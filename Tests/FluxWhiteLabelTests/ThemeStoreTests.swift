import Testing
import Foundation
@testable import FluxWhiteLabel

@Suite("ThemeStore")
@MainActor
struct ThemeStoreTests {
    private let defaultTheme = WhiteLabelTheme.defaultTheme(for: .neutralFallback)

    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("theme-store-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    @Test("sem arquivo persistido, abre com o tema padrão")
    func opensWithDefaultWhenEmpty() {
        let store = ThemeStore(directory: makeTempDirectory(), defaultTheme: defaultTheme)

        #expect(store.theme == defaultTheme)
        #expect(!store.isCustomized)
        #expect(store.logoData == nil)
        #expect(store.backgroundImageData == nil)
    }

    @Test("apply persiste e uma nova instância lê de volta")
    func applyPersistsAcrossInstances() {
        let directory = makeTempDirectory()
        let store = ThemeStore(directory: directory, defaultTheme: defaultTheme)

        store.apply {
            $0.brandName = "Revenda X"
            $0.primaryColor = "#123456"
            $0.glassOpacity = 0.4
        }
        #expect(store.isCustomized)

        let reloaded = ThemeStore(directory: directory, defaultTheme: defaultTheme)
        #expect(reloaded.theme.brandName == "Revenda X")
        #expect(reloaded.theme.primaryColor == "#123456")
        #expect(reloaded.theme.glassOpacity == 0.4)
        #expect(reloaded.theme.updatedAt > .distantPast)
    }

    @Test("arquivo corrompido cai no tema padrão")
    func corruptFileFallsBackToDefault() throws {
        let directory = makeTempDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: directory.appendingPathComponent("white-label-theme.json"))

        let store = ThemeStore(directory: directory, defaultTheme: defaultTheme)
        #expect(store.theme == defaultTheme)
    }

    @Test("logo é gravado, recarregado e removível")
    func logoLifecycle() throws {
        let directory = makeTempDirectory()
        let store = ThemeStore(directory: directory, defaultTheme: defaultTheme)
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])

        try store.setLogo(bytes, fileExtension: "png")
        #expect(store.logoData == bytes)
        #expect(store.theme.logoFileName == "brand-logo.png")

        let reloaded = ThemeStore(directory: directory, defaultTheme: defaultTheme)
        #expect(reloaded.logoData == bytes)

        reloaded.removeLogo()
        #expect(reloaded.logoData == nil)
        #expect(reloaded.theme.logoFileName == nil)
        let final = ThemeStore(directory: directory, defaultTheme: defaultTheme)
        #expect(final.logoData == nil)
    }

    @Test("trocar extensão do logo remove o arquivo anterior")
    func changingLogoExtensionRemovesOldFile() throws {
        let directory = makeTempDirectory()
        let store = ThemeStore(directory: directory, defaultTheme: defaultTheme)

        try store.setLogo(Data([1]), fileExtension: "png")
        try store.setLogo(Data([2]), fileExtension: "jpg")

        #expect(store.theme.logoFileName == "brand-logo.jpg")
        let oldFile = directory.appendingPathComponent("brand-logo.png")
        #expect(!FileManager.default.fileExists(atPath: oldFile.path))
    }

    @Test("imagem acima do limite é rejeitada")
    func oversizedImageIsRejected() {
        let store = ThemeStore(directory: makeTempDirectory(), defaultTheme: defaultTheme)
        let oversized = Data(count: ThemeStore.maxImageBytes + 1)

        #expect(throws: ThemeStore.StoreError.imageTooLarge(bytes: oversized.count)) {
            try store.setLogo(oversized, fileExtension: "png")
        }
        #expect(store.logoData == nil)
    }

    @Test("imagem de fundo ativa o estilo image; remoção volta para gradiente")
    func backgroundImageTogglesStyle() throws {
        let store = ThemeStore(directory: makeTempDirectory(), defaultTheme: defaultTheme)

        try store.setBackgroundImage(Data([1, 2, 3]), fileExtension: "jpg")
        #expect(store.theme.backgroundStyle == .image)
        #expect(store.theme.backgroundImageFileName == "background-image.jpg")

        store.removeBackgroundImage()
        #expect(store.theme.backgroundStyle == .gradient)
        #expect(store.theme.backgroundImageFileName == nil)
    }

    @Test("referência a imagem sumida do disco é limpa na abertura")
    func missingImageReferenceIsCleared() throws {
        let directory = makeTempDirectory()
        let store = ThemeStore(directory: directory, defaultTheme: defaultTheme)
        try store.setBackgroundImage(Data([1]), fileExtension: "jpg")
        try FileManager.default.removeItem(at: directory.appendingPathComponent("background-image.jpg"))

        let reloaded = ThemeStore(directory: directory, defaultTheme: defaultTheme)
        #expect(reloaded.theme.backgroundImageFileName == nil)
        #expect(reloaded.theme.backgroundStyle == .gradient)
        #expect(reloaded.backgroundImageData == nil)
    }

    @Test("resetToDefault apaga customização e imagens")
    func resetRestoresDefault() throws {
        let directory = makeTempDirectory()
        let store = ThemeStore(directory: directory, defaultTheme: defaultTheme)
        store.apply { $0.brandName = "Custom" }
        try store.setLogo(Data([1]), fileExtension: "png")

        store.resetToDefault()

        #expect(store.theme == defaultTheme)
        #expect(!store.isCustomized)
        #expect(store.logoData == nil)
        let reloaded = ThemeStore(directory: directory, defaultTheme: defaultTheme)
        #expect(reloaded.theme == defaultTheme)
        #expect(reloaded.logoData == nil)
    }

    @Test("export/import faz round-trip do tema")
    func exportImportRoundTrip() throws {
        let directory = makeTempDirectory()
        let store = ThemeStore(directory: directory, defaultTheme: defaultTheme)
        store.apply {
            $0.brandName = "Exportada"
            $0.backgroundStyle = .solid
            $0.backgroundColor = "#ABCDEF"
        }
        let exported = try store.exportThemeJSON()

        let other = ThemeStore(directory: makeTempDirectory(), defaultTheme: defaultTheme)
        try other.importTheme(from: exported)

        #expect(other.theme.brandName == "Exportada")
        #expect(other.theme.backgroundStyle == .solid)
        #expect(other.theme.backgroundColor == "#ABCDEF")
    }

    @Test("import com cor inválida falha e não altera o tema")
    func importRejectsInvalidTheme() {
        let store = ThemeStore(directory: makeTempDirectory(), defaultTheme: defaultTheme)
        let before = store.theme
        let json = #"{ "primaryColor": "azul" }"#

        #expect(throws: WhiteLabelTheme.ValidationError.invalidColor("azul")) {
            try store.importTheme(from: Data(json.utf8))
        }
        #expect(store.theme == before)
    }

    @Test("import com imagem inexistente descarta a referência")
    func importDropsMissingImageReferences() throws {
        let store = ThemeStore(directory: makeTempDirectory(), defaultTheme: defaultTheme)
        let json = #"{ "backgroundStyle": "image", "backgroundImageFileName": "background-image.jpg" }"#

        try store.importTheme(from: Data(json.utf8))

        #expect(store.theme.backgroundImageFileName == nil)
        #expect(store.theme.backgroundStyle == .gradient)
    }
}
