//
//  GoogleIDToken.swift
//  MeetingBarNG
//
//  Reads the signed-in account out of Google's ID token.
//
//  The account address is not cosmetic here: it is the calendar list's ACCOUNT
//  HEADING. Without it every Google calendar fell back to `MBCalendar`'s
//  "unknown" source and the list filed them all under "Other", which is exactly
//  the question the heading exists to answer.
//
//  The decoding is the whole story. A JWT payload is base64URL — `-` and `_` in
//  place of `+` and `/`, and padding stripped — which `Data(base64Encoded:)`
//  rejects outright. It returns nil rather than throwing, so the failure looked
//  like "Google didn't tell us the address" instead of "we cannot read it", and
//  every caller degraded quietly.
//
//  NOT a verification step. The token arrives over TLS from the token endpoint,
//  in response to a PKCE exchange this app started, and is used only to label a
//  row. Nothing here is a security decision, so nothing here checks a signature.
//

import Foundation

public enum GoogleIDToken {
    /// The `email` claim, or `nil` when the token is absent, malformed, or
    /// simply carries no email.
    public static func email(fromIDToken token: String?) -> String? {
        guard let claims = claims(fromIDToken: token) else { return nil }
        guard let email = claims["email"] as? String, !email.isEmpty else { return nil }
        return email
    }

    /// The token's payload claims.
    public static func claims(fromIDToken token: String?) -> [String: Any]? {
        guard let token else { return nil }
        // header.payload.signature — the payload is the middle segment. A JWT
        // has exactly three; anything else is not one.
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return nil }

        guard let payload = decodeBase64URL(String(segments[1])),
              let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
        else { return nil }
        return json
    }

    /// base64URL → Data.
    ///
    /// Two differences from standard base64, both fatal to
    /// `Data(base64Encoded:)`: the alphabet swaps `+/` for `-_`, and trailing
    /// `=` padding is stripped. Restoring both is all that is needed.
    public static func decodeBase64URL(_ value: String) -> Data? {
        guard !value.isEmpty else { return nil }

        var normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Pad up to the next multiple of 4. A remainder of 1 is impossible in
        // valid base64 and would be silently mis-decoded, so it is rejected.
        let remainder = normalized.count % 4
        switch remainder {
        case 0: break
        case 2: normalized += "=="
        case 3: normalized += "="
        default: return nil
        }

        return Data(base64Encoded: normalized)
    }
}
