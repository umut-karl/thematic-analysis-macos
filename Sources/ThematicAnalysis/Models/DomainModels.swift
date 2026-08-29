import Foundation
import SwiftUI

struct TranscriptSegment: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var order: Int
    var part: Int?
    var speaker: String
    var start: String
    var end: String
    var text: String
}

struct ThemeNode: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var parentID: UUID?
    var colorIndex: Int
    var note: String? = nil
}

struct CodingUnit: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var segmentIDs: [UUID]
    var themeIDs: Set<UUID>
    var memo: String
    var createdAt: Date = .now
}

struct ParticipantDetails: Codable, Hashable {
    var gender: String = ""
    var age: String = ""
    var education: String = ""
    var occupation: String = ""
    var employmentStatus: String = ""
    var sector: String = ""
    var experienceYears: String = ""
    var maritalStatus: String = ""
    var location: String = ""
    var notes: String = ""

    init(
        gender: String = "",
        age: String = "",
        education: String = "",
        occupation: String = "",
        employmentStatus: String = "",
        sector: String = "",
        experienceYears: String = "",
        maritalStatus: String = "",
        location: String = "",
        notes: String = ""
    ) {
        self.gender = gender
        self.age = age
        self.education = education
        self.occupation = occupation
        self.employmentStatus = employmentStatus
        self.sector = sector
        self.experienceYears = experienceYears
        self.maritalStatus = maritalStatus
        self.location = location
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case gender, age, education, occupation, employmentStatus, sector
        case experienceYears, maritalStatus, location, notes
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        gender = try values.decodeIfPresent(String.self, forKey: .gender) ?? ""
        age = try values.decodeIfPresent(String.self, forKey: .age) ?? ""
        education = try values.decodeIfPresent(String.self, forKey: .education) ?? ""
        occupation = try values.decodeIfPresent(String.self, forKey: .occupation) ?? ""
        employmentStatus = try values.decodeIfPresent(String.self, forKey: .employmentStatus) ?? ""
        sector = try values.decodeIfPresent(String.self, forKey: .sector) ?? ""
        experienceYears = try values.decodeIfPresent(String.self, forKey: .experienceYears) ?? ""
        maritalStatus = try values.decodeIfPresent(String.self, forKey: .maritalStatus) ?? ""
        location = try values.decodeIfPresent(String.self, forKey: .location) ?? ""
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}

struct Interview: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var participant: String
    var participantDetails: ParticipantDetails?
    var importedAt: Date = .now
    var segments: [TranscriptSegment]
    var codingUnits: [CodingUnit] = []
}

struct AnalysisProject: Codable {
    var name: String
    var interviews: [Interview]
    var themes: [ThemeNode]
    var updatedAt: Date = .now
}

enum WorkspaceSection: String, CaseIterable, Identifiable {
    case addParticipant = "Add Participant"
    case participants = "Participants"
    case transcript = "Transcript"
    case coding = "Coding"
    case coded = "Coded Excerpts"
    case overview = "All Interviews"
    case map = "Theme Map"
    case profile = "Dominance Profile"
    case frequency = "Content Analysis"
    case milesMatrix = "Miles–Huberman Matrix"
    case prevalence = "Participant Prevalence"
    case frameworkMatrix = "Framework Matrix"

    var id: String { rawValue }
    var localizedTitle: LocalizedStringKey { LocalizedStringKey(rawValue) }
    var symbol: String {
        switch self {
        case .addParticipant: "person.badge.plus"
        case .participants: "person.2"
        case .transcript: "tablecells"
        case .coding: "tag"
        case .coded: "line.3.horizontal.decrease.circle"
        case .overview: "person.3"
        case .map: "point.3.connected.trianglepath.dotted"
        case .profile: "chart.bar.xaxis"
        case .frequency: "chart.bar"
        case .milesMatrix: "square.grid.3x3"
        case .prevalence: "person.3.sequence"
        case .frameworkMatrix: "tablecells"
        }
    }

    static let indicatorSections: [WorkspaceSection] = [
        .profile,
        .frequency,
        .milesMatrix,
        .prevalence,
        .frameworkMatrix
    ]

    var analyticsModule: DebugLabModule? {
        switch self {
        case .profile: .profile
        case .frequency: .frequency
        case .milesMatrix: .milesMatrix
        case .prevalence: .prevalence
        case .frameworkMatrix: .frameworkMatrix
        default: nil
        }
    }

    var isIndicatorSection: Bool { Self.indicatorSections.contains(self) }
}
