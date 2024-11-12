import SwiftUI

@main
struct AirCSVApp: App {
  var body: some Scene {
    DocumentGroup(viewing: CSVViewModel.self) { configuration in
      ContentView(viewModel: configuration.document)
    }
  }
}
