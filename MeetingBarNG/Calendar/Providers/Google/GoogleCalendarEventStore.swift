//
//  GCEventStore.swift
//  MeetingBar
//
//  Created by Andrii Leitsius on 21.11.2021.
//  Copyright © 2021 Andrii Leitsius. All rights reserved.
//

import AppAuth
import AppAuthCore
import AppKit
import Defaults
import Foundation

/// Google OAuth configuration, read from the app's Info.plist (populated at
/// build time from `XCConfig/GoogleSecrets.xcconfig` — see README). Reads are
/// non-crashing: a missing or still-placeholder value simply leaves
/// `isConfigured == false`, and `GCEventStore.signIn` throws
/// `AuthError.notConfigured` instead of trapping on a force-unwrap.
enum GoogleOAuthConfig {
    /// The build's client id. `GOOGLE_CLIENT_ID` is the current name and takes
    /// either the full id or just the number; `GOOGLE_CLIENT_NUMBER` is the
    /// former name, still read so an existing `GoogleSecrets.xcconfig` keeps
    /// working. `GoogleOAuthClientResolver` normalizes whichever form arrives.
    static let clientNumber: String = {
        let current = infoString("GOOGLE_CLIENT_ID")
        guard GoogleOAuthClientResolver.isValidClientID(current) else {
            return infoString("GOOGLE_CLIENT_NUMBER")
        }
        return current
    }()
    static let clientSecret = infoString("GOOGLE_CLIENT_SECRET")
    static let keychainName = infoString("GOOGLE_AUTH_KEYCHAIN_NAME")

    /// The client secret as AppAuth must receive it: `nil` when there isn't one.
    ///
    /// This is NOT cosmetic. AppAuth branches on `if (_clientSecret)` in
    /// Objective-C, where an empty `NSString` is a non-nil object and therefore
    /// TRUE. Handing it `""` makes it authenticate the token request with
    /// `Authorization: Basic base64("<id>:")` instead of putting `client_id` in
    /// the body — and Google rejects that with `invalid_client` for an
    /// "iOS"-type client, which is the type this app's reversed-domain redirect
    /// wants and the one the setup docs recommend. So the recommended,
    /// no-secret configuration was the one that could not sign in.
    static var oauthClientSecret: String? { normalizedSecret(clientSecret) }

    /// Pure so the empty-vs-nil distinction above is testable without the
    /// ambient build's Info.plist.
    static func normalizedSecret(_ secret: String) -> String? {
        secret.isEmpty ? nil : secret
    }

    /// True when the current build carries real OAuth credentials.
    ///
    /// This is about the BUILD only. Whether Google can actually be used is
    /// `effectiveClient != nil`, which is also satisfied by a user-supplied
    /// client — a build shipping no credentials is still fully usable by
    /// bringing your own.
    static var isConfigured: Bool {
        isConfigured(clientNumber: clientNumber, clientSecret: clientSecret, keychainName: keychainName)
    }

    /// Pure validation, split out so it's unit-testable without depending on the
    /// ambient build's Info.plist. The client number and keychain name must be
    /// real (non-empty, not the build placeholder); the client secret may be
    /// empty — "iOS"-type OAuth clients (whose reversed-domain redirect scheme
    /// this app uses) have none — but must not be left as the placeholder.
    static func isConfigured(clientNumber: String, clientSecret: String, keychainName: String) -> Bool {
        !clientNumber.isEmpty && !clientNumber.hasPrefix("REPLACE_BY_YOUR")
            && !keychainName.isEmpty && !keychainName.hasPrefix("REPLACE_BY_YOUR")
            && !clientSecret.hasPrefix("REPLACE_BY_YOUR")
    }

    private static func infoString(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
    }
}

let googleClientNumber = GoogleOAuthConfig.clientNumber
let googleAuthKeychainName = GoogleOAuthConfig.keychainName
// No `googleClientSecret` alias on purpose: the only correct way to hand the
// secret to AppAuth is `GoogleOAuthConfig.oauthClientSecret`, which maps "no
// secret" to nil rather than "". A convenience alias for the raw string is what
// made passing `""` straight through look reasonable.

extension OIDServiceConfiguration: @unchecked @retroactive Sendable {}

extension OIDAuthState {
    /// token is considered fresh if it expires later than 300 seconds from now
    var isTokenFresh: Bool {
        guard let exp = lastTokenResponse?.accessTokenExpirationDate else { return false }
        return exp > Date().addingTimeInterval(300)
    }

    /// The signed-in account address, from the ID token's `email` claim.
    ///
    /// Decoding lives in `GoogleIDToken` because the payload is base64URL and
    /// `Data(base64Encoded:)` rejects it — see that file. The version here
    /// decoded it as standard base64, so this was very nearly always nil and
    /// every Google calendar ended up filed under "Other".
    var userEmail: String? {
        GoogleIDToken.email(fromIDToken: lastTokenResponse?.idToken)
    }
}

// MARK: - GCEventStore
@MainActor
final class GCEventStore: NSObject,
                           AuthenticatedEventStore,
                           @preconcurrency OIDExternalUserAgent,
                          @preconcurrency OIDAuthStateChangeDelegate,
                          @preconcurrency OIDAuthStateErrorDelegate {

    // MARK: Static constants
    private static let kIssuer       = "https://accounts.google.com"
    private static let kKeychainName = googleAuthKeychainName

    /// Loopback HTTP listener that receives the OAuth redirect.
    ///
    /// REPLACES the reversed-domain custom scheme
    /// (`com.googleusercontent.apps.<n>:/oauthredirect`). Two reasons, either
    /// sufficient:
    ///
    /// 1. A custom scheme has to be declared in `CFBundleURLTypes` at BUILD
    ///    time, so a client id supplied at RUNTIME could never receive its
    ///    redirect — bring-your-own-client is impossible with it.
    /// 2. Google documents loopback as the recommended redirect for macOS
    ///    desktop apps and is retiring custom schemes over app-impersonation
    ///    risk: any other app on the Mac can register the same scheme and
    ///    intercept the redirect. PKCE keeps an intercepted code unusable, but
    ///    not receiving it at all is better.
    ///
    /// Held per sign-in and torn down after; requires the
    /// `com.apple.security.network.server` entitlement, which is scoped to
    /// 127.0.0.1 on an ephemeral port for the duration of the flow.
    private var redirectHandler: OIDRedirectHTTPHandler?

    /// Serves the branded "connected" page the browser is sent to afterwards.
    /// Separate from `redirectHandler` on purpose: AppAuth keeps the whole
    /// OAuth-critical path, and this only serves HTML.
    private let completionPage = OAuthCompletionPageServer()

    // MARK: Stored properties
    @MainActor var currentAuthorizationFlow: OIDExternalUserAgentSession?
    private(set) var userEmail: String?

    private var authState: OIDAuthState? {
        didSet {
            // ensure delegates always set
            authState?.stateChangeDelegate = self
            authState?.errorDelegate       = self
            // Keep the account address in step with the session that carries it,
            // including when a token refresh replaces the state.
            userEmail = authState?.userEmail
            persistAuthState()
        }
    }

    private var signInTask: Task<Void, Error>?
    private var refreshTask: Task<String, Error>?

    // Shared URLSession to leverage connection reuse
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.waitsForConnectivity          = true
        return URLSession(configuration: cfg)
    }()
    private var urlSession: URLSession { Self.session }

    // Singleton
    static let shared = GCEventStore()
    private override init() {
        super.init()
        self.authState = restoreAuthState()
        // delegates were set in didSet, but set them again just in case restore returned nil
        self.authState?.stateChangeDelegate = self
        self.authState?.errorDelegate       = self
        // `didSet` does not run for assignments inside `init`, so the restored
        // session's address has to be picked up explicitly. Without this the
        // account was known only for the launch you signed in on, and every
        // relaunch filed Google's calendars under "Other" again.
        self.userEmail = self.authState?.userEmail
    }

    // MARK: Public API

    var isAuthorized: Bool { authState?.isAuthorized == true }

    func signIn(forcePrompt: Bool = false) async throws {
        // Fail gracefully when there is no usable client — this build carries no
        // credentials, or the user turned on their own and it is unusable —
        // rather than starting a flow that cannot succeed.
        guard let client = GoogleOAuthConfig.effectiveClient,
              let issuerURL = URL(string: Self.kIssuer)
        else {
            throw AuthError.notConfigured
        }

        // Tokens are bound to the client that obtained them. If the stored
        // session belongs to a different client (the user switched to their own,
        // or edited the id), drop it rather than replaying a refresh token the
        // new client cannot use — that surfaces as `invalid_grant`, which reads
        // like a broken account rather than a changed setting.
        //
        // BEFORE the reusable-session check on purpose. The stored tokens still
        // look perfectly valid — they are another client's valid tokens — so
        // skipping first would keep using them until they expired, and only then
        // fail on a refresh the new client cannot perform.
        discardAuthStateIfClientChanged(to: client)

        if Self.shouldSkipSignIn(forcePrompt: forcePrompt, state: authState) {
            return
        }

        // Start the page server first so its URL exists to hand to AppAuth. If
        // it cannot bind, `successURL` stays nil and AppAuth serves its own
        // plain page — worth losing the branding over, never worth failing the
        // sign-in over.
        let successURL = await completionPage.start()

        // Start the loopback listener BEFORE building the request: the redirect
        // URI has to carry the port it actually bound to.
        let handler = OIDRedirectHTTPHandler(successURL: successURL)
        redirectHandler = handler
        var listenerError: NSError?
        let redirectURL = handler.startHTTPListener(&listenerError)
        if let listenerError {
            redirectHandler = nil
            throw listenerError
        }

        // discover configuration for Google issuer
        let config = try await withCheckedThrowingContinuation { cont in
            OIDAuthorizationService.discoverConfiguration(forIssuer: issuerURL) { cfg, err in
                if let cfg { cont.resume(returning: cfg) } else { cont.resume(throwing: err ?? NSError(domain: "GoogleSignIn", code: -1)) }
            }
        }

        // request scopes we need
        let scopes = [
            "email",
            "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
            "https://www.googleapis.com/auth/calendar.events.readonly"
        ]

        // additional parameters to be sure we get refresh_token
        var extra = [
            "access_type": "offline"
        ]
        if forcePrompt {
            extra["prompt"] = "consent"
        }

        let request = OIDAuthorizationRequest(
            configuration: config,
            clientId: client.clientID,
            clientSecret: client.clientSecret,
            scopes: scopes,
            redirectURL: redirectURL,
            responseType: OIDResponseTypeCode,
            additionalParameters: extra
        )

        defer {
            // Whatever happened, stop listening. `cancelHTTPListener` is a no-op
            // once a valid response has been received.
            redirectHandler?.cancelHTTPListener()
            redirectHandler = nil
            // The page server outlives this function by design — the browser is
            // redirected to it AFTER the code is exchanged, so tearing it down
            // here would race the request it exists to answer. It is stopped on
            // the next sign-in or sign-out instead.
        }

        try await withCheckedThrowingContinuation { cont in
            let session = OIDAuthState.authState(byPresenting: request,
                                                 externalUserAgent: self) { [weak self] state, error in
                guard let self else { return }
                if let state {
                    self.authState = state    // didSet handles persistence & delegates
                    self.userEmail = state.userEmail
                    Defaults[.googleTokenClientIdentity] = client.tokenIdentity
                    // Set before the browser is redirected, so the page can name
                    // the account that was just connected.
                    self.completionPage.setAccountEmail(state.userEmail)
                    AppMessageCenter.shared.post(
                        .googleAccountConnected(email: self.userEmail ?? "")
                    )
                    cont.resume()
                } else {
                    cont.resume(throwing: Self.authorizationError(error))
                }
            }
            self.currentAuthorizationFlow = session
            // The loopback server delivers the redirect to this session; without
            // it the browser hits 127.0.0.1 and the response goes nowhere.
            handler.currentAuthorizationFlow = session
        }
    }

    /// Drops any stored session that belongs to a different OAuth client.
    private func discardAuthStateIfClientChanged(to client: GoogleOAuthClient) {
        let stored = Defaults[.googleTokenClientIdentity]
        guard !stored.isEmpty, stored != client.tokenIdentity else { return }
        MeetingBarLogger.calendar.info(
            "Google OAuth client changed; discarding the previous client's session"
        )
        clearAuthState()
    }

    private static func authorizationError(_ error: Error?) -> Error {
        guard let error else {
            return NSError(domain: "GoogleSignIn", code: 1)
        }

        let nsError = error as NSError
        let cancellationCodes = [-3, -4]
        if nsError.domain == OIDGeneralErrorDomain,
           cancellationCodes.contains(nsError.code) {
            return AuthError.cancelled
        }
        return error
    }

    func signOut() async {
        cancelPendingOperations()
        guard let state = authState else { return }

        // Revoke tokens in parallel
        let access  = state.lastTokenResponse?.accessToken
        let refresh = state.refreshToken
        await withTaskGroup(of: Void.self) { grp in
            if let acc = access { grp.addTask { try? await self.revoke(token: acc) } }
            if let ref = refresh { grp.addTask { try? await self.revoke(token: ref) } }
        }

        clearAuthState()
    }

    func cancelPendingOperations() {
        signInTask?.cancel()
        signInTask = nil
        refreshTask?.cancel()
        refreshTask = nil

        let flow = currentAuthorizationFlow
        currentAuthorizationFlow = nil
        flow?.cancel()

        // Abandoning the flow means nobody is coming to read the completion
        // page, so stop holding a socket open for it.
        redirectHandler?.cancelHTTPListener()
        redirectHandler = nil
        completionPage.stop()
    }

    func refreshSources() async {}

    func fetchAllCalendars() async throws -> [MBCalendar] {
        try await ensureSignedIn()

        let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=250&showHidden=true")!
        let items = try await fetchJSON(url)

        return items.compactMap { item -> MBCalendar? in
            guard let title = item["summary"] as? String,
                  let calendarID = item["id"] as? String,
                  let backgroundColor = item["backgroundColor"] as? String else { return nil }

            return MBCalendar(title: title,
                              id: calendarID,
                              source: userEmail,
                              email: userEmail,
                              color: hexStringToUIColor(hex: backgroundColor),
                              provider: .googleCalendar)
        }
    }

    private func getCalendarEventsForDateRange(calendar: MBCalendar,
                                               dateFrom: Date,
                                               dateTo: Date) async throws -> [MBEvent] {
        let iso = ISO8601DateFormatter()
        let timeMin = iso.string(from: dateFrom)
        let timeMax = iso.string(from: dateTo)
        let url = try Self.eventsURL(
            calendarID: calendar.id,
            timeMin: timeMin,
            timeMax: timeMax
        )

        let items = try await fetchJSON(url, calendarID: calendar.id)
        return items.compactMap { GCParser.event(from: $0, calendar: calendar) }
    }

    static func eventsURL(calendarID: String, timeMin: String, timeMax: String) throws -> URL {
        // Calendar IDs can contain `#`, `@`, `+`, and group-address punctuation.
        // Path interpolation without escaping breaks for those calendars
        // (Google returns 404). Build the path via `URLComponents.path` so
        // encoding happens once, correctly.
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "www.googleapis.com"
        comps.path = "/calendar/v3/calendars/\(calendarID)/events"
        comps.queryItems = [
            .init(name: "singleEvents", value: "true"),
            .init(name: "orderBy", value: "startTime"),
            .init(name: "eventTypes", value: "default"),
            .init(name: "timeMax", value: timeMax),
            .init(name: "timeMin", value: timeMin)
        ]
        guard let url = comps.url else {
            throw URLError(.badURL)
        }

        return url
    }

    func fetchEventsForDateRange(for calendars: [MBCalendar],
                                 from: Date,
                                 to: Date) async throws -> [MBEvent] {
        try await ensureSignedIn()
        var result: [MBEvent] = []
        var forbiddenErrors: [Error] = []
        var successfulCalendars = 0
        for cal in calendars {
            do {
                let ev = try await getCalendarEventsForDateRange(calendar: cal, dateFrom: from, dateTo: to)
                successfulCalendars += 1
                result.append(contentsOf: ev)
            } catch let error as GoogleCalendarError {
                switch error {
                case .forbiddenCalendar:
                    MeetingBarLogger.calendar.warning(
                        "Skipping inaccessible Google calendar \(cal.id, privacy: .private): \(error.localizedDescription, privacy: .private)"
                    )
                    forbiddenErrors.append(error)
                default:
                    throw error
                }
            } catch {
                throw error
            }
        }
        let deduplicated = Dictionary(result.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values
        return try GoogleCalendarBatchPolicy.finish(
            events: Array(deduplicated),
            successfulCalendars: successfulCalendars,
            forbiddenErrors: forbiddenErrors
        )
    }

    // MARK: - Private helpers
    private func ensureSignedIn() async throws {
        if Self.hasReusableSession(authState) {
            return
        }

        let forceConsent = authState?.refreshToken == nil
        if let running = signInTask { return try await running.value }

        let task = Task {
            try await signIn(forcePrompt: forceConsent)
        }
        signInTask = task
        defer { signInTask = nil }
        try await task.value
    }

    nonisolated static func hasReusableSession(_ state: OIDAuthState?) -> Bool {
        state?.isAuthorized == true && state?.refreshToken != nil
    }

    nonisolated static func shouldSkipSignIn(
        forcePrompt: Bool,
        state: OIDAuthState?
    ) -> Bool {
        !forcePrompt && hasReusableSession(state)
    }

    private func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard let state = authState else { throw AuthError.notSignedIn }

        if !forceRefresh,
           state.isTokenFresh,
           let token = state.lastTokenResponse?.accessToken {
            return token
        }

        if let running = refreshTask { return try await running.value }

        let task = Task<String, Error> {
            defer { refreshTask = nil }
            return try await withCheckedThrowingContinuation { cont in
                if forceRefresh { state.setNeedsTokenRefresh() }

                state.performAction { [weak self] accessToken, _, error in
                    guard let self else { return }
                    if let token = accessToken {
                        cont.resume(returning: token) // stateChangeDelegate persists new tokens
                    } else if let error {
                        let nsError = error as NSError
                        if nsError.domain == OIDOAuthTokenErrorDomain {
                            self.clearAuthState()
                            cont.resume(throwing: AuthError.notSignedIn)
                        } else {
                            cont.resume(throwing: error)
                        }
                    } else {
                        cont.resume(throwing: AuthError.refreshFailed)
                    }
                }
            }
        }

        refreshTask = task
        return try await task.value
    }

    // MARK: Keychain persistence

    private func persistAuthState() {
        guard let state = authState else {
            Keychain.delete(for: Self.kKeychainName)
            return
        }
        do {
            let data = try NSKeyedArchiver.archivedData(withRootObject: state, requiringSecureCoding: true)
            Keychain.save(data: data, for: Self.kKeychainName)
        } catch {
            let errorDescription = String(describing: error)
            MeetingBarLogger.calendar.error(
                "Could not archive Google auth state: \(errorDescription, privacy: .private)"
            )
        }
    }

    private func restoreAuthState() -> OIDAuthState? {
        guard let data = Keychain.load(for: Self.kKeychainName) else { return nil }
        do {
            guard let state = try NSKeyedUnarchiver.unarchivedObject(ofClass: OIDAuthState.self, from: data) else { return nil }
            userEmail = state.userEmail
            return state
        } catch {
            let errorDescription = String(describing: error)
            MeetingBarLogger.calendar.error(
                "Could not restore Google auth state: \(errorDescription, privacy: .private)"
            )
            return nil
        }
    }

    private func clearAuthState() {
        authState  = nil
        userEmail  = nil
        Keychain.delete(for: Self.kKeychainName)
        // Forget which client the (now deleted) tokens belonged to, so the next
        // sign-in is not measured against a session that no longer exists.
        Defaults[.googleTokenClientIdentity] = ""
    }

    // MARK: Networking helper
    private func fetchJSON(_ url: URL, calendarID: String? = nil, retrying: Bool = false) async throws -> [[String: Any]] {
        let token = try await validAccessToken()

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: req)

        if let http = response as? HTTPURLResponse {
            switch GoogleHTTPStatusPolicy.classify(
                statusCode: http.statusCode,
                url: url,
                calendarID: calendarID,
                retrying: retrying
            ) {
            case .proceed:
                break
            case .retryWithForcedTokenRefresh:
                _ = try await validAccessToken(forceRefresh: true)
                return try await fetchJSON(url, calendarID: calendarID, retrying: true)
            case .clearAuthAndThrowAuthRequired:
                clearAuthState()
                throw AuthError.notSignedIn
            case let .throwError(error):
                throw error
            }
        }

        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let items = root["items"] as? [[String: Any]] else {
            throw GoogleCalendarError.missingItems(url)
        }
        return items
    }

    private func revoke(token: String) async throws {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data("token=\(token)".utf8)

        let (_, resp) = try await urlSession.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "GoogleRevoke", code: (resp as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }

    // MARK: - OIDAuthState Delegates
    func didChange(_ state: OIDAuthState) {
        // persist every change (e.g., refreshed token)
        persistAuthState()
    }

    func authState(_ state: OIDAuthState, didEncounterAuthorizationError error: Error) {
        let nsErr = error as NSError
        if nsErr.domain == OIDOAuthTokenErrorDomain {
            // refresh token invalid → clean state & notify
            clearAuthState()
        }
    }

    // MARK: - OIDExternalUserAgent
    func present(_ request: OIDExternalUserAgentRequest, session _: OIDExternalUserAgentSession) -> Bool {
        if let url = request.externalUserAgentRequestURL(), NSWorkspace.shared.open(url) {
            return true
        }
        return false
    }

    func dismiss(animated _: Bool, completion: @escaping () -> Void) { completion() }

    // MARK: - Google JSON ➜ MBEvent converter
    enum GCParser {
        // swiftlint:disable:next cyclomatic_complexity
        static func event(from item: [String: Any],
                          calendar: MBCalendar) -> MBEvent? {
            guard let eventID = item["id"] as? String else {
                MeetingBarLogger.calendar.warning(
                    "Skipping Google Calendar event without a string id"
                )
                return nil
            }

            let formatter = ISO8601DateFormatter()
            let lastModifiedDate = formatter.date(from: item["updated"] as? String ?? "")
            let title = item["summary"] as? String
            var status: MBEventStatus
            switch item["status"] as? String {
            case "confirmed":
                status = .confirmed
            case "tentative":
                status = .tentative
            case "cancelled":
                status = .canceled
            default:
                status = .none
            }

            let notes = item["description"] as? String
            let location = item["location"] as? String

            // Google Calendar exposes the meeting URL through structured
            // conferenceData. Surface it as `conferenceURL` so the link
            // detector can score it ahead of any URL accidentally pasted
            // into notes (#847). The plain `url` field remains nil for
            // Google events — Google Calendar has no per-event "user URL"
            // equivalent of EKEvent.url.
            var conferenceURL: URL?
            if let conferenceData = item["conferenceData"] as? [String: Any],
               let entryPoints = conferenceData["entryPoints"] as? [[String: Any]],
               let videoEntryPoint = entryPoints.first(where: { $0["entryPointType"] as? String == "video" }) {
                conferenceURL = (videoEntryPoint["uri"] as? String).flatMap(URL.init(string:))
            }

            let organizerRaw = item["organizer"] as? [String: Any]
            let organizer = MBEventOrganizer(email: organizerRaw?["email"] as? String, name: organizerRaw?["name"] as? String)

            var attendees: [MBEventAttendee] = []
            let rawAttendees = item["attendees"] as? [[String: Any]] ?? []
            for jsonAttendee in rawAttendees {
                let email = jsonAttendee["email"] as? String
                let name = jsonAttendee["displayName"] as? String
                let optional = jsonAttendee["optional"] as? Bool ?? false
                let isCurrentUser = jsonAttendee["self"] as? Bool ?? false

                var attendeeStatus: MBEventAttendeeStatus
                switch jsonAttendee["responseStatus"] as? String {
                case "accepted":
                    attendeeStatus = .accepted
                case "declined":
                    attendeeStatus = .declined
                case "tentative":
                    attendeeStatus = .tentative
                case "needsAction":
                    attendeeStatus = .pending
                default:
                    attendeeStatus = .unknown
                }
                let attendee = MBEventAttendee(email: email, name: name, status: attendeeStatus, optional: optional, isCurrentUser: isCurrentUser)
                attendees.append(attendee)
            }

            var startDate: Date
            var endDate: Date
            var isAllDay: Bool

            guard let itemStart = item["start"] as? [String: String],
                  let itemEnd = item["end"] as? [String: String] else {
                MeetingBarLogger.calendar.warning(
                    "Skipping Google event \(eventID, privacy: .private) without valid start/end dictionaries"
                )
                return nil
            }

            if let startDateTime = itemStart["dateTime"], let endDateTime = itemEnd["dateTime"] {
                let formatter = ISO8601DateFormatter()
                guard let parsedStartDate = formatter.date(from: startDateTime),
                      let parsedEndDate = formatter.date(from: endDateTime) else {
                    MeetingBarLogger.calendar.warning(
                        "Skipping Google event \(eventID, privacy: .private) with invalid dateTime values"
                    )
                    return nil
                }
                startDate = parsedStartDate
                endDate = parsedEndDate
                isAllDay = false
            } else {
                let formatter = DateFormatter()
                // Pin a fixed locale + Gregorian calendar so the date-only
                // "yyyy-MM-dd" parse is stable regardless of the user's system
                // calendar/locale (e.g. a Buddhist or Japanese default calendar
                // would otherwise land the event on the wrong year/day). All-day
                // dates are floating, so local midnight is the correct instant —
                // do NOT force UTC.
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.dateFormat = "yyyy-MM-dd"
                guard let startDateString = itemStart["date"],
                      let endDateString = itemEnd["date"],
                      let parsedStartDate = formatter.date(from: startDateString),
                      let parsedEndDate = formatter.date(from: endDateString) else {
                    MeetingBarLogger.calendar.warning(
                        "Skipping Google event \(eventID, privacy: .private) with invalid all-day date values"
                    )
                    return nil
                }
                startDate = parsedStartDate
                endDate = parsedEndDate
                isAllDay = true
            }

            let recurrent = (item["recurringEventId"] != nil) ? true : false

            // Web link to the event in Google Calendar; used for "Open in
            // Calendar" since `ical://ekevent/<google-id>` is not valid.
            let calendarOpenURL = (item["htmlLink"] as? String).flatMap(URL.init(string:))

            return MBEvent(
                id: eventID,
                lastModifiedDate: lastModifiedDate,
                title: title,
                status: status,
                notes: notes,
                location: location,
                url: nil,
                conferenceURL: conferenceURL,
                calendarOpenURL: calendarOpenURL,
                organizer: organizer,
                attendees: attendees,
                startDate: startDate,
                endDate: endDate,
                isAllDay: isAllDay,
                recurrent: recurrent,
                calendar: calendar,
                customRegexes: Defaults[.customRegexes]
            )
        }
    }
}
