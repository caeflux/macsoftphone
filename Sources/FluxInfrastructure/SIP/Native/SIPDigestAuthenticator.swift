import Foundation
import CryptoKit

/// Challenge de um `WWW-Authenticate`/`Proxy-Authenticate: Digest ...`.
struct SIPDigestChallenge: Equatable, Sendable {
    let realm: String
    let nonce: String
    let qop: String?
    let opaque: String?
    let algorithm: String?

    /// Aceita o valor completo do header (com ou sem o prefixo `Digest`).
    static func parse(fromHeader header: String) -> SIPDigestChallenge? {
        var body = header.trimmingCharacters(in: .whitespaces)
        if body.lowercased().hasPrefix("digest") {
            body = String(body.dropFirst("digest".count))
        }
        let params = parseParameters(body)
        guard let realm = params["realm"], let nonce = params["nonce"] else { return nil }
        return SIPDigestChallenge(
            realm: realm,
            nonce: nonce,
            qop: params["qop"],
            opaque: params["opaque"],
            algorithm: params["algorithm"]
        )
    }

    /// Divide `k1="v1", k2=v2, ...` respeitando vírgulas dentro de aspas.
    static func parseParameters(_ input: String) -> [String: String] {
        var result: [String: String] = [:]
        var current = ""
        var insideQuotes = false
        var parts: [String] = []

        for character in input {
            if character == "\"" { insideQuotes.toggle() }
            if character == ",", !insideQuotes {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)

        for part in parts {
            guard let equals = part.firstIndex(of: "=") else { continue }
            let key = part[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            var value = part[part.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            guard !key.isEmpty else { continue }
            result[key] = value
        }
        return result
    }
}

/// Cálculo de digest (RFC 2617, algoritmo MD5, com e sem `qop=auth`).
/// Funções puras — a senha entra e sai daqui apenas em memória, nunca em log.
enum SIPDigestAuthenticator {
    /// Monta o valor do header `Authorization`/`Proxy-Authorization`.
    static func authorizationHeaderValue(
        username: String,
        password: String,
        method: String,
        uri: String,
        challenge: SIPDigestChallenge,
        cnonce: String,
        nonceCount: Int
    ) -> String {
        let ha1 = md5("\(username):\(challenge.realm):\(password)")
        let ha2 = md5("\(method):\(uri)")
        let usesQopAuth = challenge.qop?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .contains("auth") ?? false
        let nc = String(format: "%08x", nonceCount)

        let response: String
        if usesQopAuth {
            response = md5("\(ha1):\(challenge.nonce):\(nc):\(cnonce):auth:\(ha2)")
        } else {
            response = md5("\(ha1):\(challenge.nonce):\(ha2)")
        }

        var fields = [
            "username=\"\(username)\"",
            "realm=\"\(challenge.realm)\"",
            "nonce=\"\(challenge.nonce)\"",
            "uri=\"\(uri)\"",
            "response=\"\(response)\"",
            "algorithm=MD5"
        ]
        if usesQopAuth {
            fields.append("qop=auth")
            fields.append("nc=\(nc)")
            fields.append("cnonce=\"\(cnonce)\"")
        }
        if let opaque = challenge.opaque {
            fields.append("opaque=\"\(opaque)\"")
        }
        return "Digest " + fields.joined(separator: ", ")
    }

    static func md5(_ input: String) -> String {
        Insecure.MD5.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
