import Testing

@Test
func wordErrorRateNormalizesTimesPercentsAndCase() {
    #expect(WordErrorRate.errors(reference: "Moved to three thirty, in room B.", hypothesis: "moved to 3:30 in room b").errors == 0)
    #expect(WordErrorRate.errors(reference: "Grew by twelve percent.", hypothesis: "grew by 12%").errors == 0)
    #expect(WordErrorRate.errors(reference: "Swift six point two", hypothesis: "Swift 6.2").errors == 0)
    #expect(WordErrorRate.errors(reference: "Mañana tenemos", hypothesis: "manana tenemos").errors == 0)
    #expect(WordErrorRate.errors(reference: "three thirty", hypothesis: "3.30").errors == 0)
    #expect(WordErrorRate.errors(reference: "a b c d", hypothesis: "a x c").errors == 2)
}
