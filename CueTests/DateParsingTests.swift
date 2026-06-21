import XCTest
@testable import Cue

/// Verifies ISO 8601 parsing, the 9:00 AM default for date-only input, and the
/// ISO round-trip used in the task snapshot.
final class DateParsingTests: XCTestCase {

    func testParsesFullDatetime() throws {
        let result = try XCTUnwrap(DateParsing.parse("2026-06-23T15:00:00"))
        XCTAssertFalse(result.timeWasDefaulted)
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: result.date)
        XCTAssertEqual(comps.year, 2026)
        XCTAssertEqual(comps.month, 6)
        XCTAssertEqual(comps.day, 23)
        XCTAssertEqual(comps.hour, 15)
        XCTAssertEqual(comps.minute, 0)
    }

    func testDateOnlyDefaultsToNineAM() throws {
        let result = try XCTUnwrap(DateParsing.parse("2026-06-23"))
        XCTAssertTrue(result.timeWasDefaulted)
        let comps = Calendar.current.dateComponents([.hour, .minute], from: result.date)
        XCTAssertEqual(comps.hour, 9)
        XCTAssertEqual(comps.minute, 0)
    }

    func testParsesZonedDatetime() throws {
        let result = try XCTUnwrap(DateParsing.parse("2026-06-23T15:00:00Z"))
        XCTAssertFalse(result.timeWasDefaulted)
    }

    func testISORoundTrip() throws {
        let original = try XCTUnwrap(DateParsing.parse("2026-12-01T08:30:00")).date
        let iso = DateParsing.iso(from: original)
        let reparsed = try XCTUnwrap(DateParsing.parse(iso)).date
        XCTAssertEqual(original.timeIntervalSince1970, reparsed.timeIntervalSince1970, accuracy: 1.0)
    }

    func testBlankReturnsNil() {
        XCTAssertNil(DateParsing.parse(""))
        XCTAssertNil(DateParsing.parse("   "))
        XCTAssertNil(DateParsing.parse("not a date"))
    }
}
