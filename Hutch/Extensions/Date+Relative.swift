import Foundation

extension Date {
    /// A short relative description like "2h ago", "3d ago", or "Jan 5, 2025".
    var relativeDescription: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: .now)
    }
}
