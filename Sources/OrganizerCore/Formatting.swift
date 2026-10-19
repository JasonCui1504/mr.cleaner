import Foundation

public enum Formatting {
    /// Unambiguous local date and time, e.g. "2026-03-14 09:26:53 PDT".
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss zzz"
        return formatter
    }()

    public static func date(_ date: Date?) -> String {
        guard let date else { return "Unavailable" }
        return dateFormatter.string(from: date)
    }

    public static func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    public static func sizeWithBytes(_ bytes: Int64) -> String {
        "\(size(bytes)) (\(bytes.formatted()) bytes)"
    }
}
