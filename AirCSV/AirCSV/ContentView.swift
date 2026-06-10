import SwiftUI

struct ContentView: View {

  @ObservedObject var viewModel: CSVViewModel
  @State private var wrapContent: Bool = false

  var body: some View {
    CSVTableView(viewModel: viewModel, wrapContent: $wrapContent)
      .toolbar {
        CSVImportButton(viewModel: viewModel)
        CSVExportButton(viewModel: viewModel)
        Button {
          wrapContent.toggle()
        } label: {
          Label(
            wrapContent ? "Clip Content" : "Wrap Content",
            systemImage: wrapContent ? "scissors" : "arrow.turn.down.left"
          )
        }
      }
  }
}

#Preview {
  ContentView(viewModel: CSVViewModel.preview)
}
