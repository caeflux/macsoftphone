import Testing
@testable import FluxWhiteLabel

@Suite("HexColorParser")
struct HexColorParserTests {
    @Test("RRGGBB com e sem # é aceito")
    func sixDigitHex() {
        let white = HexColorParser.parse("#FFFFFF")
        #expect(white == HexColorParser.RGBA(red: 1, green: 1, blue: 1, alpha: 1))

        let black = HexColorParser.parse("000000")
        #expect(black == HexColorParser.RGBA(red: 0, green: 0, blue: 0, alpha: 1))
    }

    @Test("RRGGBBAA aplica alpha")
    func eightDigitHex() {
        let semi = HexColorParser.parse("#FF000080")
        #expect(semi != nil)
        #expect(semi?.red == 1)
        #expect(semi?.green == 0)
        if let alpha = semi?.alpha {
            #expect(abs(alpha - 128.0 / 255.0) < 0.001)
        }
    }

    @Test("entradas inválidas retornam nil")
    func invalidInputs() {
        #expect(HexColorParser.parse("azul") == nil)
        #expect(HexColorParser.parse("#FFF") == nil)
        #expect(HexColorParser.parse("#GGGGGG") == nil)
        #expect(HexColorParser.parse("") == nil)
    }
}
