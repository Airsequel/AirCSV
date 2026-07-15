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
        XCTAssertEqual(cell.exportContent(), "hello")
    }

    func testCSVCellExportContentWithComma() {
        let cell = CSVCell(content: "hello, world")
        XCTAssertEqual(cell.exportContent(), "\"hello, world\"")
    }

    func testCSVCellExportContentWithNewline() {
        let cell = CSVCell(content: "hello\nworld")
        XCTAssertEqual(cell.exportContent(), "\"hello\nworld\"")
    }

    func testCSVCellExportContentWithQuote() {
        let cell = CSVCell(content: "say \"hi\"")
        XCTAssertEqual(cell.exportContent(), "\"say \"\"hi\"\"\"")
    }

    func testCSVCellExportContentTabDelimiterQuotesTab() {
        let cell = CSVCell(content: "hello\tworld")
        XCTAssertEqual(cell.exportContent(delimiter: "\t"), "\"hello\tworld\"")
    }

    func testCSVCellExportContentTabDelimiterLeavesCommaUnquoted() {
        let cell = CSVCell(content: "hello, world")
        XCTAssertEqual(cell.exportContent(delimiter: "\t"), "hello, world")
    }

    @MainActor
    func testParseCSV() {
        let doc = CSVDocument()
        doc.parseCSV(content: "Name,Age\nAlice,30\nBob,25")
        XCTAssertEqual(doc.headers.count, 2)
        XCTAssertEqual(doc.headers[0].name, "Name")
        XCTAssertEqual(doc.rows.count, 2)
        XCTAssertEqual(doc.rows[0].cells[0].content, "Alice")
    }

    @MainActor
    func testParseTSVDetectsTabDelimiter() {
        let doc = CSVDocument()
        doc.parseCSV(content: "Name\tAge\nAlice\t30\nBob\t25")
        XCTAssertEqual(doc.delimiter, .tab)
        XCTAssertEqual(doc.headers.map(\.name), ["Name", "Age"])
        XCTAssertEqual(doc.rows.count, 2)
        XCTAssertEqual(doc.rows[0].cells.map(\.content), ["Alice", "30"])
    }

    @MainActor
    func testExportTSVUsesTabDelimiter() {
        let doc = CSVDocument()
        doc.parseCSV(content: "Name\tAge\nAlice\t30")
        XCTAssertEqual(doc.exportContent(), "Name\tAge\nAlice\t30\n")
    }

    @MainActor
    func testParseTSVWithUnescapedQuotesFallsBack() {
        // Real-world messy data: an unescaped quote inside an unquoted
        // field. Strict CSV parsing throws; the lenient fallback must
        // still populate the table instead of leaving it empty.
        let doc = CSVDocument()
        doc.parseCSV(content: "kind\tartist\tpath\nampersand\tEddie \"Lockjaw\" Davis & His Beboppers\t/music/a.mp3")
        XCTAssertEqual(doc.delimiter, .tab)
        XCTAssertEqual(doc.headers.map(\.name), ["kind", "artist", "path"])
        XCTAssertEqual(doc.rows.count, 1)
        XCTAssertEqual(
            doc.rows[0].cells.map(\.content),
            ["ampersand", "Eddie \"Lockjaw\" Davis & His Beboppers", "/music/a.mp3"])
    }

    @MainActor
    func testParseCSVWithUnescapedQuotesFallsBack() {
        let doc = CSVDocument()
        doc.parseCSV(content: "a,b\nEddie \"Lockjaw\" Davis,2")
        XCTAssertEqual(doc.rows.count, 1)
        XCTAssertEqual(doc.rows[0].cells.map(\.content), ["Eddie \"Lockjaw\" Davis", "2"])
    }

    @MainActor
    func testDeleteRowNoSelection() {
        let doc = CSVDocument()
        doc.parseCSV(content: "A,B\n1,2\n3,4")
        let rowToDelete = doc.rows[0]
        doc.delete(row: rowToDelete, selection: [])
        XCTAssertEqual(doc.rows.count, 1)
        XCTAssertEqual(doc.rows[0].cells[0].content, "3")
    }

    @MainActor
    func testAddRow() {
        let doc = CSVDocument()
        doc.parseCSV(content: "A,B\n1,2")
        doc.addRow()
        XCTAssertEqual(doc.rows.count, 2)
        XCTAssertEqual(doc.rows[1].cells.count, 2)
        XCTAssertEqual(doc.rows[1].cells.map(\.content), ["", ""])
    }

    @MainActor
    func testAddColumn() {
        let doc = CSVDocument()
        doc.parseCSV(content: "A,B\n1,2\n3,4")
        doc.addColumn()
        XCTAssertEqual(doc.headers.count, 3)
        XCTAssertEqual(doc.headers[2].name, "Column 3")
        XCTAssertEqual(doc.headers[2].columnIndex, 2)
        XCTAssertTrue(doc.rows.allSatisfy { $0.cells.count == 3 })
        XCTAssertEqual(doc.rows[0].cells[2].content, "")
    }

    @MainActor
    func testExportContentEndsWithNewline() {
        let doc = CSVDocument()
        doc.parseCSV(content: "A,B\n1,2")
        XCTAssertEqual(doc.exportContent(), "A,B\n1,2\n")
    }

    @MainActor
    func testExportContentForRow() {
        let doc = CSVDocument()
        doc.parseCSV(content: "A,B\nhello,\"with, comma\"")
        XCTAssertEqual(doc.exportContent(for: doc.rows[0]), "hello,\"with, comma\"")
    }

    @MainActor
    func testClearRowNoSelection() {
        let doc = CSVDocument()
        doc.parseCSV(content: "A,B\n1,2\n3,4")
        doc.clear(row: doc.rows[0], selection: [])
        XCTAssertEqual(doc.rows.count, 2)
        XCTAssertEqual(doc.rows[0].cells.map(\.content), ["", ""])
        XCTAssertEqual(doc.rows[1].cells.map(\.content), ["3", "4"])
    }

    @MainActor
    func testClearRowWithSelection() {
        let doc = CSVDocument()
        doc.parseCSV(content: "A,B\n1,2\n3,4\n5,6")
        let ids = Set(doc.rows.prefix(2).map(\.id))
        doc.clear(row: doc.rows[0], selection: ids)
        XCTAssertEqual(doc.rows[0].cells.map(\.content), ["", ""])
        XCTAssertEqual(doc.rows[1].cells.map(\.content), ["", ""])
        XCTAssertEqual(doc.rows[2].cells.map(\.content), ["5", "6"])
    }

    @MainActor
    func testClearColumn() {
        let doc = CSVDocument()
        doc.parseCSV(content: "A,B\n1,2\n3,4")
        doc.clear(column: doc.headers[0])
        XCTAssertEqual(doc.rows[0].cells.map(\.content), ["", "2"])
        XCTAssertEqual(doc.rows[1].cells.map(\.content), ["", "4"])
    }

    @MainActor
    func testDeleteColumn() {
        let doc = CSVDocument()
        doc.parseCSV(content: "A,B,C\n1,2,3\n4,5,6")
        doc.delete(column: doc.headers[1])
        XCTAssertEqual(doc.headers.map(\.name), ["A", "C"])
        XCTAssertEqual(doc.headers.map(\.columnIndex), [0, 1])
        XCTAssertEqual(doc.rows[0].cells.map(\.content), ["1", "3"])
        XCTAssertEqual(doc.rows[1].cells.map(\.content), ["4", "6"])
    }

    @MainActor
    func testExportContentForColumn() {
        let doc = CSVDocument()
        doc.parseCSV(content: "A,B\nhello,2\n\"with, comma\",4")
        XCTAssertEqual(doc.exportContent(for: doc.headers[0]), "hello\n\"with, comma\"")
    }

    @MainActor
    func testCopyContentForRows() {
        let doc = CSVDocument()
        doc.parseCSV(content: "A,B\n1,2\n3,4\n5,6")
        let ids = Set([doc.rows[0].id, doc.rows[2].id])
        XCTAssertEqual(doc.copyContent(rows: ids), "1,2\n5,6")
    }

    @MainActor
    func testCopyContentForColumns() {
        let doc = CSVDocument()
        doc.parseCSV(content: "A,B,C\n1,2,3\n4,5,6")
        let ids = Set([doc.headers[0].id, doc.headers[2].id])
        XCTAssertEqual(doc.copyContent(columns: ids), "1,3\n4,6")
    }

    @MainActor
    func testClearColumns() {
        let doc = CSVDocument()
        doc.parseCSV(content: "A,B,C\n1,2,3\n4,5,6")
        doc.clear(columns: Set([doc.headers[0].id, doc.headers[2].id]))
        XCTAssertEqual(doc.rows[0].cells.map(\.content), ["", "2", ""])
        XCTAssertEqual(doc.rows[1].cells.map(\.content), ["", "5", ""])
    }

    @MainActor
    func testCopyContentForCellRange() {
        let doc = CSVDocument()
        doc.parseCSV(content: "A,B,C\n1,2,3\n4,\"with, comma\",6\n7,8,9")
        XCTAssertEqual(
            doc.copyContent(rowRange: 0...1, columnRange: 1...2),
            "2,3\n\"with, comma\",6")
    }

    @MainActor
    func testClearCellRange() {
        let doc = CSVDocument()
        doc.parseCSV(content: "A,B,C\n1,2,3\n4,5,6\n7,8,9")
        doc.clear(rowRange: 1...2, columnRange: 0...1)
        XCTAssertEqual(doc.rows[0].cells.map(\.content), ["1", "2", "3"])
        XCTAssertEqual(doc.rows[1].cells.map(\.content), ["", "", "6"])
        XCTAssertEqual(doc.rows[2].cells.map(\.content), ["", "", "9"])
    }

    @MainActor
    func testPasteSingleField() {
        let doc = CSVDocument()
        doc.parseCSV(content: "A,B\n1,2\n3,4")
        doc.paste("hello", atRow: 1, column: 1)
        XCTAssertEqual(doc.rows[1].cells.map(\.content), ["3", "hello"])
    }

    @MainActor
    func testPasteCSVBlock() {
        let doc = CSVDocument()
        doc.parseCSV(content: "A,B\n1,2\n3,4")
        doc.paste("x,y\nz,\"with, comma\"\n", atRow: 0, column: 0)
        XCTAssertEqual(doc.rows[0].cells.map(\.content), ["x", "y"])
        XCTAssertEqual(doc.rows[1].cells.map(\.content), ["z", "with, comma"])
    }

    @MainActor
    func testPasteTabSeparated() {
        let doc = CSVDocument()
        doc.parseCSV(content: "A,B\n1,2")
        doc.paste("x\ty", atRow: 0, column: 0)
        XCTAssertEqual(doc.rows[0].cells.map(\.content), ["x", "y"])
    }

    @MainActor
    func testPasteExpandsTable() {
        let doc = CSVDocument()
        doc.parseCSV(content: "A,B\n1,2")
        doc.paste("x,y\nz,w", atRow: 1, column: 1)
        XCTAssertEqual(doc.headers.count, 3)
        XCTAssertEqual(doc.rows.count, 3)
        XCTAssertEqual(doc.rows[1].cells.map(\.content), ["", "x", "y"])
        XCTAssertEqual(doc.rows[2].cells.map(\.content), ["", "z", "w"])
    }

    @MainActor
    func testPasteIntoColumn() {
        let doc = CSVDocument()
        doc.parseCSV(content: "A,B\n1,2\n3,4")
        doc.paste("x\ny", atRow: 0, column: 1)
        XCTAssertEqual(doc.rows[0].cells.map(\.content), ["1", "x"])
        XCTAssertEqual(doc.rows[1].cells.map(\.content), ["3", "y"])
    }

    @MainActor
    func testDeleteRowWithSelection() {
        let doc = CSVDocument()
        doc.parseCSV(content: "A,B\n1,2\n3,4\n5,6")
        let ids = Set(doc.rows.prefix(2).map(\.id))
        doc.delete(row: doc.rows[0], selection: ids)
        XCTAssertEqual(doc.rows.count, 1)
        XCTAssertEqual(doc.rows[0].cells[0].content, "5")
    }

    @MainActor
    func testMoveRow() {
        let doc = CSVDocument()
        doc.parseCSV(content: "A,B\n1,2\n3,4\n5,6")
        doc.move(rowAt: 0, to: 2)
        XCTAssertEqual(doc.rows.map { $0.cells[0].content }, ["3", "5", "1"])
    }

    @MainActor
    func testMoveRowOutOfBoundsIsIgnored() {
        let doc = CSVDocument()
        doc.parseCSV(content: "A,B\n1,2\n3,4")
        doc.move(rowAt: 0, to: 5)
        XCTAssertEqual(doc.rows.map { $0.cells[0].content }, ["1", "3"])
    }

    @MainActor
    func testMoveColumn() {
        let doc = CSVDocument()
        doc.parseCSV(content: "A,B,C\n1,2,3\n4,5,6")
        doc.move(columnAt: 2, to: 0)
        XCTAssertEqual(doc.headers.map(\.name), ["C", "A", "B"])
        XCTAssertEqual(doc.headers.map(\.columnIndex), [0, 1, 2])
        XCTAssertEqual(doc.rows[0].cells.map(\.content), ["3", "1", "2"])
        XCTAssertEqual(doc.rows[1].cells.map(\.content), ["6", "4", "5"])
    }

    @MainActor
    func testUndoRedoDeleteRow() {
        let doc = CSVDocument()
        let undoManager = UndoManager()
        doc.undoManager = undoManager
        doc.parseCSV(content: "A,B\n1,2\n3,4")
        doc.delete(row: doc.rows[0], selection: [])
        XCTAssertEqual(doc.rows.count, 1)
        undoManager.undo()
        XCTAssertEqual(doc.rows.map { $0.cells[0].content }, ["1", "3"])
        undoManager.redo()
        XCTAssertEqual(doc.rows.map { $0.cells[0].content }, ["3"])
    }

    @MainActor
    func testUndoAddColumn() {
        let doc = CSVDocument()
        let undoManager = UndoManager()
        doc.undoManager = undoManager
        doc.parseCSV(content: "A,B\n1,2")
        doc.addColumn()
        XCTAssertEqual(doc.headers.count, 3)
        undoManager.undo()
        XCTAssertEqual(doc.headers.map(\.name), ["A", "B"])
        XCTAssertEqual(doc.rows[0].cells.map(\.content), ["1", "2"])
    }

    @MainActor
    func testUndoMoveColumn() {
        let doc = CSVDocument()
        let undoManager = UndoManager()
        doc.undoManager = undoManager
        doc.parseCSV(content: "A,B,C\n1,2,3")
        doc.move(columnAt: 0, to: 2)
        XCTAssertEqual(doc.headers.map(\.name), ["B", "C", "A"])
        undoManager.undo()
        XCTAssertEqual(doc.headers.map(\.name), ["A", "B", "C"])
        XCTAssertEqual(doc.headers.map(\.columnIndex), [0, 1, 2])
        XCTAssertEqual(doc.rows[0].cells.map(\.content), ["1", "2", "3"])
    }

    @MainActor
    func testUndoCellEditCoalescesKeystrokes() {
        let doc = CSVDocument()
        let undoManager = UndoManager()
        doc.undoManager = undoManager
        doc.parseCSV(content: "A,B\n1,2")
        let binding = doc.cellBinding(for: doc.rows[0], header: doc.headers[0])
        binding.wrappedValue = "x"
        binding.wrappedValue = "xy"
        undoManager.undo()
        XCTAssertEqual(doc.rows[0].cells[0].content, "1")
    }

    @MainActor
    func testBreakUndoCoalescingSeparatesEditSessions() {
        let doc = CSVDocument()
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        doc.undoManager = undoManager
        doc.parseCSV(content: "A,B\n1,2")
        let binding = doc.cellBinding(for: doc.rows[0], header: doc.headers[0])
        undoManager.beginUndoGrouping()
        binding.wrappedValue = "x"
        undoManager.endUndoGrouping()
        doc.breakUndoCoalescing()
        undoManager.beginUndoGrouping()
        binding.wrappedValue = "xy"
        undoManager.endUndoGrouping()
        undoManager.undo()
        XCTAssertEqual(doc.rows[0].cells[0].content, "x")
        undoManager.undo()
        XCTAssertEqual(doc.rows[0].cells[0].content, "1")
    }

    @MainActor
    func testUndoHeaderRename() {
        let doc = CSVDocument()
        let undoManager = UndoManager()
        doc.undoManager = undoManager
        doc.parseCSV(content: "A,B\n1,2")
        doc.headerBinding(for: doc.headers[0]).wrappedValue = "Z"
        XCTAssertEqual(doc.headers[0].name, "Z")
        undoManager.undo()
        XCTAssertEqual(doc.headers[0].name, "A")
    }

    @MainActor
    func testUndoPasteRestoresTableSize() {
        let doc = CSVDocument()
        let undoManager = UndoManager()
        doc.undoManager = undoManager
        doc.parseCSV(content: "A,B\n1,2")
        doc.paste("x,y\nz,w", atRow: 1, column: 1)
        XCTAssertEqual(doc.headers.count, 3)
        XCTAssertEqual(doc.rows.count, 3)
        undoManager.undo()
        XCTAssertEqual(doc.headers.count, 2)
        XCTAssertEqual(doc.rows.count, 1)
        XCTAssertEqual(doc.rows[0].cells.map(\.content), ["1", "2"])
    }

    @MainActor
    func testParseCSVClearsUndoHistory() {
        let doc = CSVDocument()
        let undoManager = UndoManager()
        doc.undoManager = undoManager
        doc.parseCSV(content: "A,B\n1,2")
        doc.addRow()
        doc.parseCSV(content: "C,D\n3,4")
        undoManager.undo()
        XCTAssertEqual(doc.headers.map(\.name), ["C", "D"])
        XCTAssertEqual(doc.rows[0].cells.map(\.content), ["3", "4"])
    }
}
