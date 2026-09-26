import Foundation

// A GUI app's PATH does not include Homebrew, so tools are looked up in fixed locations.
enum Executables {
    private static let searchDirectories = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]

    static func locate(_ program: String) -> String? {
        searchDirectories
            .map { "\($0)/\(program)" }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
