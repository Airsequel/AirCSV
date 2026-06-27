import SwiftUI

@main
struct AirCSVApp: App {
  var body: some Scene {
    DocumentGroup(viewing: CSVDocument.self) { configuration in
      ContentView(document: configuration.document)
    }
    .defaultSize(width: 1000, height: 660)
  }
}
