import Foundation

// MARK: - String Extensions for Content Detection

public extension String {
    var isValidURL: Bool {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if it starts with common URL schemes
        let urlPrefixes = ["http://", "https://", "ftp://", "ftps://", "mailto:", "file://"]
        for prefix in urlPrefixes {
            if trimmed.lowercased().hasPrefix(prefix) {
                return URL(string: trimmed) != nil
            }
        }

        // Check for URLs without scheme (like google.com)
        if !trimmed.contains(" ") && trimmed.contains(".") {
            let withHTTPS = "https://" + trimmed
            if let url = URL(string: withHTTPS), url.host != nil {
                return true
            }
        }

        return false
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
}