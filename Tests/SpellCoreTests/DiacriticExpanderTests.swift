import Testing
@testable import SpellCore

@Suite struct DiacriticExpanderTests {
    @Test func enumeratesCzechDiacriticVariants() {
        let variants = DiacriticExpander.variants(of: "praci")
        #expect(variants.contains("práci"))
        #expect(variants.contains("prací"))
        #expect(variants.contains("přáčí"))
        #expect(!variants.contains("praci"))
    }

    @Test func keepsUppercase() {
        #expect(DiacriticExpander.variants(of: "Zitra").contains("Zítra"))
        #expect(DiacriticExpander.variants(of: "Cesko").contains("Česko"))
    }

    @Test func givesUpOnCombinatorialExplosion() {
        #expect(DiacriticExpander.variants(of: "nejneobhospodarovavatelnejsimi").isEmpty)
    }
}
