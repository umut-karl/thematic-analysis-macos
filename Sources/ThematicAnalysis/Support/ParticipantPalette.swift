import SwiftUI

enum ParticipantPalette {
    private static let colors: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .indigo, .brown]

    static func color(_ index: Int) -> Color {
        colors[abs(index) % colors.count]
    }

    static func index(for interviewID: UUID, in interviews: [Interview]) -> Int {
        interviews.firstIndex(where: { $0.id == interviewID }) ?? 0
    }
}
