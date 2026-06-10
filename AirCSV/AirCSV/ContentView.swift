import SwiftUI

struct ContentView: View {

  @ObservedObject var viewModel: CSVViewModel
  @State private var wrapContent: Bool = true

  var body: some View {
    CSVTableView(viewModel: viewModel, wrapContent: $wrapContent)
      .toolbar {
        CSVImportButton(viewModel: viewModel)
          .labelStyle(.titleAndIcon)
        CSVExportButton(viewModel: viewModel)
          .labelStyle(.titleAndIcon)
        Button {
          wrapContent.toggle()
        } label: {
          Label(
            wrapContent ? "Clip Content" : "Wrap Content",
            systemImage: wrapContent ? "arrow.right.to.line" : "arrow.turn.down.left"
          )
        }
        .labelStyle(.titleAndIcon)
      }
  }
}

#Preview {
  ContentView(viewModel: CSVViewModel.preview)
}
