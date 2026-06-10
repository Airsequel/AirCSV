import SwiftUI

struct CellAddress: Hashable {
  let rowID: CSVRow.ID
  let headerID: CSVHeader.ID
}

struct CSVTableView: View {

  @ObservedObject var viewModel: CSVViewModel
  @Binding var wrapContent: Bool
  @State private var selectedRows: Set<CSVRow.ID> = []
  @State private var selectedColumns: Set<CSVHeader.ID> = []
  @State private var selectedCell: CellAddress?
  /// Extent of a shift+click range selection; `selectedCell` is the
  /// anchor. Nil while only a single cell is selected.
  @State private var selectionEnd: CellAddress?
  @State private var editingCell: CellAddress?
  @FocusState private var focusedCell: CellAddress?
  @State private var columnWidths: [UUID: CGFloat] = [:]
  @State private var dragStartWidths: [UUID: CGFloat] = [:]
  @State private var keyMonitor: Any?
  @State private var hoveringAddRow = false
  @State private var hoveringAddColumn = false
  @State private var editingHeader: CSVHeader.ID?
  @FocusState private var focusedHeader: CSVHeader.ID?

  func columnWidth(for header: CSVHeader) -> CGFloat {
    columnWidths[header.id] ?? viewModel.idealWidth(for: header)
  }

  /// Width of a data row: row number column plus all data columns.
  var tableWidth: CGFloat {
    viewModel.headers.reduce(viewModel.rowNumberColumnWidth) { $0 + columnWidth(for: $1) }
  }

  func sizeAllColumnsToFit() {
    for header in viewModel.headers {
      columnWidths[header.id] = viewModel.fitWidth(for: header)
    }
  }

  /// Move the edit session to the cell offset by the given deltas, or end
  /// editing when that would leave the table.
  func moveEditing(rowDelta: Int, columnDelta: Int) {
    guard let current = editingCell,
      let rowIndex = viewModel.rows.firstIndex(where: { $0.id == current.rowID }),
      let columnIndex = viewModel.headers.firstIndex(where: { $0.id == current.headerID })
    else { return }
    let targetRow = rowIndex + rowDelta
    let targetColumn = columnIndex + columnDelta
    guard viewModel.rows.indices.contains(targetRow),
      viewModel.headers.indices.contains(targetColumn)
    else {
      editingCell = nil
      focusedCell = nil
      return
    }
    let target = CellAddress(
      rowID: viewModel.rows[targetRow].id,
      headerID: viewModel.headers[targetColumn].id
    )
    editingCell = target
    selectedCell = target
    selectionEnd = nil
    DispatchQueue.main.async { focusedCell = target }
  }

  /// Move the selection to the cell offset by the given deltas, clamped to
  /// the table bounds.
  func moveSelection(rowDelta: Int, columnDelta: Int) {
    guard let current = selectedCell,
      let rowIndex = viewModel.rows.firstIndex(where: { $0.id == current.rowID }),
      let columnIndex = viewModel.headers.firstIndex(where: { $0.id == current.headerID })
    else { return }
    let targetRow = min(max(rowIndex + rowDelta, 0), viewModel.rows.count - 1)
    let targetColumn = min(max(columnIndex + columnDelta, 0), viewModel.headers.count - 1)
    selectedCell = CellAddress(
      rowID: viewModel.rows[targetRow].id,
      headerID: viewModel.headers[targetColumn].id
    )
    selectionEnd = nil
    selectedRows = []
    selectedColumns = []
  }

  /// Row and column index bounds of the cell selection rectangle spanned
  /// by the anchor cell and the shift+click extent, or nil when no cell
  /// is selected.
  func selectionRange() -> (rows: ClosedRange<Int>, columns: ClosedRange<Int>)? {
    guard let anchor = selectedCell,
      let anchorRow = viewModel.rows.firstIndex(where: { $0.id == anchor.rowID }),
      let anchorColumn = viewModel.headers.firstIndex(where: { $0.id == anchor.headerID })
    else { return nil }
    guard let end = selectionEnd,
      let endRow = viewModel.rows.firstIndex(where: { $0.id == end.rowID }),
      let endColumn = viewModel.headers.firstIndex(where: { $0.id == end.headerID })
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
        let cells = viewModel.rows[range.rows.lowerBound].cells
        content =
          cells.indices.contains(range.columns.lowerBound)
          ? cells[range.columns.lowerBound].content
          : ""
      } else {
        content = viewModel.copyContent(
          rowRange: range.rows, columnRange: range.columns)
      }
    } else if !selectedRows.isEmpty {
      content = viewModel.copyContent(rows: selectedRows)
    } else if !selectedColumns.isEmpty {
      content = viewModel.copyContent(columns: selectedColumns)
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
      viewModel.clear(rowRange: range.rows, columnRange: range.columns)
    } else if !selectedRows.isEmpty {
      viewModel.clear(rows: selectedRows)
    } else if !selectedColumns.isEmpty {
      viewModel.clear(columns: selectedColumns)
    }
    return true
  }

  /// Paste the pasteboard starting at the top-left selected cell, the
  /// first selected row, or the first selected column. Returns false when
  /// nothing is selected or the pasteboard has no text.
  func pasteSelection() -> Bool {
    guard let text = NSPasteboard.general.string(forType: .string) else { return false }
    if let range = selectionRange() {
      viewModel.paste(
        text, atRow: range.rows.lowerBound, column: range.columns.lowerBound)
    } else if let rowIndex = viewModel.rows.firstIndex(where: { selectedRows.contains($0.id) }) {
      viewModel.paste(text, atRow: rowIndex, column: 0)
    } else if let columnIndex = viewModel.headers.firstIndex(where: {
      selectedColumns.contains($0.id)
    }) {
      viewModel.paste(text, atRow: 0, column: columnIndex)
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

  var body: some View {
    // Computed once per render; cells check membership by index.
    let selection = selectionRange()
    GeometryReader { geometry in
      ScrollView([.horizontal, .vertical]) {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
          Section {
            ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
              HStack(spacing: 0) {
                Text("\(index + 1)")
                  .foregroundStyle(.secondary)
                  .font(.system(.body, design: .monospaced))
                  .padding(.horizontal, 8)
                  .padding(.vertical, 6)
                  .frame(width: viewModel.rowNumberColumnWidth, alignment: .trailing)
                  .frame(maxHeight: .infinity)
                  .background(Color(nsColor: .windowBackgroundColor))
                  .overlay(alignment: .trailing) { Divider() }
                  .contentShape(Rectangle())
                  .onTapGesture {
                    selectedRows = [row.id]
                    selectedColumns = []
                    selectedCell = nil
                    selectionEnd = nil
                    editingCell = nil
                    focusedCell = nil
                  }
                  .overlay(
                    RightClickMenu {
                      selectedRows = [row.id]
                      selectedColumns = []
                      selectedCell = nil
                      selectionEnd = nil
                      editingCell = nil
                      focusedCell = nil
                      return [
                        MenuAction(title: "Copy Row") {
                          NSPasteboard.general.clearContents()
                          NSPasteboard.general.setString(
                            viewModel.exportContent(for: row), forType: .string)
                        },
                        MenuAction(title: "Clear Row") {
                          viewModel.clear(row: row, selection: [row.id])
                        },
                        MenuAction(title: "Delete Row") {
                          viewModel.delete(row: row, selection: [row.id])
                        },
                      ]
                    }
                  )
                ForEach(viewModel.headers) { header in
                  let address = CellAddress(rowID: row.id, headerID: header.id)
                  Group {
                    if editingCell == address {
                      TextField(
                        "", text: viewModel.cellBinding(for: row, header: header),
                        axis: .vertical
                      )
                      .textFieldStyle(.plain)
                      .focused($focusedCell, equals: address)
                      .onSubmit { moveEditing(rowDelta: 1, columnDelta: 0) }
                      .onExitCommand { editingCell = nil }
                    } else {
                      Text(viewModel.cellBinding(for: row, header: header).wrappedValue)
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
                    selection.map {
                      $0.rows.contains(index) && $0.columns.contains(header.columnIndex)
                    } == true
                      ? Color.accentColor.opacity(0.25)
                      : selectedColumns.contains(header.id)
                        ? Color.accentColor.opacity(0.15)
                        : Color.clear
                  )
                  .overlay(alignment: .trailing) { Divider() }
                  .contentShape(Rectangle())
                  .simultaneousGesture(
                    TapGesture().onEnded {
                      // Shift+click extends the selection from the anchor
                      // cell into a rectangular range.
                      if let event = NSApp.currentEvent,
                        event.modifierFlags.contains(.shift),
                        selectedCell != nil,
                        editingCell != address
                      {
                        selectionEnd = address
                        selectedRows = []
                        selectedColumns = []
                        editingCell = nil
                        focusedCell = nil
                        return
                      }
                      selectedCell = address
                      selectionEnd = nil
                      selectedRows = []
                      selectedColumns = []
                      // Clicks inside the cell's own active editor (cursor
                      // placement, word selection) are the editor's business.
                      guard editingCell != address else { return }
                      // Detect double clicks via the AppKit event instead of
                      // TapGesture(count: 2): the recognizer's click counter
                      // resets when the first click ends another cell's edit
                      // session and the view tree rebuilds.
                      if let event = NSApp.currentEvent, event.clickCount >= 2 {
                        editingCell = address
                        let clickLocation = event.locationInWindow
                        DispatchQueue.main.async {
                          focusedCell = address
                          DispatchQueue.main.async { placeCursor(at: clickLocation) }
                        }
                      } else {
                        // Single click on another cell ends any active edit
                        // session. Done here explicitly because the field
                        // editor keeps first responder when a gesture-only
                        // view is clicked, so no focus change would fire.
                        editingCell = nil
                        focusedCell = nil
                      }
                    }
                  )
                  .overlay {
                    // No catcher while editing, so the field editor keeps
                    // its own clicks and text context menu.
                    if editingCell != address {
                      RightClickMenu {
                        selectedCell = address
                        selectionEnd = nil
                        selectedRows = []
                        selectedColumns = []
                        editingCell = nil
                        focusedCell = nil
                        let content =
                          viewModel.cellBinding(for: row, header: header).wrappedValue
                        var actions = [
                          MenuAction(title: "Copy Cell") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(content, forType: .string)
                          },
                          MenuAction(title: "Clear Cell") {
                            viewModel.cellBinding(for: row, header: header).wrappedValue = ""
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
                selectedRows.contains(row.id)
                  ? Color.accentColor.opacity(0.15)
                  : Color(
                    NSColor.alternatingContentBackgroundColors[index.isMultiple(of: 2) ? 0 : 1])
              )
              .overlay(alignment: .bottom) { Divider() }
              .contentShape(Rectangle())
            }
            Button {
              viewModel.addRow()
            } label: {
              Image(systemName: "plus")
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(width: tableWidth)
                .background(
                  hoveringAddRow
                    ? Color.accentColor.opacity(0.25)
                    : Color.white
                )
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
          } header: {
            HStack(spacing: 0) {
              Text("#")
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(width: viewModel.rowNumberColumnWidth, alignment: .trailing)
                .background(Color(nsColor: .windowBackgroundColor))
                .overlay(alignment: .trailing) { Divider() }
              ForEach(viewModel.headers) { header in
                Group {
                  if editingHeader == header.id {
                    TextField("", text: viewModel.headerBinding(for: header))
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
                  selectedColumns.contains(header.id)
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
                      selectedColumns = [header.id]
                      selectedRows = []
                      selectedCell = nil
                      selectionEnd = nil
                      editingCell = nil
                      focusedCell = nil
                    }
                  }
                )
                .overlay {
                  // No catcher while renaming, so the field editor keeps
                  // its own clicks and text context menu.
                  if editingHeader != header.id {
                    RightClickMenu {
                      selectedColumns = [header.id]
                      selectedRows = []
                      selectedCell = nil
                      selectionEnd = nil
                      editingCell = nil
                      focusedCell = nil
                      editingHeader = nil
                      focusedHeader = nil
                      return [
                        MenuAction(title: "Copy Column") {
                          NSPasteboard.general.clearContents()
                          NSPasteboard.general.setString(
                            viewModel.exportContent(for: header), forType: .string)
                        },
                        MenuAction(title: "Clear Column") {
                          viewModel.clear(column: header)
                        },
                        MenuAction(title: "Delete Column") {
                          viewModel.delete(column: header)
                          selectedColumns = []
                        },
                      ]
                    }
                  }
                }
                .overlay(alignment: .trailing) {
                    ResizeHandle()
                      .onTapGesture(count: 2) {
                        columnWidths[header.id] = viewModel.fitWidth(for: header)
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
              }
              Button {
                viewModel.addColumn()
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
        if editingCell != nil {
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
              viewModel.undoManager?.redo()
            } else {
              viewModel.undoManager?.undo()
            }
            return nil
          default: break
          }
        }
        if let cell = selectedCell, editingHeader == nil {
          switch event.keyCode {
          case returnKey:
            editingCell = cell
            selectionEnd = nil
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
    .onChange(of: viewModel.headers) {
      for header in viewModel.headers where columnWidths[header.id] == nil {
        columnWidths[header.id] = viewModel.fitWidth(for: header)
      }
    }
    // A new edit session is a new undo step, even for the same cell.
    .onChange(of: editingCell) { viewModel.breakUndoCoalescing() }
    .onChange(of: editingHeader) { viewModel.breakUndoCoalescing() }
    .onChange(of: focusedCell) { oldValue, newValue in
      // Only end editing when the *editing* cell lost focus. Comparing
      // against the old value avoids killing a freshly started edit session
      // when the previous cell's defocus event arrives late.
      if editingCell != nil && oldValue == editingCell && newValue != editingCell {
        editingCell = nil
      }
    }
    .onChange(of: focusedHeader) { oldValue, newValue in
      if editingHeader != nil && oldValue == editingHeader && newValue != editingHeader {
        editingHeader = nil
      }
    }
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
  CSVTableView(viewModel: CSVViewModel.preview, wrapContent: .constant(false))
}
