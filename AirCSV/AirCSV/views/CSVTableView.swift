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

  struct CSVTableView: View {

    @ObservedObject var viewModel: CSVViewModel
    @Binding var wrapContent: Bool
    @State private var selectedRows: Set<CSVRow.ID> = []
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

    var body: some View {
      GeometryReader { geometry in
        ScrollView([.horizontal, .vertical]) {
          LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section {
              ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                HStack(spacing: 0) {
                  ForEach(viewModel.headers) { header in
                    Text(viewModel.cellBinding(for: row, header: header).wrappedValue)
                      .lineLimit(wrapContent ? nil : 1)
                      .truncationMode(.tail)
                      .font(.system(.body, design: .monospaced))
                      .padding(.horizontal, 8)
                      .padding(.vertical, 6)
                      .frame(width: columnWidth(for: header), alignment: .leading)
                      .overlay(alignment: .trailing) { Divider() }
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
                .onTapGesture { selectedRows = [row.id] }
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
