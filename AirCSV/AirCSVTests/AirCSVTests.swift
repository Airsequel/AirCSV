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
        let vm = CSVDocument()
        vm.parseCSV(content: "Name,Age\nAlice,30\nBob,25")
        XCTAssertEqual(vm.headers.count, 2)
        XCTAssertEqual(vm.headers[0].name, "Name")
        XCTAssertEqual(vm.rows.count, 2)
        XCTAssertEqual(vm.rows[0].cells[0].content, "Alice")
    }

    @MainActor
    func testDeleteRowNoSelection() {
        let vm = CSVDocument()
        vm.parseCSV(content: "A,B\n1,2\n3,4")
        let rowToDelete = vm.rows[0]
        vm.delete(row: rowToDelete, selection: [])
        XCTAssertEqual(vm.rows.count, 1)
        XCTAssertEqual(vm.rows[0].cells[0].content, "3")
    }

    @MainActor
    func testAddRow() {
        let vm = CSVDocument()
        vm.parseCSV(content: "A,B\n1,2")
        vm.addRow()
        XCTAssertEqual(vm.rows.count, 2)
        XCTAssertEqual(vm.rows[1].cells.count, 2)
        XCTAssertEqual(vm.rows[1].cells.map(\.content), ["", ""])
    }

    @MainActor
    func testAddColumn() {
        let vm = CSVDocument()
        vm.parseCSV(content: "A,B\n1,2\n3,4")
        vm.addColumn()
        XCTAssertEqual(vm.headers.count, 3)
        XCTAssertEqual(vm.headers[2].name, "Column 3")
        XCTAssertEqual(vm.headers[2].columnIndex, 2)
        XCTAssertTrue(vm.rows.allSatisfy { $0.cells.count == 3 })
        XCTAssertEqual(vm.rows[0].cells[2].content, "")
    }

    @MainActor
    func testExportContentEndsWithNewline() {
        let vm = CSVDocument()
        vm.parseCSV(content: "A,B\n1,2")
        XCTAssertEqual(vm.exportContent(), "A,B\n1,2\n")
    }

    @MainActor
    func testExportContentForRow() {
        let vm = CSVDocument()
        vm.parseCSV(content: "A,B\nhello,\"with, comma\"")
        XCTAssertEqual(vm.exportContent(for: vm.rows[0]), "hello,\"with, comma\"")
    }

    @MainActor
    func testClearRowNoSelection() {
        let vm = CSVDocument()
        vm.parseCSV(content: "A,B\n1,2\n3,4")
        vm.clear(row: vm.rows[0], selection: [])
        XCTAssertEqual(vm.rows.count, 2)
        XCTAssertEqual(vm.rows[0].cells.map(\.content), ["", ""])
        XCTAssertEqual(vm.rows[1].cells.map(\.content), ["3", "4"])
    }

    @MainActor
    func testClearRowWithSelection() {
        let vm = CSVDocument()
        vm.parseCSV(content: "A,B\n1,2\n3,4\n5,6")
        let ids = Set(vm.rows.prefix(2).map(\.id))
        vm.clear(row: vm.rows[0], selection: ids)
        XCTAssertEqual(vm.rows[0].cells.map(\.content), ["", ""])
        XCTAssertEqual(vm.rows[1].cells.map(\.content), ["", ""])
        XCTAssertEqual(vm.rows[2].cells.map(\.content), ["5", "6"])
    }

    @MainActor
    func testClearColumn() {
        let vm = CSVDocument()
        vm.parseCSV(content: "A,B\n1,2\n3,4")
        vm.clear(column: vm.headers[0])
        XCTAssertEqual(vm.rows[0].cells.map(\.content), ["", "2"])
        XCTAssertEqual(vm.rows[1].cells.map(\.content), ["", "4"])
    }

    @MainActor
    func testDeleteColumn() {
        let vm = CSVDocument()
        vm.parseCSV(content: "A,B,C\n1,2,3\n4,5,6")
        vm.delete(column: vm.headers[1])
        XCTAssertEqual(vm.headers.map(\.name), ["A", "C"])
        XCTAssertEqual(vm.headers.map(\.columnIndex), [0, 1])
        XCTAssertEqual(vm.rows[0].cells.map(\.content), ["1", "3"])
        XCTAssertEqual(vm.rows[1].cells.map(\.content), ["4", "6"])
    }

    @MainActor
    func testExportContentForColumn() {
        let vm = CSVDocument()
        vm.parseCSV(content: "A,B\nhello,2\n\"with, comma\",4")
        XCTAssertEqual(vm.exportContent(for: vm.headers[0]), "hello\n\"with, comma\"")
    }

    @MainActor
    func testCopyContentForRows() {
        let vm = CSVDocument()
        vm.parseCSV(content: "A,B\n1,2\n3,4\n5,6")
        let ids = Set([vm.rows[0].id, vm.rows[2].id])
        XCTAssertEqual(vm.copyContent(rows: ids), "1,2\n5,6")
    }

    @MainActor
    func testCopyContentForColumns() {
        let vm = CSVDocument()
        vm.parseCSV(content: "A,B,C\n1,2,3\n4,5,6")
        let ids = Set([vm.headers[0].id, vm.headers[2].id])
        XCTAssertEqual(vm.copyContent(columns: ids), "1,3\n4,6")
    }

    @MainActor
    func testClearColumns() {
        let vm = CSVDocument()
        vm.parseCSV(content: "A,B,C\n1,2,3\n4,5,6")
        vm.clear(columns: Set([vm.headers[0].id, vm.headers[2].id]))
        XCTAssertEqual(vm.rows[0].cells.map(\.content), ["", "2", ""])
        XCTAssertEqual(vm.rows[1].cells.map(\.content), ["", "5", ""])
    }

    @MainActor
    func testCopyContentForCellRange() {
        let vm = CSVDocument()
        vm.parseCSV(content: "A,B,C\n1,2,3\n4,\"with, comma\",6\n7,8,9")
        XCTAssertEqual(
            vm.copyContent(rowRange: 0...1, columnRange: 1...2),
            "2,3\n\"with, comma\",6")
    }

    @MainActor
    func testClearCellRange() {
        let vm = CSVDocument()
        vm.parseCSV(content: "A,B,C\n1,2,3\n4,5,6\n7,8,9")
        vm.clear(rowRange: 1...2, columnRange: 0...1)
        XCTAssertEqual(vm.rows[0].cells.map(\.content), ["1", "2", "3"])
        XCTAssertEqual(vm.rows[1].cells.map(\.content), ["", "", "6"])
        XCTAssertEqual(vm.rows[2].cells.map(\.content), ["", "", "9"])
    }

    @MainActor
    func testPasteSingleField() {
        let vm = CSVDocument()
        vm.parseCSV(content: "A,B\n1,2\n3,4")
        vm.paste("hello", atRow: 1, column: 1)
        XCTAssertEqual(vm.rows[1].cells.map(\.content), ["3", "hello"])
    }

    @MainActor
    func testPasteCSVBlock() {
        let vm = CSVDocument()
        vm.parseCSV(content: "A,B\n1,2\n3,4")
        vm.paste("x,y\nz,\"with, comma\"\n", atRow: 0, column: 0)
        XCTAssertEqual(vm.rows[0].cells.map(\.content), ["x", "y"])
        XCTAssertEqual(vm.rows[1].cells.map(\.content), ["z", "with, comma"])
    }

    @MainActor
    func testPasteTabSeparated() {
        let vm = CSVDocument()
        vm.parseCSV(content: "A,B\n1,2")
        vm.paste("x\ty", atRow: 0, column: 0)
        XCTAssertEqual(vm.rows[0].cells.map(\.content), ["x", "y"])
    }

    @MainActor
    func testPasteExpandsTable() {
        let vm = CSVDocument()
        vm.parseCSV(content: "A,B\n1,2")
        vm.paste("x,y\nz,w", atRow: 1, column: 1)
        XCTAssertEqual(vm.headers.count, 3)
        XCTAssertEqual(vm.rows.count, 3)
        XCTAssertEqual(vm.rows[1].cells.map(\.content), ["", "x", "y"])
        XCTAssertEqual(vm.rows[2].cells.map(\.content), ["", "z", "w"])
    }

    @MainActor
    func testPasteIntoColumn() {
        let vm = CSVDocument()
        vm.parseCSV(content: "A,B\n1,2\n3,4")
        vm.paste("x\ny", atRow: 0, column: 1)
        XCTAssertEqual(vm.rows[0].cells.map(\.content), ["1", "x"])
        XCTAssertEqual(vm.rows[1].cells.map(\.content), ["3", "y"])
    }

    @MainActor
    func testDeleteRowWithSelection() {
        let vm = CSVDocument()
        vm.parseCSV(content: "A,B\n1,2\n3,4\n5,6")
        let ids = Set(vm.rows.prefix(2).map(\.id))
        vm.delete(row: vm.rows[0], selection: ids)
        XCTAssertEqual(vm.rows.count, 1)
        XCTAssertEqual(vm.rows[0].cells[0].content, "5")
    }

    @MainActor
    func testMoveRow() {
        let vm = CSVDocument()
        vm.parseCSV(content: "A,B\n1,2\n3,4\n5,6")
        vm.move(rowAt: 0, to: 2)
        XCTAssertEqual(vm.rows.map { $0.cells[0].content }, ["3", "5", "1"])
    }

    @MainActor
    func testMoveRowOutOfBoundsIsIgnored() {
        let vm = CSVDocument()
        vm.parseCSV(content: "A,B\n1,2\n3,4")
        vm.move(rowAt: 0, to: 5)
        XCTAssertEqual(vm.rows.map { $0.cells[0].content }, ["1", "3"])
    }

    @MainActor
    func testMoveColumn() {
        let vm = CSVDocument()
        vm.parseCSV(content: "A,B,C\n1,2,3\n4,5,6")
        vm.move(columnAt: 2, to: 0)
        XCTAssertEqual(vm.headers.map(\.name), ["C", "A", "B"])
        XCTAssertEqual(vm.headers.map(\.columnIndex), [0, 1, 2])
        XCTAssertEqual(vm.rows[0].cells.map(\.content), ["3", "1", "2"])
        XCTAssertEqual(vm.rows[1].cells.map(\.content), ["6", "4", "5"])
    }

    @MainActor
    func testUndoRedoDeleteRow() {
        let vm = CSVDocument()
        let undoManager = UndoManager()
        vm.undoManager = undoManager
        vm.parseCSV(content: "A,B\n1,2\n3,4")
        vm.delete(row: vm.rows[0], selection: [])
        XCTAssertEqual(vm.rows.count, 1)
        undoManager.undo()
        XCTAssertEqual(vm.rows.map { $0.cells[0].content }, ["1", "3"])
        undoManager.redo()
        XCTAssertEqual(vm.rows.map { $0.cells[0].content }, ["3"])
    }

    @MainActor
    func testUndoAddColumn() {
        let vm = CSVDocument()
        let undoManager = UndoManager()
        vm.undoManager = undoManager
        vm.parseCSV(content: "A,B\n1,2")
        vm.addColumn()
        XCTAssertEqual(vm.headers.count, 3)
        undoManager.undo()
        XCTAssertEqual(vm.headers.map(\.name), ["A", "B"])
        XCTAssertEqual(vm.rows[0].cells.map(\.content), ["1", "2"])
    }

    @MainActor
    func testUndoMoveColumn() {
        let vm = CSVDocument()
        let undoManager = UndoManager()
        vm.undoManager = undoManager
        vm.parseCSV(content: "A,B,C\n1,2,3")
        vm.move(columnAt: 0, to: 2)
        XCTAssertEqual(vm.headers.map(\.name), ["B", "C", "A"])
        undoManager.undo()
        XCTAssertEqual(vm.headers.map(\.name), ["A", "B", "C"])
        XCTAssertEqual(vm.headers.map(\.columnIndex), [0, 1, 2])
        XCTAssertEqual(vm.rows[0].cells.map(\.content), ["1", "2", "3"])
    }

    @MainActor
    func testUndoCellEditCoalescesKeystrokes() {
        let vm = CSVDocument()
        let undoManager = UndoManager()
        vm.undoManager = undoManager
        vm.parseCSV(content: "A,B\n1,2")
        let binding = vm.cellBinding(for: vm.rows[0], header: vm.headers[0])
        binding.wrappedValue = "x"
        binding.wrappedValue = "xy"
        undoManager.undo()
        XCTAssertEqual(vm.rows[0].cells[0].content, "1")
    }

    @MainActor
    func testBreakUndoCoalescingSeparatesEditSessions() {
        let vm = CSVDocument()
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        vm.undoManager = undoManager
        vm.parseCSV(content: "A,B\n1,2")
        let binding = vm.cellBinding(for: vm.rows[0], header: vm.headers[0])
        undoManager.beginUndoGrouping()
        binding.wrappedValue = "x"
        undoManager.endUndoGrouping()
        vm.breakUndoCoalescing()
        undoManager.beginUndoGrouping()
        binding.wrappedValue = "xy"
        undoManager.endUndoGrouping()
        undoManager.undo()
        XCTAssertEqual(vm.rows[0].cells[0].content, "x")
        undoManager.undo()
        XCTAssertEqual(vm.rows[0].cells[0].content, "1")
    }

    @MainActor
    func testUndoHeaderRename() {
        let vm = CSVDocument()
        let undoManager = UndoManager()
        vm.undoManager = undoManager
        vm.parseCSV(content: "A,B\n1,2")
        vm.headerBinding(for: vm.headers[0]).wrappedValue = "Z"
        XCTAssertEqual(vm.headers[0].name, "Z")
        undoManager.undo()
        XCTAssertEqual(vm.headers[0].name, "A")
    }

    @MainActor
    func testUndoPasteRestoresTableSize() {
        let vm = CSVDocument()
        let undoManager = UndoManager()
        vm.undoManager = undoManager
        vm.parseCSV(content: "A,B\n1,2")
        vm.paste("x,y\nz,w", atRow: 1, column: 1)
        XCTAssertEqual(vm.headers.count, 3)
        XCTAssertEqual(vm.rows.count, 3)
        undoManager.undo()
        XCTAssertEqual(vm.headers.count, 2)
        XCTAssertEqual(vm.rows.count, 1)
        XCTAssertEqual(vm.rows[0].cells.map(\.content), ["1", "2"])
    }

    @MainActor
    func testParseCSVClearsUndoHistory() {
        let vm = CSVDocument()
        let undoManager = UndoManager()
        vm.undoManager = undoManager
        vm.parseCSV(content: "A,B\n1,2")
        vm.addRow()
        vm.parseCSV(content: "C,D\n3,4")
        undoManager.undo()
        XCTAssertEqual(vm.headers.map(\.name), ["C", "D"])
        XCTAssertEqual(vm.rows[0].cells.map(\.content), ["3", "4"])
    }
}
