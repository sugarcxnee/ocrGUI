import Testing
@testable import OCRGUICore

@Test("版本号遵循语义化版本前缀")
func coreVersionIsSemverPrefix() {
    #expect(OCRGUIInfo.version.hasPrefix("0.1."))
}
