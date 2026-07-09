// XCTest for the VesnAI WidgetKit extension. Runs on iOS CI (Xcode), not in
// `flutter test`. Validates snapshot decoding + timeline construction.

import XCTest
@testable import VesnaiWidgetExtension

final class VesnaiWidgetTests: XCTestCase {
    func testSnapshotDecoding() throws {
        let json = """
        {"version":1,"recents":[
          {"title":"Idea","type":"Idea","generated":false},
          {"title":"AI image","type":"GeneratedImage","generated":true}
        ]}
        """.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(VesnaiSnapshot.self, from: json)
        XCTAssertEqual(snapshot.recents.count, 2)
        XCTAssertTrue(snapshot.recents[1].generated)
    }

    func testTimelineHasEntry() {
        let exp = expectation(description: "timeline")
        Provider().getTimeline(in: makeContext()) { timeline in
            XCTAssertFalse(timeline.entries.isEmpty)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
    }
}
