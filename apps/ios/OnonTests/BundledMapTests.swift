import Foundation
import XCTest
@testable import Onon

final class BundledMapTests: XCTestCase {
    func testPackagedLightAndDarkStylesHaveLocalMapFontsAndSprites() throws {
        for dark in [false, true] {
            let styleURL = try XCTUnwrap(BundledMap.styleURL(dark: dark))
            let style = try JSONDecoder().decode(PackagedStyle.self, from: Data(contentsOf: styleURL))
            let source = try XCTUnwrap(style.sources["protomaps"])
            XCTAssertTrue(source.url.hasPrefix("pmtiles://file://"))
            let archive = try XCTUnwrap(URL(string: String(source.url.dropFirst("pmtiles://".count))))
            XCTAssertEqual(Data(try Data(contentsOf: archive).prefix(7)), Data("PMTiles".utf8))
            for font in ["Noto Sans Regular", "Noto Sans Italic", "Noto Sans Medium"] {
                let glyphs = style.glyphs
                    .replacingOccurrences(of: "{fontstack}", with: font)
                    .replacingOccurrences(of: "{range}", with: "0-255")
                try assertLocalResource(glyphs)
            }
            for suffix in [".json", ".png", "@2x.json", "@2x.png"] {
                try assertLocalResource(style.sprite + suffix)
            }
        }
    }

    private func assertLocalResource(_ value: String) throws {
        let url = try XCTUnwrap(URL(string: value))
        XCTAssertTrue(url.isFileURL)
        XCTAssertFalse(try Data(contentsOf: url).isEmpty)
    }

    func testBundledStyleUsesEscapedLocalResourcesForArchiveFontsAndSprites() {
        let template = """
        {"url":"pmtiles://__MAP_ROOT__/sydney.pmtiles","glyphs":"__MAP_ROOT__/fonts/{fontstack}/{range}.pbf","sprite":"__MAP_ROOT__/sprites/v4/dark"}
        """
        let resources = URL(fileURLWithPath: "/tmp/Onon Test.app/Protomaps", isDirectory: true)
        let style = BundledMap.resolvedStyle(template, resourceURL: resources)

        XCTAssertTrue(style.contains("pmtiles://file:///tmp/Onon%20Test.app/Protomaps/sydney.pmtiles"))
        XCTAssertTrue(style.contains("file:///tmp/Onon%20Test.app/Protomaps/fonts/{fontstack}/{range}.pbf"))
        XCTAssertTrue(style.contains("file:///tmp/Onon%20Test.app/Protomaps/sprites/v4/dark"))
        XCTAssertFalse(style.contains("__MAP_ROOT__"))
        XCTAssertFalse(style.contains("http"))
    }
}

private struct PackagedStyle: Decodable {
    struct Source: Decodable { let url: String }
    let sources: [String: Source]
    let glyphs: String
    let sprite: String
}
