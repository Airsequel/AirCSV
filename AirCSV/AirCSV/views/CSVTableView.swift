import SwiftUI

struct CSVTableView: View {

  @ObservedObject var viewModel: CSVViewModel
  @State private var selection: Set<CSVRow.ID> = []

  var body: some View {
    Table(
      of: CSVRow.self,
      selection: $selection,
      columnCustomization: $viewModel.tableCustomization
    ) {
      TableColumnForEach(viewModel.headers) { header in
        TableColumn(header.name) { row in
          TextField(
            "Cell",
            text: viewModel.cellBinding(for: row, header: header)
          )
          .font(.system(.body, design: .monospaced))
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

                viewModel.delete(
                  row: row,
                  selection: selection)
              }
            }
          }
      }
    }
  }
}

#Preview {
  CSVTableView(viewModel: CSVViewModel.preview)
}
