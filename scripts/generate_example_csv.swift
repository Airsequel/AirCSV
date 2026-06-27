#!/usr/bin/env swift

// Generate a wide example CSV for testing AirCSV with large files.
//
// Usage: swift scripts/generate_example_csv.swift [OUTPUT] [ROWS]
//   OUTPUT  destination path (default: csvs/example-20k.csv)
//   ROWS    number of data rows (default: 20000)
//
// The output is deterministic (seeded), UTF-8, and includes accented
// values and a mix of column types (text, email, integer, date, boolean).

import Foundation

/// Seeded, dependency-free RNG (SplitMix64) so runs are reproducible.
struct SplitMix64: RandomNumberGenerator {
  private var state: UInt64
  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

let cities = [
  "Stuttgart", "Düsseldorf", "Cologne", "Hamburg", "Munich", "Berlin",
  "Frankfurt", "Leipzig", "Dresden", "Bremen", "Hannover", "Nuremberg",
  "Dortmund", "Essen",
]
let occupations = [
  "DevOps Engineer", "Sales Director", "UX Designer", "Product Manager",
  "Data Analyst", "Junior Developer", "Software Engineer", "CFO", "CTO",
  "Marketing Lead", "QA Engineer", "Project Manager", "Data Scientist",
  "Backend Developer", "Frontend Developer", "Site Reliability Engineer",
]
let departments = [
  "Engineering", "Sales", "Design", "Product", "Finance", "Marketing",
  "Operations", "Support", "Research", "People",
]
let countries = ["Germany", "Austria", "Switzerland", "Netherlands", "Denmark", "Sweden"]
let firstNames = [
  "Felix", "Henrik", "Emma", "Bob", "Carla", "Grace", "Alice", "David",
  "Sophie", "Liam", "Noah", "Mia", "Lucas", "Hannah", "Elias", "Marie",
  "Jonas", "Lena", "Paul", "Anna",
]
let lastNames = [
  "Bauer", "Larsen", "Wilson", "Smith", "Méndez", "Kim", "Johnson", "Lee",
  "Schmidt", "Müller", "Weber", "Fischer", "Wagner", "Becker", "Hoffmann",
  "Koch", "Richter", "Wolf",
]
let columns = [
  "Name", "Email", "Age", "City", "Country", "Occupation", "Department",
  "Salary", "Start Date", "Active",
]

/// Fold the accented characters used in the names for the email local part.
let asciiFold: [Character: Character] = [
  "ä": "a", "ö": "o", "ü": "u", "é": "e", "í": "i", "á": "a", "ñ": "n",
]
func foldAccents(_ string: String) -> String {
  String(string.map { asciiFold[$0] ?? $0 })
}

let arguments = CommandLine.arguments
let output = arguments.count > 1 ? arguments[1] : "csvs/example-20k.csv"
let rows = arguments.count > 2 ? (Int(arguments[2]) ?? 20000) : 20000

var rng = SplitMix64(seed: 42)
var csv = columns.joined(separator: ",") + "\n"
csv.reserveCapacity(rows * 80)

for i in 0..<rows {
  let first = firstNames.randomElement(using: &rng)!
  let last = lastNames.randomElement(using: &rng)!
  let name = "\(first) \(last)"
  let local = foldAccents("\(first).\(last)".lowercased())
  let email = "\(local)\(i)@example.com"
  let age = Int.random(in: 22...64, using: &rng)
  let city = cities.randomElement(using: &rng)!
  let country = countries.randomElement(using: &rng)!
  let occupation = occupations.randomElement(using: &rng)!
  let department = departments.randomElement(using: &rng)!
  let salary = Int.random(in: 40...180, using: &rng) * 1000
  let year = Int.random(in: 2012...2025, using: &rng)
  let month = Int.random(in: 1...12, using: &rng)
  let day = Int.random(in: 1...28, using: &rng)
  let date = String(format: "%04d-%02d-%02d", year, month, day)
  let active = Bool.random(using: &rng) ? "true" : "false"
  csv += "\(name),\(email),\(age),\(city),\(country),\(occupation),"
  csv += "\(department),\(salary),\(date),\(active)\n"
}

do {
  try csv.write(toFile: output, atomically: true, encoding: .utf8)
  print("Wrote \(rows) rows to \(output)")
} catch {
  FileHandle.standardError.write("Failed to write \(output): \(error)\n".data(using: .utf8)!)
  exit(1)
}
