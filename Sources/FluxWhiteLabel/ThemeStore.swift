import Foundation
import Combine
import os

/// Persistência e ciclo de vida do tema white label editável.
///
/// - Tema em `white-label-theme.json` no diretório do tema (dentro do
///   container por marca — `Application Support/<bundle>/<brandId>/theme/`).
/// - Logo e imagem de fundo como arquivos ao lado do JSON, referenciados por
///   nome relativo (sandbox-safe; nada de caminho absoluto persistido).
/// - Arquivo ausente/corrompido cai no tema padrão da marca — o softphone
///   nunca abre sem identidade.
@MainActor
public final class ThemeStore: ObservableObject {
    @Published public private(set) var theme: WhiteLabelTheme
    /// Bytes das imagens em memória para a UI renderizar sem tocar disco.
    @Published public private(set) var logoData: Data?
    @Published public private(set) var backgroundImageData: Data?

    public let defaultTheme: WhiteLabelTheme

    public enum StoreError: Error, Equatable, Sendable {
        case imageTooLarge(bytes: Int)
        case imageWriteFailed(String)
    }

    /// Limite defensivo: wallpaper 4K cabe com folga; impede um arquivo
    /// gigante de ir parar no container e na memória.
    public static let maxImageBytes = 20 * 1024 * 1024

    private static let themeFileName = "white-label-theme.json"
    private let directory: URL
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "dev.softphone.local",
        category: "whitelabel"
    )

    public init(directory: URL, defaultTheme: WhiteLabelTheme) {
        self.directory = directory
        self.defaultTheme = defaultTheme

        var loaded = Self.loadTheme(from: directory) ?? defaultTheme
        let logo = Self.loadImage(named: loaded.logoFileName, in: directory)
        let background = Self.loadImage(named: loaded.backgroundImageFileName, in: directory)
        // Referência a arquivo que sumiu do disco é limpa — a UI decide o
        // fallback (placeholder de logo, fundo padrão) sem estado fantasma.
        if logo == nil { loaded.logoFileName = nil }
        if background == nil {
            loaded.backgroundImageFileName = nil
            if loaded.backgroundStyle == .image { loaded.backgroundStyle = .gradient }
        }
        self.theme = loaded
        self.logoData = logo
        self.backgroundImageData = background
    }

    /// Há algo a restaurar? (`updatedAt` não conta como customização.)
    public var isCustomized: Bool {
        !theme.isEquivalent(to: defaultTheme)
    }

    // MARK: - Edição

    /// Única porta de mutação do tema: aplica a mudança, carimba `updatedAt`
    /// e persiste. Mudança vazia não gera escrita.
    public func apply(_ change: (inout WhiteLabelTheme) -> Void) {
        var updated = theme
        change(&updated)
        guard updated != theme else { return }
        updated.updatedAt = Date()
        theme = updated
        persist()
    }

    public func resetToDefault() {
        removeImageFile(named: theme.logoFileName)
        removeImageFile(named: theme.backgroundImageFileName)
        logoData = nil
        backgroundImageData = nil
        theme = defaultTheme
        persist()
        logger.info("Tema white label restaurado ao padrão da marca")
    }

    // MARK: - Imagens

    public func setLogo(_ data: Data, fileExtension: String) throws {
        let fileName = try storeImage(
            data,
            baseName: "brand-logo",
            fileExtension: fileExtension,
            replacing: theme.logoFileName
        )
        logoData = data
        apply { $0.logoFileName = fileName }
    }

    public func removeLogo() {
        removeImageFile(named: theme.logoFileName)
        logoData = nil
        apply { $0.logoFileName = nil }
    }

    public func setBackgroundImage(_ data: Data, fileExtension: String) throws {
        let fileName = try storeImage(
            data,
            baseName: "background-image",
            fileExtension: fileExtension,
            replacing: theme.backgroundImageFileName
        )
        backgroundImageData = data
        apply {
            $0.backgroundImageFileName = fileName
            $0.backgroundStyle = .image
        }
    }

    public func removeBackgroundImage() {
        removeImageFile(named: theme.backgroundImageFileName)
        backgroundImageData = nil
        apply {
            $0.backgroundImageFileName = nil
            if $0.backgroundStyle == .image { $0.backgroundStyle = .gradient }
        }
    }

    // MARK: - Exportar / importar (contrato JSON de tema por tenant)

    /// JSON do tema atual, legível e diffável. Imagens NÃO vão no export v1 —
    /// o JSON referencia nomes; o pacote de tema com assets é etapa futura.
    public func exportThemeJSON() throws -> Data {
        try Self.encoder.encode(theme)
    }

    /// Importa um tema exportado: decodifica, valida cores e descarta
    /// referências a imagens que não existem neste computador.
    public func importTheme(from data: Data) throws {
        var imported = try Self.decoder.decode(WhiteLabelTheme.self, from: data)
        try imported.validate()
        if Self.loadImage(named: imported.logoFileName, in: directory) == nil {
            imported.logoFileName = nil
        }
        if Self.loadImage(named: imported.backgroundImageFileName, in: directory) == nil {
            imported.backgroundImageFileName = nil
            if imported.backgroundStyle == .image { imported.backgroundStyle = .gradient }
        }
        logoData = Self.loadImage(named: imported.logoFileName, in: directory)
        backgroundImageData = Self.loadImage(named: imported.backgroundImageFileName, in: directory)
        apply { $0 = imported }
        logger.info("Tema white label importado")
    }

    // MARK: - Persistência

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try Self.encoder.encode(theme)
            try data.write(to: directory.appendingPathComponent(Self.themeFileName), options: .atomic)
        } catch {
            // Falha de disco não pode derrubar o app: o tema segue em memória
            // e a próxima edição tenta gravar de novo.
            logger.error("Falha ao persistir tema white label: \(String(describing: error), privacy: .public)")
        }
    }

    private static func loadTheme(from directory: URL) -> WhiteLabelTheme? {
        let url = directory.appendingPathComponent(themeFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode(WhiteLabelTheme.self, from: data)
        } catch {
            Logger(
                subsystem: Bundle.main.bundleIdentifier ?? "dev.softphone.local",
                category: "whitelabel"
            ).error("Tema white label corrompido; usando padrão: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private static func loadImage(named fileName: String?, in directory: URL) -> Data? {
        guard let fileName, isSafeFileName(fileName) else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(fileName))
    }

    /// Nome de arquivo vindo do JSON não pode escapar do diretório do tema.
    private static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.contains("\\") && name != ".." && !name.hasPrefix(".")
    }

    /// Grava a imagem como `<baseName>.<ext>` e remove o arquivo anterior se
    /// o nome mudou (ex.: logo .png substituído por .jpg).
    private func storeImage(
        _ data: Data,
        baseName: String,
        fileExtension: String,
        replacing previous: String?
    ) throws -> String {
        guard data.count <= Self.maxImageBytes else {
            throw StoreError.imageTooLarge(bytes: data.count)
        }
        let sanitized = fileExtension
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        let fileName = "\(baseName).\(sanitized.isEmpty ? "png" : sanitized)"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        } catch {
            logger.error("Falha ao gravar imagem do tema: \(String(describing: error), privacy: .public)")
            throw StoreError.imageWriteFailed(String(describing: error))
        }
        if let previous, previous != fileName {
            removeImageFile(named: previous)
        }
        return fileName
    }

    private func removeImageFile(named fileName: String?) {
        guard let fileName, Self.isSafeFileName(fileName) else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(fileName))
    }
}
