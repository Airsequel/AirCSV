import SwiftUI
import UniformTypeIdentifiers

struct CSVExportButton: View {

  @ObservedObject var document: CSVDocument
  @State private var isPresented: Bool = false

  var body: some View {
    Button {
      isPresented.toggle()
    } label: {
      Label("Export CSV", systemImage: "square.and.arrow.up")
    }
    .disabled(document.content.isEmpty)

    .fileExporter(
      isPresented: $isPresented,
      document: document,
      contentType: UTType.commaSeparatedText
    ) { result in
      print("result \(result)")
    }
  }
}

#Preview {
  CSVExportButton(document: CSVDocument.preview)
    .frame(width: 300, height: 100)
}
