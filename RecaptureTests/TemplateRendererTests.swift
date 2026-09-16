import XCTest
@testable import Recapture

final class TemplateRendererTests: XCTestCase {
    private let window = ActiveWindowInfo(appName: "Finder", windowTitle: "Document")

    func testPresetsAndAdjacentTokens() throws {
        let date = Date(timeIntervalSince1970: 0)
        let timestamp = try TemplateRenderer.render(
            template: "yyyyMMdd-HHmmss", date: date, sequence: 1, activeWindowInfo: window
        )
        XCTAssertEqual(
            try TemplateRenderer.render(
                template: "yyyyMMdd-HHmmss-{app}-{sequence}", date: date, sequence: 1, activeWindowInfo: window
            ),
            timestamp + "-Finder-0001"
        )
        XCTAssertEqual(
            try TemplateRenderer.render(
                template: "{app}{sequence}{title}", date: date, sequence: 1, activeWindowInfo: window
            ),
            "Finder0001Document"
        )
    }

    func testDateQuotesAndLiteralTokens() throws {
        XCTAssertEqual(
            try TemplateRenderer.render(
                template: "'Screenshot' ''{app}-'{sequence}'",
                date: Date(), sequence: 3, activeWindowInfo: window
            ),
            "Screenshot 'Finder-{sequence}"
        )
        XCTAssertThrowsError(try TemplateRenderer.validate(template: "'unterminated"))
        XCTAssertThrowsError(try TemplateRenderer.validate(template: "{unknown}"))
        XCTAssertThrowsError(try TemplateRenderer.validate(template: "{app"))
    }

    func testEmptyHiddenAndDynamicEmptyNamesAreRejected() {
        for template in ["", "   ", ".", "..", "'.hidden'"] {
            XCTAssertThrowsError(try TemplateRenderer.validate(template: template), template)
        }
        XCTAssertThrowsError(try TemplateRenderer.render(
            template: "{title}", date: Date(), sequence: 1,
            activeWindowInfo: ActiveWindowInfo(appName: "Finder", windowTitle: "")
        ))
    }

    func testSanitizingAndByteLimit() throws {
        let unsafe = ActiveWindowInfo(appName: "A/B:C\nD", windowTitle: "")
        XCTAssertEqual(
            try TemplateRenderer.render(template: "{app}", date: Date(), sequence: 1, activeWindowInfo: unsafe),
            "A-B-C-D"
        )
        XCTAssertNoThrow(try TemplateRenderer.validate(template: "'" + String(repeating: "a", count: 250) + "'"))
        XCTAssertThrowsError(try TemplateRenderer.validate(template: "'" + String(repeating: "a", count: 251) + "'"))
        let longTitle = ActiveWindowInfo(appName: "App", windowTitle: String(repeating: "\u{65e5}", count: 84))
        XCTAssertThrowsError(try TemplateRenderer.render(
            template: "{title}", date: Date(), sequence: 1, activeWindowInfo: longTitle
        ))
    }
}
