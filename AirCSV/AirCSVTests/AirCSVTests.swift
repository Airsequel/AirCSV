import XCTest
@testable import AirCSV

final class AirCSVTests: XCTestCase {

    func testCSVHeaderCreation() {
        let headers = CSVHeader.createHeaders(data: ["Name", "Age", "City"])
        XCTAssertEqual(headers.count, 3)
        XCTAssertEqual(headers[0].name, "Name")
        XCTAssertEqual(headers[0].columnIndex, 0)
        XCTAssertEqual(headers[1].columnIndex, 1)
        XCTAssertEqual(headers[2].columnIndex, 2)
    }

    func testCSVCellExportContentPlain() {
        let cell = CSVCell(content: "hello")
        XCTAssertEqual(cell.exportContent, "hello")
    }

    func testCSVCellExportContentWithComma() {
        let cell = CSVCell(content: "hello, world")
        XCTAssertEqual(cell.exportContent, "\"hello, world\"")
    }

    func testCSVCellExportContentWithNewline() {
        let cell = CSVCell(content: "hello\nworld")
        XCTAssertEqual(cell.exportContent, "\"hello\nworld\"")
    }

    func testCSVCellExportContentWithQuote() {
        let cell = CSVCell(content: "say \"hi\"")
        XCTAssertEqual(cell.exportContent, "\"say \"\"hi\"\"\"")
    }

    @MainActor
    func testParseCSV() {
        let vm = CSVViewModel()
        vm.parseCSV(content: "Name,Age\nAlice,30\nBob,25")
        XCTAssertEqual(vm.headers.count, 2)
        XCTAssertEqual(vm.headers[0].name, "Name")
        XCTAssertEqual(vm.rows.count, 2)
        XCTAssertEqual(vm.rows[0].cells[0].content, "Alice")
    }

    @MainActor
    func testDeleteRowNoSelection() {
        let vm = CSVViewModel()
        vm.parseCSV(content: "A,B\n1,2\n3,4")
        let rowToDelete = vm.rows[0]
        vm.delete(row: rowToDelete, selection: [])
        XCTAssertEqual(vm.rows.count, 1)
        XCTAssertEqual(vm.rows[0].cells[0].content, "3")
    }

    @MainActor
    func testDeleteRowWithSelection() {
        let vm = CSVViewModel()
        vm.parseCSV(content: "A,B\n1,2\n3,4\n5,6")
        let ids = Set(vm.rows.prefix(2).map(\.id))
        vm.delete(row: vm.rows[0], selection: ids)
        XCTAssertEqual(vm.rows.count, 1)
        XCTAssertEqual(vm.rows[0].cells[0].content, "5")
    }
}
