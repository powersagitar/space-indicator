import Testing

@Suite struct TitleImageTests {
    @Test func digitsHaveEqualWidth() {
        let one = TitleImage.make("1").size
        let eight = TitleImage.make("8").size
        #expect(one.width == eight.width)
        #expect(one.width > 0 && one.height > 0)
    }

    @Test func placeholderYieldsTemplateImage() {
        let image = TitleImage.make("?")
        #expect(image.size.width > 0)
        #expect(image.isTemplate)
    }

    @Test func accessibilityDescriptionIsTitle() {
        #expect(TitleImage.make("2 \u{B7} 1").accessibilityDescription == "2 \u{B7} 1")
    }
}
