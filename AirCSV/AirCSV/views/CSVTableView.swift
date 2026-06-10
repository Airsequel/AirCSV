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

    func columnWidth(for header: CSVHeader) -> CGFloat {
      columnWidths[header.id] ?? viewModel.idealWidth(for: header)
    }

    func sizeAllColumnsToFit() {
      for header in viewModel.headers {
        columnWidths[header.id] = viewModel.fitWidth(for: header)
      }
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
                        .onSubmit { editingCell = nil }
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
            } header: {
              HStack(spacing: 0) {
                Text("#")
                  .fontWeight(.semibold)
                  .padding(.horizontal, 8)
                  .padding(.vertical, 6)
                  .frame(width: viewModel.rowNumberColumnWidth, alignment: .trailing)
                  .overlay(alignment: .trailing) { Divider() }
                ForEach(viewModel.headers) { header in
                  Text(header.name)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(width: columnWidth(for: header), alignment: .leading)
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
      .onAppear { sizeAllColumnsToFit() }
      .onChange(of: viewModel.headers) { sizeAllColumnsToFit() }
      .onChange(of: focusedCell) { oldValue, newValue in
        // Only end editing when the *editing* cell lost focus. Comparing
        // against the old value avoids killing a freshly started edit session
        // when the previous cell's defocus event arrives late.
        if editingCell != nil && oldValue == editingCell && newValue != editingCell {
          editingCell = nil
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
