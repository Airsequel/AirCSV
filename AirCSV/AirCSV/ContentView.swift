import SwiftUI

struct ContentView: View {

  @ObservedObject var document: CSVDocument
  @Environment(\.undoManager) private var undoManager
  @State private var wrapContent: Bool = true

  var body: some View {
    CSVTableView(document: document, wrapContent: $wrapContent)
      .onAppear { document.undoManager = undoManager }
      .onChange(of: undoManager) { document.undoManager = undoManager }
      .toolbar {
        CSVImportButton(document: document)
          .labelStyle(.titleAndIcon)
        CSVExportButton(document: document)
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
  ContentView(document: CSVDocument.preview)
}
