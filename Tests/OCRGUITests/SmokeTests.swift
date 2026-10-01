import Testing
@testable import OCRGUICore

@Test("版本号遵循语义化版本（major.minor.patch）")
func coreVersionIsSemverPrefix() {
    #expect(OCRGUIInfo.version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil)
}
