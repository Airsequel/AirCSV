import SwiftUI

struct ContentView: View {

  @ObservedObject var document: CSVDocument
  /// The document's on-disk location, used to remember the window frame
  /// per document. Nil for a new, unsaved document.
  var fileURL: URL?
  @Environment(\.undoManager) private var undoManager
  @State private var wrapContent: Bool = true
  /// Keeps the window from being recentered while the file loads. See
  /// `WindowFramePin`. Starts armed only for a document that still has to
  /// load, and releases a beat after loading settles.
  @State private var framePinned = false

  var body: some View {
    CSVTableView(document: document, wrapContent: $wrapContent)
      .background(WindowFramePin(active: framePinned, documentURL: fileURL))
      .overlay {
        if document.isLoading {
          ProgressView("Loading…")
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
        }
      }
      .task { document.loadPendingContent() }
      .onAppear {
        document.undoManager = undoManager
        framePinned = document.isLoading
      }
      .onChange(of: document.isLoading) { _, loading in
        if loading {
          framePinned = true
        } else {
          // The stale-frame re-apply fires just after content commits;
          // hold the pin a moment longer so it's caught, then let the
          // user move freely.
          Task {
            try? await Task.sleep(for: .seconds(1))
            framePinned = false
          }
        }
      }
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
  ContentView(document: CSVDocument.preview, fileURL: nil)
}
