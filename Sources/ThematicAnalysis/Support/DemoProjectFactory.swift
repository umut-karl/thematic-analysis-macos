import Foundation

enum DemoProjectFactory {
    static func makeProject() -> AnalysisProject {
        let adoption = ThemeNode(name: "Adoption Experiences", parentID: nil, colorIndex: 0)
        let firstEncounters = ThemeNode(name: "First Encounters", parentID: adoption.id, colorIndex: 0)
        let initialCuriosity = ThemeNode(name: "Initial Curiosity", parentID: firstEncounters.id, colorIndex: 0)
        let earlyFriction = ThemeNode(name: "Early Friction", parentID: firstEncounters.id, colorIndex: 0)
        let workflowChanges = ThemeNode(name: "Workflow Changes", parentID: adoption.id, colorIndex: 0)
        let timeSavings = ThemeNode(name: "Time Savings", parentID: workflowChanges.id, colorIndex: 0)

        let trust = ThemeNode(name: "Trust and Evaluation", parentID: nil, colorIndex: 1)
        let verification = ThemeNode(name: "Verification Practices", parentID: trust.id, colorIndex: 1)
        let crossChecking = ThemeNode(name: "Cross-checking Output", parentID: verification.id, colorIndex: 1)
        let confidence = ThemeNode(name: "Confidence", parentID: trust.id, colorIndex: 1)
        let conditionalTrust = ThemeNode(name: "Conditional Trust", parentID: confidence.id, colorIndex: 1)

        let segments = [
            TranscriptSegment(order: 1, speaker: "Interviewer", start: "00:00", end: "00:06", text: "When did you first begin using an AI assistant at work?"),
            TranscriptSegment(order: 2, speaker: "Demo Participant", start: "00:06", end: "00:18", text: "I tried it out of curiosity when I had to summarize a long meeting transcript."),
            TranscriptSegment(order: 3, speaker: "Demo Participant", start: "00:18", end: "00:31", text: "The first result was useful, but it missed a decision that mattered to the team."),
            TranscriptSegment(order: 4, speaker: "Interviewer", start: "00:31", end: "00:37", text: "How did that change the way you use it?"),
            TranscriptSegment(order: 5, speaker: "Demo Participant", start: "00:37", end: "00:52", text: "Now I compare every summary with my notes and open the source whenever a claim looks uncertain."),
            TranscriptSegment(order: 6, speaker: "Demo Participant", start: "00:52", end: "01:04", text: "It still saves time because I begin with a draft instead of a blank page."),
            TranscriptSegment(order: 7, speaker: "Demo Participant", start: "01:04", end: "01:18", text: "I trust it for organizing material, but I do not let it make the final judgment for me."),
            TranscriptSegment(order: 8, speaker: "Interviewer", start: "01:18", end: "01:22", text: "Thank you. That is all for today.")
        ]

        let codingUnits = [
            CodingUnit(segmentIDs: [segments[1].id], themeIDs: [initialCuriosity.id], memo: "Curiosity prompted the participant's first trial."),
            CodingUnit(segmentIDs: [segments[2].id], themeIDs: [earlyFriction.id], memo: "A missed decision created early friction."),
            CodingUnit(segmentIDs: [segments[4].id], themeIDs: [crossChecking.id], memo: "The participant verifies summaries against primary material."),
            CodingUnit(segmentIDs: [segments[5].id], themeIDs: [timeSavings.id], memo: "Draft generation reduces the time needed to begin."),
            CodingUnit(segmentIDs: [segments[6].id], themeIDs: [conditionalTrust.id], memo: "Trust is limited to organization rather than final judgment.")
        ]

        let details = ParticipantDetails(
            occupation: "Project Coordinator",
            employmentStatus: "Full-time",
            sector: "Professional Services",
            experienceYears: "6",
            notes: "Synthetic participant created for the built-in demo."
        )
        let interview = Interview(
            name: "Demo Interview",
            participant: "Demo Participant",
            participantDetails: details,
            segments: segments,
            codingUnits: codingUnits
        )

        return AnalysisProject(
            name: "Demo — AI-Assisted Work",
            interviews: [interview],
            themes: [
                adoption, firstEncounters, initialCuriosity, earlyFriction,
                workflowChanges, timeSavings, trust, verification,
                crossChecking, confidence, conditionalTrust
            ]
        )
    }
}
