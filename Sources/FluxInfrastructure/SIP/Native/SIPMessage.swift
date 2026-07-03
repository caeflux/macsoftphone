import Foundation
import FluxDomain

/// Constrói mensagens SIP em texto (RFC 3261). Puro e testável.
enum SIPRequestBuilder {
    struct RegisterParameters {
        let account: SIPAccount
        let callId: String
        let cseq: Int
        let fromTag: String
        let branch: String
        let localHost: String
        let localPort: Int
        let expires: Int
        let userAgent: String
        /// Valor completo do header de autorização, quando respondendo a um
        /// challenge. O nome do header depende de quem desafiou (401 ou 407).
        let authorization: (name: String, value: String)?
    }

    static func register(_ p: RegisterParameters) -> String {
        let domain = p.account.domain
        let addressOfRecord = "sip:\(p.account.username)@\(domain)"
        var headers = [
            ("From", "<\(addressOfRecord)>;tag=\(p.fromTag)"),
            ("To", "<\(addressOfRecord)>"),
            ("Call-ID", p.callId),
            ("CSeq", "\(p.cseq) REGISTER"),
            ("Contact", contact(account: p.account, host: p.localHost, port: p.localPort)),
            ("Expires", "\(p.expires)"),
            ("User-Agent", p.userAgent)
        ]
        if let authorization = p.authorization {
            headers.append((authorization.name, authorization.value))
        }
        return request(
            method: "REGISTER",
            uri: "sip:\(domain)",
            via: via(account: p.account, host: p.localHost, port: p.localPort, branch: p.branch),
            headers: headers,
            body: nil
        )
    }

    /// Requisição genérica com Via/Max-Forwards/Content-Length calculados.
    /// `routes`: route-set do diálogo (Record-Route capturado) — requisições
    /// em diálogo SEM esses headers são descartadas por proxies que fizeram
    /// record-routing (sintoma clássico: BYE com "ACK Timeout").
    static func request(
        method: String,
        uri: String,
        via: String,
        routes: [String] = [],
        headers: [(String, String)],
        body: String?,
        contentType: String? = nil
    ) -> String {
        var lines = ["\(method) \(uri) SIP/2.0", "Via: \(via)", "Max-Forwards: 70"]
        for route in routes {
            lines.append("Route: \(route)")
        }
        for (name, value) in headers {
            lines.append("\(name): \(value)")
        }
        let bodyText = body ?? ""
        if let contentType, !bodyText.isEmpty {
            lines.append("Content-Type: \(contentType)")
        }
        lines.append("Content-Length: \(bodyText.utf8.count)")
        return lines.joined(separator: "\r\n") + "\r\n\r\n" + bodyText
    }

    /// Resposta a uma requisição recebida: ecoa Via/From/Call-ID/CSeq e
    /// usa o To informado (com nossa tag quando formos o atendido).
    static func response(
        status: Int,
        reason: String,
        to request: SIPRequest,
        toHeader: String,
        extraHeaders: [(String, String)] = [],
        body: String? = nil,
        contentType: String? = nil
    ) -> String {
        var lines = ["SIP/2.0 \(status) \(reason)"]
        for viaValue in request.headers(named: "Via") {
            lines.append("Via: \(viaValue)")
        }
        if let from = request.firstHeader("From") {
            lines.append("From: \(from)")
        }
        lines.append("To: \(toHeader)")
        if let callId = request.firstHeader("Call-ID") {
            lines.append("Call-ID: \(callId)")
        }
        if let cseq = request.firstHeader("CSeq") {
            lines.append("CSeq: \(cseq)")
        }
        for (name, value) in extraHeaders {
            lines.append("\(name): \(value)")
        }
        let bodyText = body ?? ""
        if let contentType, !bodyText.isEmpty {
            lines.append("Content-Type: \(contentType)")
        }
        lines.append("Content-Length: \(bodyText.utf8.count)")
        return lines.joined(separator: "\r\n") + "\r\n\r\n" + bodyText
    }

    static func via(account: SIPAccount, host: String, port: Int, branch: String) -> String {
        "SIP/2.0/\(account.transport.rawValue.uppercased()) \(host):\(port);branch=\(branch);rport"
    }

    static func contact(account: SIPAccount, host: String, port: Int) -> String {
        "<sip:\(account.username)@\(host):\(port);transport=\(account.transport.rawValue)>"
    }
}

/// Cabeçalhos compartilhados entre requisição e resposta.
protocol SIPMessageHeaders {
    var headerList: [(name: String, value: String)] { get }
    var body: String { get }
}

extension SIPMessageHeaders {
    func firstHeader(_ name: String) -> String? {
        headerList.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    func headers(named name: String) -> [String] {
        headerList.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map(\.value)
    }
}

/// Resposta SIP parseada.
struct SIPResponse: Sendable, SIPMessageHeaders {
    let statusCode: Int
    let reasonPhrase: String
    let headerList: [(name: String, value: String)]
    let body: String

    static func parse(_ raw: String) -> SIPResponse? {
        guard let (statusLine, headers, body) = SIPMessageParsing.split(raw),
              statusLine.hasPrefix("SIP/2.0 ")
        else { return nil }

        let afterVersion = statusLine.dropFirst("SIP/2.0 ".count)
        guard let code = Int(afterVersion.prefix(3)), (100...699).contains(code) else { return nil }
        let reason = afterVersion.dropFirst(3).trimmingCharacters(in: .whitespaces)
        return SIPResponse(statusCode: code, reasonPhrase: reason, headerList: headers, body: body)
    }
}

/// Requisição SIP recebida do servidor (INVITE, BYE, CANCEL, OPTIONS...).
struct SIPRequest: Sendable, SIPMessageHeaders {
    let method: String
    let uri: String
    let headerList: [(name: String, value: String)]
    let body: String

    static func parse(_ raw: String) -> SIPRequest? {
        guard let (requestLine, headers, body) = SIPMessageParsing.split(raw),
              requestLine.hasSuffix(" SIP/2.0")
        else { return nil }

        let parts = requestLine.split(separator: " ")
        guard parts.count == 3 else { return nil }
        let method = String(parts[0])
        guard method.uppercased() == method, !method.isEmpty else { return nil }
        return SIPRequest(method: method, uri: String(parts[1]), headerList: headers, body: body)
    }
}

enum SIPMessageParsing {
    /// Divide uma mensagem em (primeira linha, headers, corpo).
    static func split(_ raw: String) -> (firstLine: String, headers: [(String, String)], body: String)? {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let sections = normalized.split(separator: "\n\n", maxSplits: 1, omittingEmptySubsequences: false)
        let head = sections[0]
        let body = sections.count > 1 ? String(sections[1]) : ""

        var lines = head.split(separator: "\n", omittingEmptySubsequences: false)[...]
        guard let firstLine = lines.first, !firstLine.isEmpty else { return nil }
        lines = lines.dropFirst()

        var headers: [(String, String)] = []
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            headers.append((name, value))
        }
        return (String(firstLine), headers, body)
    }
}

/// Extração de pedaços de headers SIP — puro e testável.
enum SIPHeaderTools {
    /// `<sip:1001@dominio>;tag=abc` → `abc`
    static func tag(fromHeaderValue value: String) -> String? {
        for part in value.split(separator: ";").dropFirst() {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("tag=") {
                return String(trimmed.dropFirst(4))
            }
        }
        return nil
    }

    /// `"Nome" <sip:1001@dominio>;tag=x` → `sip:1001@dominio`
    static func uri(fromHeaderValue value: String) -> String? {
        if let open = value.firstIndex(of: "<"), let close = value.firstIndex(of: ">"), open < close {
            return String(value[value.index(after: open)..<close])
        }
        let bare = value.split(separator: ";").first.map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        return bare?.isEmpty == false ? bare : nil
    }

    /// `sip:1001@dominio:porta;params` → `1001`
    static func user(fromURI uri: String) -> String? {
        var value = uri
        if let colon = value.range(of: ":") { value = String(value[colon.upperBound...]) }
        guard let at = value.firstIndex(of: "@") else { return nil }
        let user = String(value[..<at])
        return user.isEmpty ? nil : user
    }

    /// Display name antes do `<...>`, sem aspas.
    static func displayName(fromHeaderValue value: String) -> String? {
        guard let open = value.firstIndex(of: "<") else { return nil }
        var name = String(value[..<open]).trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("\""), name.hasSuffix("\""), name.count >= 2 {
            name = String(name.dropFirst().dropLast())
        }
        return name.isEmpty ? nil : name
    }

    /// Branch do Via: `SIP/2.0/UDP host;branch=z9hG4bKx;rport` → `z9hG4bKx`
    static func branch(fromVia value: String) -> String? {
        for part in value.split(separator: ";").dropFirst() {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.lowercased().hasPrefix("branch=") {
                return String(trimmed.dropFirst("branch=".count))
            }
        }
        return nil
    }

    /// `CSeq: 2 INVITE` → (2, "INVITE")
    static func cseq(fromHeaderValue value: String) -> (number: Int, method: String)? {
        let parts = value.split(separator: " ")
        guard parts.count == 2, let number = Int(parts[0]) else { return nil }
        return (number, String(parts[1]))
    }

    /// Entradas de Record-Route/Route: cada header pode conter várias,
    /// separadas por vírgula FORA dos `<>` (URIs contêm vírgulas raramente,
    /// mas parâmetros podem).
    static func routeEntries(fromHeaderValues values: [String]) -> [String] {
        var entries: [String] = []
        for value in values {
            var current = ""
            var angleDepth = 0
            for character in value {
                if character == "<" { angleDepth += 1 }
                if character == ">" { angleDepth = max(0, angleDepth - 1) }
                if character == ",", angleDepth == 0 {
                    let trimmed = current.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { entries.append(trimmed) }
                    current = ""
                } else {
                    current.append(character)
                }
            }
            let trimmed = current.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { entries.append(trimmed) }
        }
        return entries
    }
}
