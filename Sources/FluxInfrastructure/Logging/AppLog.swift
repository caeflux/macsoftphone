import Foundation
import os

/// Loggers estruturados por categoria via `os.Logger` (visíveis no Console.app).
///
/// Regra (docs/05_SECURITY_PRIVACY.md): nunca logar senha, token ou header de
/// autorização. Para dados de conta use `LogSanitizer` ou a `description`
/// já mascarada de `SIPAccount`.
public enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "dev.softphone.local"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let sip = Logger(subsystem: subsystem, category: "sip")
    public static let audio = Logger(subsystem: subsystem, category: "audio")
    public static let whiteLabel = Logger(subsystem: subsystem, category: "whitelabel")
    public static let persistence = Logger(subsystem: subsystem, category: "persistence")
}
