//
//  OAuthCompletionPage.swift
//  MeetingBarNG
//
//  The page the browser lands on after Google hands back the authorization
//  code.
//
//  AppAuth answers the redirect with a hardcoded
//  `<html><body>Authorization complete.<br> Return to the app.</body></html>` —
//  unstyled, unbranded, and silent about what to do next. It cannot be replaced:
//  the string is a compile-time constant and `OIDLoopbackHTTPServer` is not in
//  AppAuth's umbrella header, so the only lever is `successURL`, which makes it
//  302 somewhere of our choosing.
//
//  So this serves that somewhere, from a second loopback listener of our own.
//  The split matters: AppAuth keeps the ENTIRE OAuth-critical path — receiving
//  the code, checking `state`, the PKCE exchange. This listener is a static file
//  server for exactly one page. It never sees the authorization code, parses
//  nothing out of the request, and cannot affect whether sign-in succeeds.
//
//  Local rather than a hosted URL so the page works offline, needs no
//  infrastructure, and does not tell a web server every time someone connects
//  their calendar.
//

import Foundation
import Network

/// Serves the single "you're connected" page on 127.0.0.1.
///
/// Deliberately not a general HTTP server: every request on the socket gets the
/// same response regardless of method or path, because the only client is a
/// browser this app just redirected here.
@MainActor
final class OAuthCompletionPageServer {
    private var listener: NWListener?
    private var connections: [NWConnection] = []

    /// The account to name on the page. Set before the redirect arrives.
    private var accountEmail: String?

    /// Starts listening and returns the URL to redirect the browser to, or `nil`
    /// when the listener cannot bind.
    ///
    /// AWAITS `.ready` before reading the port. `NWListener.port` is not
    /// assigned at `start()` — it reads 0 until the kernel has bound the socket,
    /// which produced a `successURL` of `http://127.0.0.1:0/connected` that no
    /// browser can reach. Nothing would have reported it either: the redirect
    /// happens after the code is exchanged, so sign-in still succeeds and only
    /// the final page breaks.
    ///
    /// A failure here is not fatal and must not be treated as one: without a
    /// `successURL` AppAuth simply serves its own plain page, so sign-in still
    /// completes. Losing the branding is a far better outcome than failing the
    /// connection over it.
    func start() async -> URL? {
        stop()

        let listener: NWListener
        do {
            // Port 0 asks the kernel for any free port. `requiredInterfaceType`
            // alone does not keep this off the network, so the URL below names
            // the loopback address explicitly.
            let parameters = NWParameters.tcp
            parameters.requiredInterfaceType = .loopback
            parameters.allowLocalEndpointReuse = true
            listener = try NWListener(using: parameters, on: .any)
        } catch {
            PunctualLogger.calendar.error(
                "Could not create the OAuth completion page listener: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }

        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in self?.accept(connection) }
        }
        self.listener = listener

        // `stateUpdateHandler` can fire more than once (a `.failed` after a
        // `.ready`, or a `.cancelled` on teardown) and the continuation may be
        // resumed exactly once. A plain captured `var` cannot express that under
        // strict concurrency, so the one-shot claim is its own type.
        let resumeOnce = OneShotGuard()
        let port: UInt16? = await withCheckedContinuation { continuation in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard resumeOnce.claim() else { return }
                    continuation.resume(returning: listener.port?.rawValue)
                case .failed, .cancelled:
                    guard resumeOnce.claim() else { return }
                    continuation.resume(returning: nil)
                default:
                    break
                }
            }
            listener.start(queue: .main)
        }

        guard let port, port != 0 else {
            stop()
            return nil
        }
        return URL(string: "http://127.0.0.1:\(port)/connected")
    }

    /// Names the connected account on the page. Called once the token response
    /// has been parsed, which happens before the browser is redirected here.
    func setAccountEmail(_ email: String?) {
        accountEmail = email
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: .main)
        // The request is read and discarded: nothing in it changes the response,
        // and reading it lets the browser finish sending before we reply.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] _, _, _, _ in
            Task { @MainActor in self?.respond(on: connection) }
        }
    }

    private func respond(on connection: NWConnection) {
        let body = Data(OAuthCompletionPage.html(accountEmail: accountEmail).utf8)
        let headers = [
            "HTTP/1.1 200 OK",
            "Content-Type: text/html; charset=utf-8",
            "Content-Length: \(body.count)",
            // The page names an account, so keep it out of any cache.
            "Cache-Control: no-store",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")

        connection.send(
            content: Data(headers.utf8) + body,
            completion: .contentProcessed { _ in
                connection.cancel()
            }
        )
    }
}

/// Lets exactly one caller through, so a continuation resumed from a callback
/// that can fire repeatedly is resumed once.
private final class OneShotGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}

/// The page itself, as a pure function so its content is testable without
/// binding a socket.
enum OAuthCompletionPage {
    /// Inline everything: the browser is talking to a socket that is about to
    /// close, so there is no second request for a stylesheet or an image, and
    /// the page has to render correctly on the first and only response.
    ///
    /// Colours follow the system light/dark preference rather than picking one,
    /// since this opens in whatever browser the user has and should not flash
    /// white at someone working in the dark.
    static func html(accountEmail: String?) -> String {
        let account = accountEmail.flatMap { $0.isEmpty ? nil : $0 }
        let accountLine = account.map {
            "<p class=\"account\">\(escape($0))</p>"
        } ?? ""

        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape("oauth_page_title".loco()))</title>
        <style>
          :root {
            color-scheme: light dark;
            --bg: #f5f5f7;
            --card: #ffffff;
            --text: #1d1d1f;
            --muted: #6e6e73;
            --accent: #34c759;
            --border: rgba(0, 0, 0, 0.08);
          }
          @media (prefers-color-scheme: dark) {
            :root {
              --bg: #1c1c1e;
              --card: #2c2c2e;
              --text: #f5f5f7;
              --muted: #a1a1a6;
              --border: rgba(255, 255, 255, 0.1);
            }
          }
          * { box-sizing: border-box; }
          body {
            margin: 0;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 24px;
            background: var(--bg);
            color: var(--text);
            font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, sans-serif;
          }
          .card {
            width: 100%;
            max-width: 420px;
            background: var(--card);
            border: 1px solid var(--border);
            border-radius: 14px;
            padding: 32px;
            text-align: center;
          }
          .check {
            width: 48px;
            height: 48px;
            margin: 0 auto 20px;
            border-radius: 50%;
            background: var(--accent);
            display: flex;
            align-items: center;
            justify-content: center;
          }
          .check svg { width: 26px; height: 26px; }
          h1 { margin: 0 0 8px; font-size: 20px; font-weight: 600; letter-spacing: -0.01em; }
          .account {
            margin: 0 0 20px;
            font-size: 14px;
            color: var(--muted);
            word-break: break-all;
          }
          p.next { margin: 0; font-size: 14px; color: var(--muted); }
          .app { margin-top: 24px; font-size: 12px; color: var(--muted); }
        </style>
        </head>
        <body>
          <main class="card">
            <div class="check" aria-hidden="true">
              <svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="3"
                   stroke-linecap="round" stroke-linejoin="round">
                <path d="M4 12.5l5.5 5.5L20 7"/>
              </svg>
            </div>
            <h1>\(escape("oauth_page_heading".loco()))</h1>
            \(accountLine)
            <p class="next">\(escape("oauth_page_next_steps".loco()))</p>
            <p class="app">Punctual</p>
          </main>
        </body>
        </html>
        """
    }

    /// The account address comes from Google's ID token, so it is not ours to
    /// trust unescaped in markup.
    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
