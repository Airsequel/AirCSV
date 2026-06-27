import SwiftUI
import UniformTypeIdentifiers

struct CSVImportButton: View {

  @ObservedObject var document: CSVDocument

  @State private var isPresented: Bool = false

  var body: some View {
    Button {
      isPresented.toggle()
    } label: {
      Label("Import CSV", systemImage: "square.and.arrow.down")
    }
    .fileImporter(
      isPresented: $isPresented,
      allowedContentTypes: [UTType.commaSeparatedText]
    ) { result in
      document.handleFileImport(for: result)
    }

  }
}

#Preview {
  CSVImportButton(document: CSVDocument())
}
