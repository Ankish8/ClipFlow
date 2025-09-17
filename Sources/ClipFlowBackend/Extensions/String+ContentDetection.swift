import Foundation

// MARK: - String Extensions for Content Detection

public extension String {
    var isValidURL: Bool {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)

        // Exclude file URLs as they should be handled as files
        if trimmed.hasPrefix("file://") || trimmed.hasPrefix("/") {
            return false
        }

        // Simple and reliable URL detection - prioritize common patterns
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            // Additional validation: can we create a URL from it?
            return URL(string: trimmed) != nil
        }

        // Check www. prefix
        if trimmed.hasPrefix("www.") {
            return URL(string: "https://" + trimmed) != nil
        }

        // For single line content, use NSDataDetector as fallback
        if !trimmed.contains("\n") {
            guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
                return false
            }

            if let match = detector.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: trimmed.utf16.count)) {
                return match.range.length == trimmed.utf16.count
            }
        }

        // For multi-line content, check if it's primarily URLs
        let lines = trimmed.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !lines.isEmpty else { return false }

        let urlLikeLines = lines.filter { line in
            let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleanLine.hasPrefix("http://") || cleanLine.hasPrefix("https://") || cleanLine.hasPrefix("www.")
        }

        return Double(urlLikeLines.count) / Double(lines.count) >= 0.5
    }

    var isValidEmail: Bool {
        let emailRegex = "^[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}$"
        let emailTest = NSPredicate(format:"SELF MATCHES[c] %@", emailRegex)
        return emailTest.evaluate(with: self)
    }

    var isValidPhoneNumber: Bool {
        let phoneRegex = "^[\\+]?[1-9]?[0-9]{7,15}$"
        let phoneTest = NSPredicate(format: "SELF MATCHES %@", phoneRegex)
        let cleanedPhone = self.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        return phoneTest.evaluate(with: cleanedPhone) && cleanedPhone.count >= 7
    }

    var isValidColor: Bool {
        // Use Macboard's proven regex approach for hex colors
        guard let regex = try? NSRegularExpression(pattern: "^#(?:[0-9a-fA-F]{2}){3,4}$") else { return false }
        let range = NSRange(location: 0, length: self.utf16.count)
        return regex.firstMatch(in: self, options: [], range: range) != nil
    }

    var isNum: Bool {
        return !isEmpty && rangeOfCharacter(from: CharacterSet.decimalDigits.inverted) == nil
    }
}