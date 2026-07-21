import SwiftUI

@main
struct AirCSVApp: App {
  var body: some Scene {
    DocumentGroup(viewing: CSVDocument.self) { configuration in
      ContentView(document: configuration.document, fileURL: configuration.fileURL)
    }
    .defaultSize(width: 1000, height: 660)
  }
}
