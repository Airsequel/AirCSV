import SwiftCSV
import SwiftUI

class CSVDocument: ObservableObject {

  @Published var url: URL?
  @Published var content: String = ""
  @Published var headers: [CSVHeader] = []
  @Published var rows: [CSVRow] = []

  /// True while the file's content is still being parsed on a background
  /// thread. The view shows a loading spinner in the meantime so the
  /// window can appear immediately instead of waiting for a large file.
  @Published var isLoading = false

  /// Content decoded at open time but not yet parsed. Cleared once
  /// `loadPendingContent()` has kicked off the background parse.
  private var pendingContent: String?

  /// Delimiter detected when the file was parsed. Used to serialize the
  /// document back out so a CSV stays comma-separated and a TSV
  /// tab-separated.
  @Published var delimiter: CSVDelimiter = .comma

  /// The window's undo manager, injected by the view layer. Weak because
  /// the window owns it.
  weak var undoManager: UndoManager?
  private var undoableActionDepth = 0
  /// Coalescing key of the most recent undo registration. Consecutive
  /// actions with the same key (e.g. keystrokes into one cell) merge
  /// into a single undo step.
  private var lastCoalescingKey: String?

  init() {}

  required init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw CocoaError(.fileReadCorruptFile)
    }
    guard let fileContent = String(data: data, encoding: .utf8) else {
      throw CocoaError(.fileReadInapplicableStringEncoding)
    }
    // Defer parsing so the window appears immediately. The view calls
    // `loadPendingContent()` once it's on screen, which parses in the
    // background and clears `isLoading`.
    self.content = fileContent
    self.pendingContent = fileContent
    self.isLoading = true
  }

  /// Parses the content stored at open time on a background thread, then
  /// publishes the table on the main thread and clears `isLoading`. Does
  /// nothing if there's no pending content (e.g. a new empty document or
  /// after the file has already loaded).
  func loadPendingContent() {
    guard let content = pendingContent else { return }
    pendingContent = nil
    Task.detached(priority: .userInitiated) { [weak self] in
      let parsed = Self.parseTable(content: content)
      await MainActor.run {
        guard let self else { return }
        self.apply(parsed)
        self.isLoading = false
      }
    }
  }

  func handleFileImport(for result: Result<URL, Error>) {
    switch result {
    case .success(let url):
      readFile(url)
    case .failure(let error):
      print("Failed to import file: \(error)")
    }
  }

  func readFile(_ url: URL) {
    guard url.startAccessingSecurityScopedResource() else { return }
    defer { url.stopAccessingSecurityScopedResource() }
    self.url = url

    do {
      let content = try String(contentsOf: url, encoding: .utf8)
      self.content = content
      parseCSV(content: content)
    } catch {
      print("Failed to read \(url.lastPathComponent): \(error)")
    }
  }

  /// The parsed table together with the delimiter it was parsed with
  /// and the column fit widths measured alongside the parse.
  struct ParsedTable {
    let delimiter: CSVDelimiter
    let headers: [CSVHeader]
    let rows: [CSVRow]
    /// Minimum width per column (keyed by header id) that fully shows
    /// header and cells. Measured off the main thread because doing it
    /// for every cell at first render blocks the UI for seconds on
    /// larger files.
    let fitWidths: [UUID: CGFloat]
    var hasContent: Bool { !headers.isEmpty }
  }

  func parseCSV(content: String) {
    apply(Self.parseTable(content: content))
  }

  /// Parses CSV text into headers and rows. Pure and self-contained so it
  /// can run off the main thread; the caller applies the result via
  /// `apply(_:)`.
  static func parseTable(content: String) -> ParsedTable {
    let delimiter = CSVDelimiter.guessed(string: content)

    let table: [[String]]
    if let data = try? EnumeratedCSV(string: content, delimiter: delimiter, loadColumns: false) {
      table = [data.header] + data.rows
    } else {
      // SwiftCSV's parser rejects RFC-noncompliant content such as
      // unescaped quotes inside an unquoted field (e.g. `Eddie "Lockjaw"
      // Davis`). Fall back to splitting on the delimiter so messy
      // real-world files still open instead of showing an empty window.
      table = lenientParse(content: content, delimiter: delimiter.rawValue)
    }

    guard let header = table.first else {
      return ParsedTable(delimiter: delimiter, headers: [], rows: [], fitWidths: [:])
    }
    let headers = CSVHeader.createHeaders(data: header)
    let rows = table.dropFirst().map { CSVRow(cells: $0.map { CSVCell(content: $0) }) }
    return ParsedTable(
      delimiter: delimiter,
      headers: headers,
      rows: rows,
      fitWidths: Dictionary(
        uniqueKeysWithValues: headers.map { ($0.id, measuredFitWidth(for: $0, rows: rows)) })
    )
  }

  /// Publishes a parsed table onto the document and resets the editing
  /// history. An empty result (no header row) leaves the table untouched.
  private func apply(_ parsed: ParsedTable) {
    self.delimiter = parsed.delimiter
    guard parsed.hasContent else { return }
    self.fitWidthCache = parsed.fitWidths
    self.headers = parsed.headers
    self.rows = parsed.rows

    // A freshly loaded file starts with a clean editing history.
    undoManager?.removeAllActions(withTarget: self)
    lastCoalescingKey = nil
  }

  /// Splits `content` into rows and fields on the delimiter, treating
  /// quotes as literal characters. Used as a fallback when strict CSV
  /// parsing fails, so malformed files still load.
  private static func lenientParse(content: String, delimiter: Character) -> [[String]] {
    let normalized =
      content
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    var lines = normalized.components(separatedBy: "\n")
    if lines.last == "" { lines.removeLast() }
    return lines.map { $0.components(separatedBy: String(delimiter)) }
  }

  //MARK: - Undo

  private struct TableState {
    let headers: [CSVHeader]
    let rows: [CSVRow]
  }

  /// Runs the mutation as a single undoable action by snapshotting the
  /// whole table beforehand. Nested calls register no extra snapshots.
  /// Consecutive actions with the same non-nil coalescing key merge into
  /// one undo step.
  private func performUndoable(
    _ actionName: String, coalescing key: String? = nil, mutate: () -> Void
  ) {
    if undoableActionDepth == 0 {
      registerUndoSnapshot(actionName, coalescing: key)
    }
    undoableActionDepth += 1
    defer { undoableActionDepth -= 1 }
    mutate()
  }

  private func registerUndoSnapshot(_ actionName: String, coalescing key: String?) {
    defer { lastCoalescingKey = key }
    if let key, key == lastCoalescingKey { return }
    let state = TableState(headers: headers, rows: rows)
    undoManager?.registerUndo(withTarget: self) { $0.restore(state) }
    undoManager?.setActionName(actionName)
  }

  /// Swaps the table back to the given snapshot, registering the inverse
  /// so the same mechanism serves undo and redo.
  private func restore(_ state: TableState) {
    let current = TableState(headers: headers, rows: rows)
    undoManager?.registerUndo(withTarget: self) { $0.restore(current) }
    headers = state.headers
    rows = state.rows
    lastCoalescingKey = nil
  }

  /// Ends the current coalescing run so the next edit with the same key
  /// starts a new undo step (e.g. when an edit session ends).
  func breakUndoCoalescing() {
    lastCoalescingKey = nil
  }

  //MARK: - Layout

  /// Width of the row-number column: fits the largest row number,
  /// measured with the same monospaced font the cells render in.
  var rowNumberColumnWidth: CGFloat {
    Self.rowNumberWidth(digits: String(max(rows.count, 1)).count)
  }

  /// Measured widths per digit count, cached because the width is read
  /// for every visible row on each render.
  private static var rowNumberWidthCache: [Int: CGFloat] = [:]

  private static func rowNumberWidth(digits: Int) -> CGFloat {
    if let width = rowNumberWidthCache[digits] { return width }
    let font = NSFont.monospacedSystemFont(
      ofSize: NSFont.systemFontSize, weight: .regular)
    let sample = String(repeating: "8", count: digits)
    let width = max(
      40, ceil((sample as NSString).size(withAttributes: [.font: font]).width) + 16)
    rowNumberWidthCache[digits] = width
    return width
  }

  /// Fit widths measured during the last parse, so first render doesn't
  /// re-measure every cell on the main thread. Not published: purely a
  /// cache for `cachedFitWidth(for:)`.
  private var fitWidthCache: [UUID: CGFloat] = [:]

  /// Minimum width that fully shows the column's header and cells,
  /// measured from the rendered text widths. Prefers the width measured
  /// during the background parse; measures live (and caches) only for
  /// columns added since.
  func cachedFitWidth(for header: CSVHeader) -> CGFloat {
    if let width = fitWidthCache[header.id] { return width }
    let width = fitWidth(for: header)
    fitWidthCache[header.id] = width
    return width
  }

  /// Minimum width that fully shows the column's header and cells,
  /// re-measured from the current content.
  func fitWidth(for header: CSVHeader) -> CGFloat {
    Self.measuredFitWidth(for: header, rows: rows)
  }

  /// Static and self-contained so it can run off the main thread during
  /// the background parse. String measurement is thread-safe.
  ///
  /// Measuring text is ~70× slower than counting bytes, so instead of
  /// measuring every cell (tens of seconds on a 500k-row file), scan
  /// for the few widest candidates by UTF-8 length and measure only
  /// those. Cells render in a monospaced font, so byte count is a
  /// faithful width proxy — and it over-weights multi-byte characters
  /// (CJK, emoji), which render wider, so the candidate set errs
  /// toward including them. Measuring several candidates absorbs the
  /// remaining count-vs-width mismatch.
  private static func measuredFitWidth(for header: CSVHeader, rows: [CSVRow]) -> CGFloat {
    let cellFont = NSFont.monospacedSystemFont(
      ofSize: NSFont.systemFontSize, weight: .regular)
    let headerFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)

    let headerWidth = (header.name as NSString)
      .size(withAttributes: [.font: headerFont]).width

    // The widest candidates seen so far, sorted ascending by byte
    // count so the weakest is always at index 0.
    let candidateCount = 8
    var candidates: [(bytes: Int, content: String)] = []
    for row in rows where row.cells.count > header.columnIndex {
      let content = row.cells[header.columnIndex].content
      let bytes = content.utf8.count
      if candidates.count < candidateCount {
        candidates.append((bytes, content))
        candidates.sort { $0.bytes < $1.bytes }
      } else if bytes > candidates[0].bytes {
        candidates[0] = (bytes, content)
        var index = 0
        while index + 1 < candidates.count,
          candidates[index].bytes > candidates[index + 1].bytes
        {
          candidates.swapAt(index, index + 1)
          index += 1
        }
      }
    }
    let maxCellWidth =
      Set(candidates.map(\.content)).map {
        ($0 as NSString).size(withAttributes: [.font: cellFont]).width
      }.max() ?? 0

    let horizontalPadding: CGFloat = 16
    return max(50, ceil(max(headerWidth, maxCellWidth)) + horizontalPadding)
  }

  //MARK: - Edit

  func delete(row: CSVRow, selection: Set<CSVRow.ID>) {
    performUndoable("Delete Row") {
      if selection.contains(row.id) {
        self.rows.removeAll { selection.contains($0.id) }
      } else {
        self.rows.removeAll(where: { $0.id == row.id })
      }
    }
  }

  func clear(row: CSVRow, selection: Set<CSVRow.ID>) {
    clear(rows: selection.contains(row.id) ? selection : [row.id])
  }

  func clear(rows selection: Set<CSVRow.ID>) {
    performUndoable("Clear Rows") {
      for index in rows.indices where selection.contains(rows[index].id) {
        for cellIndex in rows[index].cells.indices {
          rows[index].cells[cellIndex].content = ""
        }
      }
    }
  }

  func clear(columns selection: Set<CSVHeader.ID>) {
    performUndoable("Clear Columns") {
      for header in headers where selection.contains(header.id) {
        clear(column: header)
      }
    }
  }

  func clear(column header: CSVHeader) {
    performUndoable("Clear Column") {
      for index in rows.indices where rows[index].cells.indices.contains(header.columnIndex) {
        rows[index].cells[header.columnIndex].content = ""
      }
    }
  }

  func delete(column header: CSVHeader) {
    guard let headerIndex = headers.firstIndex(where: { $0.id == header.id }) else { return }
    performUndoable("Delete Column") {
      headers.remove(at: headerIndex)
      for index in rows.indices where rows[index].cells.indices.contains(header.columnIndex) {
        rows[index].cells.remove(at: header.columnIndex)
      }
      for index in headers.indices {
        headers[index].columnIndex = index
      }
    }
  }

  func addRow() {
    performUndoable("Add Row") {
      rows.append(CSVRow(cells: headers.map { _ in CSVCell(content: "") }))
    }
  }

  func addColumn() {
    performUndoable("Add Column") {
      headers.append(
        CSVHeader(name: "Column \(headers.count + 1)", columnIndex: headers.count))
      for index in rows.indices {
        while rows[index].cells.count < headers.count {
          rows[index].cells.append(CSVCell(content: ""))
        }
      }
    }
  }

  /// Moves the row to the given position. Out-of-bounds indices are
  /// ignored.
  func move(rowAt from: Int, to: Int) {
    guard from != to, rows.indices.contains(from), rows.indices.contains(to) else { return }
    performUndoable("Move Row") {
      let row = rows.remove(at: from)
      rows.insert(row, at: to)
    }
  }

  /// Moves the column (header and every row's cell) to the given
  /// position and renumbers the column indices.
  func move(columnAt from: Int, to: Int) {
    guard from != to, headers.indices.contains(from), headers.indices.contains(to) else {
      return
    }
    performUndoable("Move Column") {
      let header = headers.remove(at: from)
      headers.insert(header, at: to)
      for index in rows.indices where rows[index].cells.indices.contains(from) {
        let cell = rows[index].cells.remove(at: from)
        rows[index].cells.insert(cell, at: min(to, rows[index].cells.count))
      }
      for index in headers.indices {
        headers[index].columnIndex = index
      }
    }
  }

  func headerBinding(for header: CSVHeader) -> Binding<String> {
    Binding {
      self.headers.first(where: { $0.id == header.id })?.name ?? ""
    } set: { newValue in
      if let index = self.headers.firstIndex(where: { $0.id == header.id }),
        self.headers[index].name != newValue
      {
        self.performUndoable("Rename Column", coalescing: "header-\(header.id)") {
          self.headers[index].name = newValue
        }
      }
    }
  }

  func cellBinding(for row: CSVRow, header: CSVHeader) -> Binding<String> {
    Binding {
      if let r = self.rows.first(where: { $0.id == row.id }),
        r.cells.count > header.columnIndex
      {
        return r.cells[header.columnIndex].content
      }
      return ""
    } set: { newValue in
      if let rowIndex = self.rows.firstIndex(where: { $0.id == row.id }),
        self.rows[rowIndex].cells[header.columnIndex].content != newValue
      {
        self.performUndoable("Edit Cell", coalescing: "cell-\(row.id)-\(header.id)") {
          self.rows[rowIndex].cells[header.columnIndex].content = newValue
        }
      }
    }
  }

  //MARK: - Clipboard

  /// The selected rows serialized as CSV lines, in table order.
  func copyContent(rows selection: Set<CSVRow.ID>) -> String {
    rows.filter { selection.contains($0.id) }
      .map { exportContent(for: $0) }
      .joined(separator: "\n")
  }

  /// The selected columns serialized as CSV lines, one per row, in table
  /// order.
  func copyContent(columns selection: Set<CSVHeader.ID>) -> String {
    let selectedHeaders = headers.filter { selection.contains($0.id) }
    return rows.map { row in
      selectedHeaders.map { header in
        row.cells.indices.contains(header.columnIndex)
          ? row.cells[header.columnIndex].exportContent(delimiter: delimiter.rawValue)
          : ""
      }.joined(separator: String(delimiter.rawValue))
    }.joined(separator: "\n")
  }

  /// The cell block serialized as CSV lines. Both ranges must lie within
  /// the table bounds.
  func copyContent(rowRange: ClosedRange<Int>, columnRange: ClosedRange<Int>) -> String {
    rowRange.map { rowIndex in
      columnRange.map { columnIndex in
        rows[rowIndex].cells.indices.contains(columnIndex)
          ? rows[rowIndex].cells[columnIndex].exportContent(delimiter: delimiter.rawValue)
          : ""
      }.joined(separator: String(delimiter.rawValue))
    }.joined(separator: "\n")
  }

  /// Clear all cells in the block. Both ranges must lie within the table
  /// bounds.
  func clear(rowRange: ClosedRange<Int>, columnRange: ClosedRange<Int>) {
    performUndoable("Clear Cells") {
      for rowIndex in rowRange {
        for columnIndex in columnRange
        where rows[rowIndex].cells.indices.contains(columnIndex) {
          rows[rowIndex].cells[columnIndex].content = ""
        }
      }
    }
  }

  /// Paste delimited text with its top-left field at the given position,
  /// adding rows and columns as needed.
  func paste(_ text: String, atRow startRow: Int, column startColumn: Int) {
    performUndoable("Paste") {
      for (rowOffset, fields) in parseFields(text).enumerated() {
        let rowIndex = startRow + rowOffset
        while rows.count <= rowIndex { addRow() }
        for (columnOffset, field) in fields.enumerated() {
          let columnIndex = startColumn + columnOffset
          while headers.count <= columnIndex { addColumn() }
          while rows[rowIndex].cells.count <= columnIndex {
            rows[rowIndex].cells.append(CSVCell(content: ""))
          }
          rows[rowIndex].cells[columnIndex].content = field
        }
      }
    }
  }

  /// Parse pasted text into a grid of fields, guessing the delimiter
  /// (comma, tab, or semicolon). Falls back to one field per line when the
  /// text isn't parseable.
  private func parseFields(_ text: String) -> [[String]] {
    var trimmed = text
    while let last = trimmed.last, last.isNewline { trimmed.removeLast() }
    guard !trimmed.isEmpty else { return [] }
    if let csv = try? EnumeratedCSV(string: trimmed, loadColumns: false) {
      return [csv.header] + csv.rows
    }
    return trimmed.components(separatedBy: .newlines).map { [$0] }
  }

  //MARK: - Preview

  static var preview: CSVDocument {
    let doc = CSVDocument()
    doc.content = sampleCSV
    doc.parseCSV(content: sampleCSV)
    return doc
  }

  static var sampleCSV: String {
    """
    Keyword,Search volume
    swiftui components list,10
    swiftui list not showing,20
    swiftui uitableview,20
    swift tab view,20
    ios tabview,20
    table view swiftui,20
    table swiftui,20
    swift listview,30
    swift list view,30
    swiftui list example,30
    tabitem swiftui,30
    tableview swiftui,40
    tab bar swiftui,50
    swift ui table view,50
    swiftui table view,50
    """
  }
}
