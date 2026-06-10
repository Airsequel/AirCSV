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
    func testAddRow() {
        let vm = CSVViewModel()
        vm.parseCSV(content: "A,B\n1,2")
        vm.addRow()
        XCTAssertEqual(vm.rows.count, 2)
        XCTAssertEqual(vm.rows[1].cells.count, 2)
        XCTAssertEqual(vm.rows[1].cells.map(\.content), ["", ""])
    }

    @MainActor
    func testAddColumn() {
        let vm = CSVViewModel()
        vm.parseCSV(content: "A,B\n1,2\n3,4")
        vm.addColumn()
        XCTAssertEqual(vm.headers.count, 3)
        XCTAssertEqual(vm.headers[2].name, "Column 3")
        XCTAssertEqual(vm.headers[2].columnIndex, 2)
        XCTAssertTrue(vm.rows.allSatisfy { $0.cells.count == 3 })
        XCTAssertEqual(vm.rows[0].cells[2].content, "")
    }

    @MainActor
    func testExportContentForRow() {
        let vm = CSVViewModel()
        vm.parseCSV(content: "A,B\nhello,\"with, comma\"")
        XCTAssertEqual(vm.exportContent(for: vm.rows[0]), "hello,\"with, comma\"")
    }

    @MainActor
    func testClearRowNoSelection() {
        let vm = CSVViewModel()
        vm.parseCSV(content: "A,B\n1,2\n3,4")
        vm.clear(row: vm.rows[0], selection: [])
        XCTAssertEqual(vm.rows.count, 2)
        XCTAssertEqual(vm.rows[0].cells.map(\.content), ["", ""])
        XCTAssertEqual(vm.rows[1].cells.map(\.content), ["3", "4"])
    }

    @MainActor
    func testClearRowWithSelection() {
        let vm = CSVViewModel()
        vm.parseCSV(content: "A,B\n1,2\n3,4\n5,6")
        let ids = Set(vm.rows.prefix(2).map(\.id))
        vm.clear(row: vm.rows[0], selection: ids)
        XCTAssertEqual(vm.rows[0].cells.map(\.content), ["", ""])
        XCTAssertEqual(vm.rows[1].cells.map(\.content), ["", ""])
        XCTAssertEqual(vm.rows[2].cells.map(\.content), ["5", "6"])
    }

    @MainActor
    func testClearColumn() {
        let vm = CSVViewModel()
        vm.parseCSV(content: "A,B\n1,2\n3,4")
        vm.clear(column: vm.headers[0])
        XCTAssertEqual(vm.rows[0].cells.map(\.content), ["", "2"])
        XCTAssertEqual(vm.rows[1].cells.map(\.content), ["", "4"])
    }

    @MainActor
    func testDeleteColumn() {
        let vm = CSVViewModel()
        vm.parseCSV(content: "A,B,C\n1,2,3\n4,5,6")
        vm.delete(column: vm.headers[1])
        XCTAssertEqual(vm.headers.map(\.name), ["A", "C"])
        XCTAssertEqual(vm.headers.map(\.columnIndex), [0, 1])
        XCTAssertEqual(vm.rows[0].cells.map(\.content), ["1", "3"])
        XCTAssertEqual(vm.rows[1].cells.map(\.content), ["4", "6"])
    }

    @MainActor
    func testExportContentForColumn() {
        let vm = CSVViewModel()
        vm.parseCSV(content: "A,B\nhello,2\n\"with, comma\",4")
        XCTAssertEqual(vm.exportContent(for: vm.headers[0]), "hello\n\"with, comma\"")
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
