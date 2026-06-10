import SwiftUI

#if USE_NATIVE_TABLE

  struct CSVTableView: View {

    @ObservedObject var viewModel: CSVViewModel
    @Binding var wrapContent: Bool
    @State private var selection: Set<CSVRow.ID> = []

    var body: some View {
      Table(
        of: CSVRow.self,
        selection: $selection,
        columnCustomization: $viewModel.tableCustomization
      ) {
        TableColumn("#") { row in
          Text("\(viewModel.rowNumber(for: row))")
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .width(viewModel.rowNumberColumnWidth)

        TableColumnForEach(viewModel.headers) { header in
          TableColumn(header.name) { row in
            TextField("", text: viewModel.cellBinding(for: row, header: header), axis: .vertical)
              .textFieldStyle(.plain)
              .lineLimit(wrapContent ? nil : 1)
              .truncationMode(.tail)
              .font(.system(.body, design: .monospaced))
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
          }
          .width(min: 50, ideal: viewModel.idealWidth(for: header))
          .customizationID(header.id.uuidString)
        }
      } rows: {
        ForEach(viewModel.rows) { row in
          TableRow(row)
            .contextMenu {
              Button("Delete") {
                withAnimation(.bouncy(duration: 2)) {
                  viewModel.delete(row: row, selection: selection)
                }
              }
            }
        }
      }
      .id(wrapContent)
    }
  }

#else

  struct CellAddress: Hashable {
    let rowID: CSVRow.ID
    let headerID: CSVHeader.ID
  }

  struct CSVTableView: View {

    @ObservedObject var viewModel: CSVViewModel
    @Binding var wrapContent: Bool
    @State private var selectedRows: Set<CSVRow.ID> = []
    @State private var selectedCell: CellAddress?
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
      selectedRows = []
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
                      selectedCell = nil
                      editingCell = nil
                      focusedCell = nil
                    }
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
                      selectedCell == address ? Color.accentColor.opacity(0.25) : Color.clear
                    )
                    .overlay(alignment: .trailing) { Divider() }
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                      TapGesture().onEnded {
                        selectedCell = address
                        selectedRows = []
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
                .contextMenu {
                  Button("Delete") {
                    withAnimation(.bouncy(duration: 2)) {
                      viewModel.delete(row: row, selection: selectedRows)
                    }
                  }
                }
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
                      }
                    }
                  )
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
        // While a cell is merely selected, the arrow keys move the selection.
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
          if selectedCell != nil && editingHeader == nil {
            switch event.keyCode {
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

#endif

#Preview {
  CSVTableView(viewModel: CSVViewModel.preview, wrapContent: .constant(false))
}
