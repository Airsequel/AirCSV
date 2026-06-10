import SwiftCSV
import SwiftUI

class CSVViewModel: ObservableObject {

  @Published var url: URL?
  @Published var content: String = ""
  @Published var headers: [CSVHeader] = []
  @Published var rows: [CSVRow] = []
  @Published var tableCustomization: TableColumnCustomization<CSVRow> = .init()

  init() {

  }

  required init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw CocoaError(.fileReadCorruptFile)
    }

    guard let fileContent = String(data: data, encoding: .utf8) else { return }
    self.content = fileContent
    parseCSV(content: fileContent)
  }

  func handleFileImport(for result: Result<URL, Error>) {
    switch result {
    case .success(let url):
      readFile(url)
    case .failure(let error): print("error loading file \(error)")
    }
  }

  func readFile(_ url: URL) {
    guard url.startAccessingSecurityScopedResource() else { return }
    self.url = url

    do {
      let content = try String(contentsOf: url, encoding: .utf8)
      self.content = content
      parseCSV(content: content)
    } catch {
      print(error)
    }

    url.stopAccessingSecurityScopedResource()
  }

  func parseCSV(content: String) {
    do {
      let data = try EnumeratedCSV(string: content, loadColumns: false)

      self.headers = CSVHeader.createHeaders(data: data.header)
      self.rows = data.rows.map({ CSVRow(cells: $0.map({ CSVCell(content: $0) })) })

    } catch {
      print(error)
    }
  }

  //MARK: - Layout

  func idealWidth(for header: CSVHeader) -> CGFloat {
    let headerLength = header.name.count
    let maxCellLength =
      rows.compactMap { row in
        row.cells.count > header.columnIndex ? row.cells[header.columnIndex].content.count : nil
      }.max() ?? 0
    let maxLength = max(headerLength, maxCellLength)
    return min(400, max(50, CGFloat(maxLength) * 8.5 + 24))
  }

  /// Minimum width that shows all content of the column, without the cap
  /// applied by `idealWidth(for:)`. Measures the rendered text widths.
  func fitWidth(for header: CSVHeader) -> CGFloat {
    let cellFont = NSFont.monospacedSystemFont(
      ofSize: NSFont.systemFontSize, weight: .regular)
    let headerFont = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)

    let headerWidth = (header.name as NSString)
      .size(withAttributes: [.font: headerFont]).width
    let maxCellWidth =
      rows.compactMap { row -> CGFloat? in
        guard row.cells.count > header.columnIndex else { return nil }
        return (row.cells[header.columnIndex].content as NSString)
          .size(withAttributes: [.font: cellFont]).width
      }.max() ?? 0

    let horizontalPadding: CGFloat = 16
    return max(50, ceil(max(headerWidth, maxCellWidth)) + horizontalPadding)
  }

  //MARK: - Edit

  func delete(row: CSVRow, selection: Set<CSVRow.ID>) {
    if selection.contains(row.id) {
      self.rows.removeAll { selection.contains($0.id) }
    } else {
      self.rows.removeAll(where: { $0.id == row.id })
    }
  }

  func cellBinding(for row: CSVRow, header: CSVHeader) -> Binding<String> {
    Binding {
      if let r = self.rows.first(where: { $0.id == row.id }),
        r.cells.count > header.columnIndex
      {
        return r.cells[header.columnIndex].content
      }
      return ""
    } set: { newValue in
      if let rowIndex = self.rows.firstIndex(where: { $0.id == row.id }) {
        self.rows[rowIndex].cells[header.columnIndex].content = newValue
      }
    }
  }

  //MARK: - Preview

  static var preview: CSVViewModel {
    let vm = CSVViewModel()
    vm.content = sampleCSV
    vm.parseCSV(content: sampleCSV)
    return vm
  }

  static var sampleCSV: String {
    """
    Keyword,Search volume
    swiftui components list,10
    swiftui list not showing,20
    swiftui uitableview,20
    swift tab view,20
    ios tabview,20
    table view swiftui,20
    table swiftui,20
    swift listview,30
    swift list view,30
    swiftui list example,30
    tabitem swiftui,30
    tableview swiftui,40
    tab bar swiftui,50
    swift ui table view,50
    swiftui table view,50
    """
  }
}
