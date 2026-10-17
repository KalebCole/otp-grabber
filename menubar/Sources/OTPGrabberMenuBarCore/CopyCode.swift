import Foundation

public enum CopyCode {
    public static func validated(_ value: String) -> String? {
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (4...8).contains(code.utf8.count),
              code.utf8.contains(where: { (48...57).contains($0) }),
              code.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else {
            return nil
        }
        return code
    }
}
