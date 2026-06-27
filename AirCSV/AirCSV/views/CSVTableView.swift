import SwiftUI
import UniformTypeIdentifiers

struct CellAddress: Hashable {
  let rowID: CSVRow.ID
  let headerID: CSVHeader.ID
}

/// The grid's selection and active cell-edit session. The selection kinds
/// (cell, cell range, rows, columns) are mutually exclusive: selecting one
/// clears the others. The view's `focusedCell` — a `@FocusState`, which a
/// value type can't hold — mirrors `editingCell`.
struct TableSelection: Equatable {
  /// Anchor of a cell selection.
  var cell: CellAddress?
  /// Far corner of a shift+click range; `cell` is the anchor. Nil while
  /// only a single cell is selected.
  var rangeEnd: CellAddress?
  var rows: Set<CSVRow.ID> = []
  var columns: Set<CSVHeader.ID> = []
  /// The cell whose field editor is open, if any.
  var editingCell: CellAddress?

  /// Select a single cell, ending any other selection or edit session.
  mutating func select(cell address: CellAddress) {
    self = TableSelection(cell: address)
  }

  /// Extend the cell selection into a rectangle ending at `address`.
  mutating func extend(to address: CellAddress) {
    rangeEnd = address
    rows = []
    columns = []
    editingCell = nil
  }

  mutating func select(row id: CSVRow.ID) {
    self = TableSelection(rows: [id])
  }

  mutating func select(column id: CSVHeader.ID) {
    self = TableSelection(columns: [id])
  }

  /// Open the field editor on a cell, selecting it.
  mutating func beginEditing(_ address: CellAddress) {
    self = TableSelection(cell: address, editingCell: address)
  }

  /// Close the field editor, keeping the cell selected.
  mutating func endEditing() {
    editingCell = nil
  }
}

struct CSVTableView: View {

  @ObservedObject var document: CSVDocument
  @Binding var wrapContent: Bool
  @State private var selection = TableSelection()
  @FocusState private var focusedCell: CellAddress?
  @State private var columnWidths: [UUID: CGFloat] = [:]
  @State private var dragStartWidths: [UUID: CGFloat] = [:]
  @State private var keyMonitor: Any?
  @State private var hoveringAddRow = false
  @State private var hoveringAddColumn = false
  @State private var editingHeader: CSVHeader.ID?
  @FocusState private var focusedHeader: CSVHeader.ID?
  @State private var draggedRow: CSVRow.ID?
  @State private var draggedColumn: CSVHeader.ID?
  @State private var rowDropIndicator: RowDropIndicator?
  @State private var columnDropIndicator: ColumnDropIndicator?
  /// Rendered row heights, needed for the drop midpoint test because
  /// wrapped cells make row heights vary.
  @State private var rowHeights: [CSVRow.ID: CGFloat] = [:]

  func columnWidth(for header: CSVHeader) -> CGFloat {
    columnWidths[header.id] ?? document.idealWidth(for: header)
  }

  /// Width of a data row: row number column plus all data columns.
  var tableWidth: CGFloat {
    document.headers.reduce(document.rowNumberColumnWidth) { $0 + columnWidth(for: $1) }
  }

  func sizeAllColumnsToFit() {
    for header in document.headers {
      columnWidths[header.id] = document.fitWidth(for: header)
    }
  }

  /// Move the edit session to the cell offset by the given deltas, or end
  /// editing when that would leave the table.
  func moveEditing(rowDelta: Int, columnDelta: Int) {
    guard let current = selection.editingCell,
      let rowIndex = document.rows.firstIndex(where: { $0.id == current.rowID }),
      let columnIndex = document.headers.firstIndex(where: { $0.id == current.headerID })
    else { return }
    let targetRow = rowIndex + rowDelta
    let targetColumn = columnIndex + columnDelta
    guard document.rows.indices.contains(targetRow),
      document.headers.indices.contains(targetColumn)
    else {
      selection.endEditing()
      focusedCell = nil
      return
    }
    let target = CellAddress(
      rowID: document.rows[targetRow].id,
      headerID: document.headers[targetColumn].id
    )
    selection.beginEditing(target)
    DispatchQueue.main.async { focusedCell = target }
  }

  /// Move the selection to the cell offset by the given deltas, clamped to
  /// the table bounds.
  func moveSelection(rowDelta: Int, columnDelta: Int) {
    guard let current = selection.cell,
      let rowIndex = document.rows.firstIndex(where: { $0.id == current.rowID }),
      let columnIndex = document.headers.firstIndex(where: { $0.id == current.headerID })
    else { return }
    let targetRow = min(max(rowIndex + rowDelta, 0), document.rows.count - 1)
    let targetColumn = min(max(columnIndex + columnDelta, 0), document.headers.count - 1)
    selection.select(
      cell: CellAddress(
        rowID: document.rows[targetRow].id,
        headerID: document.headers[targetColumn].id
      ))
  }

  /// Row and column index bounds of the cell selection rectangle spanned
  /// by the anchor cell and the shift+click extent, or nil when no cell
  /// is selected.
  func selectionRange() -> (rows: ClosedRange<Int>, columns: ClosedRange<Int>)? {
    guard let anchor = selection.cell,
      let anchorRow = document.rows.firstIndex(where: { $0.id == anchor.rowID }),
      let anchorColumn = document.headers.firstIndex(where: { $0.id == anchor.headerID })
    else { return nil }
    guard let end = selection.rangeEnd,
      let endRow = document.rows.firstIndex(where: { $0.id == end.rowID }),
      let endColumn = document.headers.firstIndex(where: { $0.id == end.headerID })
    else { return (anchorRow...anchorRow, anchorColumn...anchorColumn) }
    return (
      min(anchorRow, endRow)...max(anchorRow, endRow),
      min(anchorColumn, endColumn)...max(anchorColumn, endColumn)
    )
  }

  /// Copy the selected cells, rows, or columns to the pasteboard. Returns
  /// false when nothing is selected.
  func copySelection() -> Bool {
    let content: String
    if let range = selectionRange() {
      if range.rows.count == 1, range.columns.count == 1 {
        // A single cell copies its raw content, without CSV escaping.
        let cells = document.rows[range.rows.lowerBound].cells
        content =
          cells.indices.contains(range.columns.lowerBound)
          ? cells[range.columns.lowerBound].content
          : ""
      } else {
        content = document.copyContent(
          rowRange: range.rows, columnRange: range.columns)
      }
    } else if !selection.rows.isEmpty {
      content = document.copyContent(rows: selection.rows)
    } else if !selection.columns.isEmpty {
      content = document.copyContent(columns: selection.columns)
    } else {
      return false
    }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(content, forType: .string)
    return true
  }

  /// Copy the selection, then clear its cells.
  func cutSelection() -> Bool {
    guard copySelection() else { return false }
    if let range = selectionRange() {
      document.clear(rowRange: range.rows, columnRange: range.columns)
    } else if !selection.rows.isEmpty {
      document.clear(rows: selection.rows)
    } else if !selection.columns.isEmpty {
      document.clear(columns: selection.columns)
    }
    return true
  }

  /// Paste the pasteboard starting at the top-left selected cell, the
  /// first selected row, or the first selected column. Returns false when
  /// nothing is selected or the pasteboard has no text.
  func pasteSelection() -> Bool {
    guard let text = NSPasteboard.general.string(forType: .string) else { return false }
    if let range = selectionRange() {
      document.paste(
        text, atRow: range.rows.lowerBound, column: range.columns.lowerBound)
    } else if let rowIndex = document.rows.firstIndex(where: { selection.rows.contains($0.id) }) {
      document.paste(text, atRow: rowIndex, column: 0)
    } else if let columnIndex = document.headers.firstIndex(where: {
      selection.columns.contains($0.id)
    }) {
      document.paste(text, atRow: 0, column: columnIndex)
    } else {
      return false
    }
    return true
  }

  /// The cell content as an openable web URL, or nil if it isn't one.
  func cellURL(_ content: String) -> URL? {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed),
      let scheme = url.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      url.host() != nil
    else { return nil }
    return url
  }

  /// Replace the field editor's begin-editing select-all with a collapsed
  /// cursor at the double-clicked character. Retries because focus is
  /// applied asynchronously after `focusedCell` is set.
  func placeCursor(at windowPoint: CGPoint?, attempt: Int = 0) {
    guard let windowPoint, attempt < 10 else { return }
    guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else {
      DispatchQueue.main.async { placeCursor(at: windowPoint, attempt: attempt + 1) }
      return
    }
    let point = editor.convert(windowPoint, from: nil)
    let index = editor.characterIndexForInsertion(at: point)
    editor.setSelectedRange(NSRange(location: index, length: 0))
  }

  /// Index of the gap (0...rows.count) the row drop indicator points at,
  /// or nil. A gap has two hover representations (below one row, above
  /// the next); mapping both to one index keeps the rendered line from
  /// jumping when the cursor crosses the edge between them.
  func indicatedRowGap() -> Int? {
    guard let indicator = rowDropIndicator,
      let index = document.rows.firstIndex(where: { $0.id == indicator.rowID })
    else { return nil }
    return indicator.insertAfter ? index + 1 : index
  }

  /// Index of the gap (0...headers.count) the column drop indicator
  /// points at, or nil. See `indicatedRowGap`.
  func indicatedColumnGap() -> Int? {
    guard let indicator = columnDropIndicator,
      let index = document.headers.firstIndex(where: { $0.id == indicator.headerID })
    else { return nil }
    return indicator.insertAfter ? index + 1 : index
  }

  var body: some View {
    // Computed once per render; cells check membership by index.
    let selectionRect = selectionRange()
    let rowGap = indicatedRowGap()
    let columnGap = indicatedColumnGap()
    GeometryReader { geometry in
      ScrollView([.horizontal, .vertical]) {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
          Section {
            ForEach(Array(document.rows.enumerated()), id: \.element.id) { index, row in
              HStack(spacing: 0) {
                Text("\(index + 1)")
                  .foregroundStyle(.secondary)
                  .font(.system(.body, design: .monospaced))
                  .padding(.horizontal, 8)
                  .padding(.vertical, 6)
                  .frame(width: document.rowNumberColumnWidth, alignment: .trailing)
                  .frame(maxHeight: .infinity)
                  .background(Color(nsColor: .windowBackgroundColor))
                  .overlay(alignment: .trailing) { Divider() }
                  .contentShape(Rectangle())
                  .onTapGesture {
                    selection.select(row: row.id)
                    focusedCell = nil
                  }
                  .onDrag {
                    draggedRow = row.id
                    draggedColumn = nil
                    return NSItemProvider(object: row.id.uuidString as NSString)
                  }
                  .overlay(
                    RightClickMenu {
                      selection.select(row: row.id)
                      focusedCell = nil
                      return [
                        MenuAction(title: "Copy Row") {
                          NSPasteboard.general.clearContents()
                          NSPasteboard.general.setString(
                            document.exportContent(for: row), forType: .string)
                        },
                        MenuAction(title: "Clear Row") {
                          document.clear(row: row, selection: [row.id])
                        },
                        MenuAction(title: "Delete Row") {
                          document.delete(row: row, selection: [row.id])
                        },
                      ]
                    }
                  )
                ForEach(document.headers) { header in
                  let address = CellAddress(rowID: row.id, headerID: header.id)
                  Group {
                    if selection.editingCell == address {
                      TextField(
                        "", text: document.cellBinding(for: row, header: header),
                        axis: .vertical
                      )
                      .textFieldStyle(.plain)
                      .focused($focusedCell, equals: address)
                      .onSubmit { moveEditing(rowDelta: 1, columnDelta: 0) }
                      .onExitCommand { selection.endEditing() }
                    } else {
                      Text(document.cellBinding(for: row, header: header).wrappedValue)
                        .lineLimit(wrapContent ? nil : 1)
                        .truncationMode(.tail)
                    }
                  }
                  .font(.system(.body, design: .monospaced))
                  .padding(.horizontal, 8)
                  .padding(.vertical, 6)
                  .frame(width: columnWidth(for: header), alignment: .leading)
                  .frame(maxHeight: .infinity)
                  .background(
                    selectionRect.map {
                      $0.rows.contains(index) && $0.columns.contains(header.columnIndex)
                    } == true
                      ? Color.accentColor.opacity(0.25)
                      : selection.columns.contains(header.id)
                        ? Color.accentColor.opacity(0.15)
                        : Color.clear
                  )
                  .overlay(alignment: .trailing) { Divider() }
                  // Insertion line for the gap left of this column — or,
                  // on the last column, also for the gap right of it.
                  .overlay(alignment: .leading) {
                    if columnGap == header.columnIndex {
                      Rectangle().fill(Color.accentColor).frame(width: 2)
                    }
                  }
                  .overlay(alignment: .trailing) {
                    if header.columnIndex == document.headers.count - 1,
                      columnGap == document.headers.count
                    {
                      Rectangle().fill(Color.accentColor).frame(width: 2)
                    }
                  }
                  .contentShape(Rectangle())
                  .simultaneousGesture(
                    TapGesture().onEnded {
                      let event = NSApp.currentEvent
                      // Shift+click extends the selection from the anchor
                      // cell into a rectangular range.
                      if event?.modifierFlags.contains(.shift) == true,
                        selection.cell != nil,
                        selection.editingCell != address
                      {
                        selection.extend(to: address)
                        focusedCell = nil
                        return
                      }
                      // Clicks inside the cell's own active editor (cursor
                      // placement, word selection) are the editor's business.
                      guard selection.editingCell != address else { return }
                      // Detect double clicks via the AppKit event instead of
                      // TapGesture(count: 2): the recognizer's click counter
                      // resets when the first click ends another cell's edit
                      // session and the view tree rebuilds.
                      if (event?.clickCount ?? 0) >= 2 {
                        selection.beginEditing(address)
                        let clickLocation = event?.locationInWindow
                        DispatchQueue.main.async {
                          focusedCell = address
                          DispatchQueue.main.async { placeCursor(at: clickLocation) }
                        }
                      } else {
                        // Single click on another cell ends any active edit
                        // session. Done here explicitly because the field
                        // editor keeps first responder when a gesture-only
                        // view is clicked, so no focus change would fire.
                        selection.select(cell: address)
                        focusedCell = nil
                      }
                    }
                  )
                  .overlay {
                    // No catcher while editing, so the field editor keeps
                    // its own clicks and text context menu.
                    if selection.editingCell != address {
                      RightClickMenu {
                        selection.select(cell: address)
                        focusedCell = nil
                        let content =
                          document.cellBinding(for: row, header: header).wrappedValue
                        var actions = [
                          MenuAction(title: "Copy Cell") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(content, forType: .string)
                          },
                          MenuAction(title: "Clear Cell") {
                            document.cellBinding(for: row, header: header).wrappedValue = ""
                          },
                        ]
                        if let url = cellURL(content) {
                          actions.append(
                            MenuAction(title: "Open URL") {
                              NSWorkspace.shared.open(url)
                            })
                        }
                        return actions
                      }
                    }
                  }
                }
              }
              // Size the row to its tallest cell, then let every cell fill
              // that height so backgrounds and dividers span the full row.
              .fixedSize(horizontal: false, vertical: true)
              .background(
                selection.rows.contains(row.id)
                  ? Color.accentColor.opacity(0.15)
                  : Color(
                    NSColor.alternatingContentBackgroundColors[index.isMultiple(of: 2) ? 0 : 1])
              )
              .overlay(alignment: .bottom) { Divider() }
              // Insertion line for the gap above this row — or, on the
              // last row, also for the gap below it.
              .overlay(alignment: .top) {
                if rowGap == index {
                  Rectangle().fill(Color.accentColor).frame(height: 2)
                }
              }
              .overlay(alignment: .bottom) {
                if index == document.rows.count - 1, rowGap == document.rows.count {
                  Rectangle().fill(Color.accentColor).frame(height: 2)
                }
              }
              .contentShape(Rectangle())
              // Records the row height for the drop delegate's midpoint
              // test without affecting layout or hit testing.
              .background(
                GeometryReader { geometry in
                  Color.clear
                    .onAppear { rowHeights[row.id] = geometry.size.height }
                    .onChange(of: geometry.size.height) {
                      rowHeights[row.id] = geometry.size.height
                    }
                }
              )
              .onDrop(
                of: [.text],
                delegate: RowReorderDropDelegate(
                  rowID: row.id, rowHeight: rowHeights[row.id] ?? 0,
                  document: document,
                  draggedRow: $draggedRow, indicator: $rowDropIndicator))
            }
            Button {
              document.addRow()
            } label: {
              // The strip spans at least the window so it stays clickable
              // under the window-centered "+". A hidden "+" fixes the
              // strip's height; the visible one is overlaid and kept at the
              // window's horizontal center.
              let stripWidth = max(tableWidth, geometry.size.width)
              Image(systemName: "plus")
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .hidden()
                .frame(width: stripWidth)
                .background(
                  hoveringAddRow
                    ? Color.accentColor.opacity(0.25)
                    : Color.white
                )
                .overlay {
                  // The glyph rides with the strip vertically (it lives in
                  // the scrolling content), but `visualEffect` counters the
                  // horizontal scroll so it stays centered on the window.
                  // The effect is render-synced, so it never lags or sticks.
                  Image(systemName: "plus")
                    .visualEffect { content, proxy in
                      content.offset(
                        x: geometry.size.width / 2
                          - proxy.frame(in: .named("viewport")).midX)
                    }
                }
                // A bare Divider on an Image base renders vertical; the
                // VStack forces the horizontal orientation.
                .overlay(alignment: .bottom) { VStack(spacing: 0) { Divider() } }
                .overlay(alignment: .trailing) { Divider() }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusEffectDisabled()
            .foregroundStyle(.secondary)
            .onHover { hoveringAddRow = $0 }
            .help("Add row")
            // The strip below the last row accepts row drags, so the gap
            // after the last row has a drop area below its line too.
            .onDrop(
              of: [.text],
              delegate: RowEndDropDelegate(
                document: document,
                draggedRow: $draggedRow, indicator: $rowDropIndicator))
          } header: {
            HStack(spacing: 0) {
              Text("#")
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(width: document.rowNumberColumnWidth, alignment: .trailing)
                .background(Color(nsColor: .windowBackgroundColor))
                .overlay(alignment: .trailing) { Divider() }
              ForEach(document.headers) { header in
                Group {
                  if editingHeader == header.id {
                    TextField("", text: document.headerBinding(for: header))
                      .textFieldStyle(.plain)
                      .focused($focusedHeader, equals: header.id)
                      .onSubmit { editingHeader = nil }
                      .onExitCommand { editingHeader = nil }
                  } else {
                    Text(header.name)
                  }
                }
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(width: columnWidth(for: header), alignment: .leading)
                .background(
                  selection.columns.contains(header.id)
                    ? Color.accentColor.opacity(0.15)
                    : Color.clear
                )
                .contentShape(Rectangle())
                // Plain gesture (not simultaneous) so the resize handle's
                // own double-click keeps priority within its strip.
                .gesture(
                  TapGesture().onEnded {
                    guard editingHeader != header.id else { return }
                    if let event = NSApp.currentEvent, event.clickCount >= 2 {
                      editingHeader = header.id
                      let clickLocation = event.locationInWindow
                      DispatchQueue.main.async {
                        focusedHeader = header.id
                        DispatchQueue.main.async { placeCursor(at: clickLocation) }
                      }
                    } else {
                      selection.select(column: header.id)
                      focusedCell = nil
                    }
                  }
                )
                .onDrag {
                  draggedColumn = header.id
                  draggedRow = nil
                  return NSItemProvider(object: header.id.uuidString as NSString)
                }
                .overlay {
                  // No catcher while renaming, so the field editor keeps
                  // its own clicks and text context menu.
                  if editingHeader != header.id {
                    RightClickMenu {
                      selection.select(column: header.id)
                      focusedCell = nil
                      editingHeader = nil
                      focusedHeader = nil
                      return [
                        MenuAction(title: "Copy Column") {
                          NSPasteboard.general.clearContents()
                          NSPasteboard.general.setString(
                            document.exportContent(for: header), forType: .string)
                        },
                        MenuAction(title: "Clear Column") {
                          document.clear(column: header)
                        },
                        MenuAction(title: "Delete Column") {
                          document.delete(column: header)
                          selection.columns = []
                        },
                      ]
                    }
                  }
                }
                .overlay(alignment: .trailing) {
                  ResizeHandle()
                    .onTapGesture(count: 2) {
                      columnWidths[header.id] = document.fitWidth(for: header)
                    }
                    .gesture(
                      DragGesture(coordinateSpace: .global)
                        .onChanged { value in
                          if dragStartWidths[header.id] == nil {
                            dragStartWidths[header.id] = columnWidth(for: header)
                          }
                          columnWidths[header.id] = max(
                            50, (dragStartWidths[header.id] ?? 50) + value.translation.width)
                        }
                        .onEnded { _ in dragStartWidths[header.id] = nil }
                    )
                }
                // Insertion line for the gap left of this column — or,
                // on the last column, also for the gap right of it.
                .overlay(alignment: .leading) {
                  if columnGap == header.columnIndex {
                    Rectangle().fill(Color.accentColor).frame(width: 2)
                  }
                }
                .overlay(alignment: .trailing) {
                  if header.columnIndex == document.headers.count - 1,
                    columnGap == document.headers.count
                  {
                    Rectangle().fill(Color.accentColor).frame(width: 2)
                  }
                }
                .onDrop(
                  of: [.text],
                  delegate: ColumnReorderDropDelegate(
                    headerID: header.id, columnWidth: columnWidth(for: header),
                    document: document,
                    draggedColumn: $draggedColumn, indicator: $columnDropIndicator))
              }
              Button {
                document.addColumn()
              } label: {
                Image(systemName: "plus")
                  .padding(.horizontal, 8)
                  .padding(.vertical, 6)
                  .frame(maxHeight: .infinity)
                  .background(
                    hoveringAddColumn
                      ? Color.accentColor.opacity(0.25)
                      : Color.white
                  )
                  .overlay(alignment: .trailing) { Divider() }
                  .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
              .focusEffectDisabled()
              .foregroundStyle(.secondary)
              .onHover { hoveringAddColumn = $0 }
              .help("Add column")
              // The strip right of the last header accepts column drags,
              // so the gap after the last column has a drop area right of
              // its line too.
              .onDrop(
                of: [.text],
                delegate: ColumnEndDropDelegate(
                  document: document,
                  draggedColumn: $draggedColumn, indicator: $columnDropIndicator))
            }
            .background(.white)
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }
          }
        }
        .frame(
          minWidth: geometry.size.width,
          minHeight: geometry.size.height,
          alignment: .topLeading
        )
      }
      // Anchor a coordinate space to the (non-scrolling) viewport so the
      // add-row "+" can measure its horizontal position against the window.
      .coordinateSpace(name: "viewport")
    }
    .onAppear {
      sizeAllColumnsToFit()
      // While editing a cell: Shift+Return inserts a line break (a plain
      // Return submits via onSubmit and moves down), Tab moves the edit
      // session to the cell on the right, Shift+Tab to the left.
      // While a cell is merely selected, Return starts editing it and the
      // arrow keys move the selection.
      keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        let returnKey: UInt16 = 36
        let tabKey: UInt16 = 48
        let leftArrow: UInt16 = 123
        let rightArrow: UInt16 = 124
        let downArrow: UInt16 = 125
        let upArrow: UInt16 = 126
        if selection.editingCell != nil {
          if event.keyCode == returnKey,
            event.modifierFlags.contains(.shift),
            let editor = NSApp.keyWindow?.firstResponder as? NSTextView
          {
            editor.insertNewlineIgnoringFieldEditor(nil)
            return nil
          }
          if event.keyCode == tabKey {
            moveEditing(
              rowDelta: 0,
              columnDelta: event.modifierFlags.contains(.shift) ? -1 : 1
            )
            return nil
          }
          return event
        }
        // Cmd+C/X/V act on the selected cell, rows, or columns; Cmd+Z and
        // Shift+Cmd+Z undo and redo. While editing, the field editor
        // handles them (returned above).
        if editingHeader == nil,
          event.modifierFlags.contains(.command),
          !event.modifierFlags.contains(.option),
          !event.modifierFlags.contains(.control),
          let key = event.charactersIgnoringModifiers
        {
          switch key {
          case "c": if copySelection() { return nil }
          case "x": if cutSelection() { return nil }
          case "v": if pasteSelection() { return nil }
          case "z", "Z":
            if event.modifierFlags.contains(.shift) {
              document.undoManager?.redo()
            } else {
              document.undoManager?.undo()
            }
            return nil
          default: break
          }
        }
        if let cell = selection.cell, editingHeader == nil {
          switch event.keyCode {
          case returnKey:
            selection.beginEditing(cell)
            DispatchQueue.main.async { focusedCell = cell }
          case leftArrow: moveSelection(rowDelta: 0, columnDelta: -1)
          case rightArrow: moveSelection(rowDelta: 0, columnDelta: 1)
          case downArrow: moveSelection(rowDelta: 1, columnDelta: 0)
          case upArrow: moveSelection(rowDelta: -1, columnDelta: 0)
          default: return event
          }
          return nil
        }
        return event
      }
    }
    .onDisappear {
      if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
      keyMonitor = nil
    }
    // Only size columns without a stored width so adding a column doesn't
    // discard manual resizes. A newly imported file gets fresh header IDs,
    // so all its columns are sized.
    .onChange(of: document.headers) {
      for header in document.headers where columnWidths[header.id] == nil {
        columnWidths[header.id] = document.fitWidth(for: header)
      }
    }
    // A new edit session is a new undo step, even for the same cell.
    .onChange(of: selection.editingCell) { document.breakUndoCoalescing() }
    .onChange(of: editingHeader) { document.breakUndoCoalescing() }
    .onChange(of: focusedCell) { oldValue, newValue in
      // Only end editing when the *editing* cell lost focus. Comparing
      // against the old value avoids killing a freshly started edit session
      // when the previous cell's defocus event arrives late.
      if selection.editingCell != nil && oldValue == selection.editingCell
        && newValue != selection.editingCell
      {
        selection.endEditing()
      }
    }
    .onChange(of: focusedHeader) { oldValue, newValue in
      if editingHeader != nil && oldValue == editingHeader && newValue != editingHeader {
        editingHeader = nil
      }
    }
  }
}

/// Animation for the reorder applied on drop.
private let moveAnimation: Animation = .easeOut(duration: 0.15)

/// The gap a hovering row drag would insert into: before the row when
/// the cursor is in its upper half, after it otherwise. Rendered via
/// `indicatedRowGap()` so both hover representations of one gap draw the
/// same insertion line.
struct RowDropIndicator: Equatable {
  let rowID: CSVRow.ID
  let insertAfter: Bool
}

/// The gap a hovering column drag would insert into: before the column
/// when the cursor is in its left half, after it otherwise. Rendered via
/// `indicatedColumnGap()` so both hover representations of one gap draw
/// the same insertion line.
struct ColumnDropIndicator: Equatable {
  let headerID: CSVHeader.ID
  let insertAfter: Bool
}

/// Shows an insertion indicator while a drag from the row-number column
/// hovers over rows; the actual move happens once, on drop.
private struct RowReorderDropDelegate: DropDelegate {
  let rowID: CSVRow.ID
  let rowHeight: CGFloat
  let document: CSVDocument
  @Binding var draggedRow: CSVRow.ID?
  @Binding var indicator: RowDropIndicator?

  /// Whether the cursor is in the lower half of the hovered row.
  private func insertAfter(_ info: DropInfo) -> Bool {
    info.location.y > rowHeight / 2
  }

  /// Source index of the dragged row and the index it would end up at
  /// for the hovered gap, or nil when no row drag is active.
  private func moveIndices(_ info: DropInfo) -> (from: Int, to: Int)? {
    guard let dragged = draggedRow,
      let from = document.rows.firstIndex(where: { $0.id == dragged }),
      let target = document.rows.firstIndex(where: { $0.id == rowID })
    else { return nil }
    var to = insertAfter(info) ? target + 1 : target
    if from < to { to -= 1 }
    return (from, to)
  }

  func validateDrop(info: DropInfo) -> Bool {
    draggedRow != nil
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    guard let (from, to) = moveIndices(info) else { return nil }
    // No line for gaps adjacent to the dragged row: dropping there
    // wouldn't move anything.
    indicator =
      from == to
      ? nil
      : RowDropIndicator(rowID: rowID, insertAfter: insertAfter(info))
    return DropProposal(operation: .move)
  }

  func dropExited(info: DropInfo) {
    if indicator?.rowID == rowID { indicator = nil }
  }

  func performDrop(info: DropInfo) -> Bool {
    defer {
      draggedRow = nil
      indicator = nil
    }
    guard let (from, to) = moveIndices(info), from != to else { return false }
    withAnimation(moveAnimation) { document.move(rowAt: from, to: to) }
    return true
  }
}

/// Shows an insertion indicator while a header drag hovers over headers;
/// the actual move happens once, on drop.
private struct ColumnReorderDropDelegate: DropDelegate {
  let headerID: CSVHeader.ID
  let columnWidth: CGFloat
  let document: CSVDocument
  @Binding var draggedColumn: CSVHeader.ID?
  @Binding var indicator: ColumnDropIndicator?

  /// Whether the cursor is in the right half of the hovered header.
  private func insertAfter(_ info: DropInfo) -> Bool {
    info.location.x > columnWidth / 2
  }

  /// Source index of the dragged column and the index it would end up
  /// at for the hovered gap, or nil when no column drag is active.
  private func moveIndices(_ info: DropInfo) -> (from: Int, to: Int)? {
    guard let dragged = draggedColumn,
      let from = document.headers.firstIndex(where: { $0.id == dragged }),
      let target = document.headers.firstIndex(where: { $0.id == headerID })
    else { return nil }
    var to = insertAfter(info) ? target + 1 : target
    if from < to { to -= 1 }
    return (from, to)
  }

  func validateDrop(info: DropInfo) -> Bool {
    draggedColumn != nil
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    guard let (from, to) = moveIndices(info) else { return nil }
    // No line for gaps adjacent to the dragged column: dropping there
    // wouldn't move anything.
    indicator =
      from == to
      ? nil
      : ColumnDropIndicator(headerID: headerID, insertAfter: insertAfter(info))
    return DropProposal(operation: .move)
  }

  func dropExited(info: DropInfo) {
    if indicator?.headerID == headerID { indicator = nil }
  }

  func performDrop(info: DropInfo) -> Bool {
    defer {
      draggedColumn = nil
      indicator = nil
    }
    guard let (from, to) = moveIndices(info), from != to else { return false }
    withAnimation(moveAnimation) { document.move(columnAt: from, to: to) }
    return true
  }
}

/// Drop target on the add-row strip: moves the dragged row to the end.
private struct RowEndDropDelegate: DropDelegate {
  let document: CSVDocument
  @Binding var draggedRow: CSVRow.ID?
  @Binding var indicator: RowDropIndicator?

  func validateDrop(info: DropInfo) -> Bool {
    draggedRow != nil
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    guard draggedRow != nil, let last = document.rows.last else { return nil }
    // No line when the dragged row already is the last row.
    indicator =
      last.id == draggedRow
      ? nil
      : RowDropIndicator(rowID: last.id, insertAfter: true)
    return DropProposal(operation: .move)
  }

  func dropExited(info: DropInfo) {
    if indicator == document.rows.last.map({ RowDropIndicator(rowID: $0.id, insertAfter: true) }) {
      indicator = nil
    }
  }

  func performDrop(info: DropInfo) -> Bool {
    defer {
      draggedRow = nil
      indicator = nil
    }
    guard let dragged = draggedRow,
      let from = document.rows.firstIndex(where: { $0.id == dragged })
    else { return false }
    withAnimation(moveAnimation) {
      document.move(rowAt: from, to: document.rows.count - 1)
    }
    return true
  }
}

/// Drop target on the add-column strip: moves the dragged column to the
/// end.
private struct ColumnEndDropDelegate: DropDelegate {
  let document: CSVDocument
  @Binding var draggedColumn: CSVHeader.ID?
  @Binding var indicator: ColumnDropIndicator?

  func validateDrop(info: DropInfo) -> Bool {
    draggedColumn != nil
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    guard draggedColumn != nil, let last = document.headers.last else { return nil }
    // No line when the dragged column already is the last column.
    indicator =
      last.id == draggedColumn
      ? nil
      : ColumnDropIndicator(headerID: last.id, insertAfter: true)
    return DropProposal(operation: .move)
  }

  func dropExited(info: DropInfo) {
    if indicator
      == document.headers.last.map({ ColumnDropIndicator(headerID: $0.id, insertAfter: true) })
    {
      indicator = nil
    }
  }

  func performDrop(info: DropInfo) -> Bool {
    defer {
      draggedColumn = nil
      indicator = nil
    }
    guard let dragged = draggedColumn,
      let from = document.headers.firstIndex(where: { $0.id == dragged })
    else { return false }
    withAnimation(moveAnimation) {
      document.move(columnAt: from, to: document.headers.count - 1)
    }
    return true
  }
}

/// A context menu entry shown by `RightClickMenu`.
private struct MenuAction {
  let title: String
  let action: () -> Void
}

/// Shows a context menu via AppKit instead of SwiftUI's `contextMenu`.
/// The callback runs on right mouse down (or Control-click) and updates
/// the selection; the menu only opens after SwiftUI has committed and
/// drawn that change, so the highlight is visible first.
private struct RightClickMenu: NSViewRepresentable {
  /// Updates the selection and returns the menu items to show.
  let onRightMouseDown: () -> [MenuAction]

  func makeNSView(context: Context) -> CatcherView {
    let view = CatcherView()
    view.onRightMouseDown = onRightMouseDown
    return view
  }

  func updateNSView(_ nsView: CatcherView, context: Context) {
    nsView.onRightMouseDown = onRightMouseDown
  }

  final class CatcherView: NSView {
    var onRightMouseDown: (() -> [MenuAction])?

    /// Only intercept right clicks and Control-clicks; every other event
    /// falls through to the SwiftUI content below.
    override func hitTest(_ point: NSPoint) -> NSView? {
      guard let event = NSApp.currentEvent else { return nil }
      let isRightClick = event.type == .rightMouseDown || event.type == .rightMouseUp
      let isControlClick =
        (event.type == .leftMouseDown || event.type == .leftMouseUp)
        && event.modifierFlags.contains(.control)
      return isRightClick || isControlClick ? super.hitTest(point) : nil
    }

    override func rightMouseDown(with event: NSEvent) {
      showMenu(for: event)
    }

    override func mouseDown(with event: NSEvent) {
      if event.modifierFlags.contains(.control) {
        showMenu(for: event)
      } else {
        super.mouseDown(with: event)
      }
    }

    private func showMenu(for event: NSEvent) {
      guard let actions = onRightMouseDown?() else { return }
      let menu = NSMenu()
      for action in actions {
        menu.addItem(ActionMenuItem(action))
      }
      // Two run loop hops so SwiftUI commits and Core Animation draws the
      // updated selection before the menu's tracking session blocks them.
      DispatchQueue.main.async {
        DispatchQueue.main.async {
          NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
      }
    }
  }

  final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ menuAction: MenuAction) {
      self.handler = menuAction.action
      super.init(title: menuAction.title, action: #selector(invoke), keyEquivalent: "")
      self.target = self
    }

    required init(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    @objc private func invoke() {
      handler()
    }
  }
}

private struct ResizeHandle: View {
  @State private var hovering = false

  var body: some View {
    Color.clear
      .frame(width: 8)
      .contentShape(Rectangle())
      .overlay(alignment: .trailing) { Divider() }
      .onHover { hovering = $0 }
      .onChange(of: hovering) {
        if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
      }
  }
}

#Preview {
  CSVTableView(document: CSVDocument.preview, wrapContent: .constant(false))
}
