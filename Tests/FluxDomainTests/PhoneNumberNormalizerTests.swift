import Testing
@testable import FluxDomain

@Suite("PhoneNumberNormalizer")
struct PhoneNumberNormalizerTests {
    @Test("separadores visuais são removidos")
    func stripsSeparators() {
        #expect(PhoneNumberNormalizer.normalize("(51) 99999-8888") == "51999998888")
        #expect(PhoneNumberNormalizer.normalize("51 3333.4444") == "5133334444")
        #expect(PhoneNumberNormalizer.normalize("  1001  ") == "1001")
    }

    @Test("prefixo internacional + é preservado apenas no início")
    func preservesLeadingPlus() {
        #expect(PhoneNumberNormalizer.normalize("+55 (51) 99999-8888") == "+5551999998888")
        #expect(PhoneNumberNormalizer.normalize("12+34") == "1234")
    }

    @Test("códigos de serviço com * e # não são destruídos")
    func preservesServiceCodes() {
        #expect(PhoneNumberNormalizer.normalize("*142#") == "*142#")
        #expect(PhoneNumberNormalizer.normalize("#31# 5133334444") == "#31#5133334444")
    }

    @Test("ramal curto é discável")
    func shortExtensionIsDiallable() {
        #expect(PhoneNumberNormalizer.isDiallable("1001"))
        #expect(PhoneNumberNormalizer.isDiallable("9"))
    }

    @Test("número internacional é discável; + sozinho ou + com código de serviço não")
    func internationalRules() {
        #expect(PhoneNumberNormalizer.isDiallable("+5551999998888"))
        #expect(!PhoneNumberNormalizer.isDiallable("+"))
        #expect(!PhoneNumberNormalizer.isDiallable("+51*99#"))
    }

    @Test("entradas com letras ou vazias não são discáveis")
    func rejectsInvalid() {
        #expect(!PhoneNumberNormalizer.isDiallable(""))
        #expect(!PhoneNumberNormalizer.isDiallable(PhoneNumberNormalizer.normalize("ligar para o João")))
        #expect(!PhoneNumberNormalizer.isDiallable(PhoneNumberNormalizer.normalize("   ")))
    }

    @Test("colar número formatado do CRM funciona de ponta a ponta")
    func pasteRoundtrip() {
        let pasted = "+55 (51) 3333-4444"
        let normalized = PhoneNumberNormalizer.normalize(pasted)
        #expect(normalized == "+555133334444")
        #expect(PhoneNumberNormalizer.isDiallable(normalized))
    }
}
