//
//  TutorialModels.swift
//  Noteworks
//
//  Mirrors NOTEWORKS_TUTORIAL_STEPS from others/NoteWorks_UI 5/noteworks-library.jsx.
//

import SwiftUI

enum TutorialTarget: String, Hashable {
    case homeFAB
    case homeBubble
    case libraryAddNote
    case libraryAddMenu
    case noteAIButton
    case aiGapOption
    case aiSmartOption
    case communityNewPost
    case communityComposer
    case profileAvatar
    case profileSettingsNav
}

enum TutorialAction: String {
    case homeFAB = "home-fab"
    case homeBubble = "home-bubble"
    case libraryAddNote = "library-add-note"
    case noteAI = "note-ai"
    case communityNewPost = "community-new-post"
    case profileAvatar = "profile-avatar"
}

enum TutorialScreen: String {
    case home
    case library
    case note
    case community
    case profile
}

enum TutorialCoachPlacement {
    case center
    case left
    case leftBottom
    case right
    case bottom
    case top
}

struct NoteWorksTutorialStep: Identifiable {
    let id: String
    let screen: TutorialScreen
    let kicker: String
    let title: String
    let body: String
    let placement: TutorialCoachPlacement
    let target: TutorialTarget?
    let action: TutorialAction?
    let cta: String?

    var usesManualAdvance: Bool { action == nil }
}

enum NoteWorksTutorialSteps {
    static let all: [NoteWorksTutorialStep] = [
        NoteWorksTutorialStep(
            id: "welcome",
            screen: .home,
            kicker: "Quick tour",
            title: "welcome to NoteWorks",
            body: "A short hands-on tour. Tap real controls to learn.",
            placement: .center,
            target: nil,
            action: nil,
            cta: "Start tour"
        ),
        NoteWorksTutorialStep(
            id: "home-create",
            screen: .home,
            kicker: "Create",
            title: "Create",
            body: "New Bubbles and Notes start here.",
            placement: .leftBottom,
            target: .homeFAB,
            action: nil,
            cta: "Next"
        ),
        NoteWorksTutorialStep(
            id: "home-bubbles",
            screen: .home,
            kicker: "Home",
            title: "Bubbles",
            body: "Each Bubble is one course space.",
            placement: .bottom,
            target: .homeBubble,
            action: nil,
            cta: "Next"
        ),
        NoteWorksTutorialStep(
            id: "library-add-note",
            screen: .library,
            kicker: "Library",
            title: "Add a note",
            body: "Tap the + card to create a note.",
            placement: .right,
            target: .libraryAddNote,
            action: nil,
            cta: "Next"
        ),
        NoteWorksTutorialStep(
            id: "library-add-menu",
            screen: .library,
            kicker: "Create note",
            title: "Blank or Import",
            body: "Blank starts empty. Import opens a local file.",
            placement: .right,
            target: .libraryAddMenu,
            action: nil,
            cta: "Next"
        ),
        NoteWorksTutorialStep(
            id: "ai",
            screen: .note,
            kicker: "AI Enhancements",
            title: "AI Enhancements",
            body: "Open the AI menu first.",
            placement: .left,
            target: .noteAIButton,
            action: nil,
            cta: "Next"
        ),
        NoteWorksTutorialStep(
            id: "ai-gap",
            screen: .note,
            kicker: "Gap Detection",
            title: "Gap Detection",
            body: "Compares your note with peer notes and class materials. You confirm Credits before it runs.",
            placement: .right,
            target: .aiGapOption,
            action: nil,
            cta: "Next"
        ),
        NoteWorksTutorialStep(
            id: "ai-smart",
            screen: .note,
            kicker: "Smart Organization",
            title: "Smart Organization",
            body: "Tidies structure after confirmation. You can minimize it while AI works.",
            placement: .right,
            target: .aiSmartOption,
            action: nil,
            cta: "Next"
        ),
        NoteWorksTutorialStep(
            id: "community-new-post",
            screen: .community,
            kicker: "Community",
            title: "New Post",
            body: "Tap this to ask or share notes.",
            placement: .right,
            target: .communityNewPost,
            action: nil,
            cta: "Next"
        ),
        NoteWorksTutorialStep(
            id: "community-composer",
            screen: .community,
            kicker: "Composer",
            title: "Create a post",
            body: "Add course, text, and attachments before posting.",
            placement: .left,
            target: .communityComposer,
            action: nil,
            cta: "Next"
        ),
        NoteWorksTutorialStep(
            id: "profile-entry",
            screen: .community,
            kicker: "Profile",
            title: "Open Profile",
            body: "Tap your avatar to open account settings.",
            placement: .left,
            target: .profileAvatar,
            action: nil,
            cta: "Next"
        ),
        NoteWorksTutorialStep(
            id: "profile",
            screen: .profile,
            kicker: "Profile",
            title: "Profile",
            body: "Courses, Credits, security, and Feedback.",
            placement: .bottom,
            target: .profileSettingsNav,
            action: nil,
            cta: "Finish"
        ),
    ]
}

struct TutorialAnchorKey: PreferenceKey {
    static var defaultValue: [TutorialTarget: CGRect] = [:]

    static func reduce(value: inout [TutorialTarget: CGRect], nextValue: () -> [TutorialTarget: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    func tutorialAnchor(_ target: TutorialTarget) -> some View {
        background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: TutorialAnchorKey.self,
                    value: [target: geo.frame(in: .global)]
                )
            }
        }
    }

    func tutorialHighlight(_ target: TutorialTarget, activeTarget: TutorialTarget?) -> some View {
        overlay {
            if activeTarget == target {
                TutorialHighlightBorder(target: target)
            }
        }
    }
}

enum TutorialTheme {
    static let accent = Color(red: 0x5E/255, green: 0xAD/255, blue: 0xD3/255)
    static let textPrimary = Color(red: 0x1C/255, green: 0x1C/255, blue: 0x1E/255)
    static let textSecondary = Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.58)
    static let highlightStrokeWidth: CGFloat = 3
    static let highlightGlowRadius: CGFloat = 12
}

extension TutorialTarget {
    enum SpotlightKind {
        case circle
        case capsule
        case roundedRect(cornerRadius: CGFloat)
    }

    var spotlightKind: SpotlightKind {
        switch self {
        case .homeFAB, .homeBubble:
            return .circle
        case .noteAIButton, .profileAvatar:
            return .capsule
        case .aiGapOption, .aiSmartOption:
            return .roundedRect(cornerRadius: 14)
        case .communityComposer:
            return .roundedRect(cornerRadius: 28)
        default:
            return .roundedRect(cornerRadius: 24)
        }
    }

    func spotlightCornerRadius(in rect: CGRect) -> CGFloat {
        switch spotlightKind {
        case .circle, .capsule:
            return min(rect.width, rect.height) / 2
        case .roundedRect(let cornerRadius):
            return cornerRadius
        }
    }
}

private struct TutorialHighlightBorder: View {
    let target: TutorialTarget

    var body: some View {
        highlightShape
            .shadow(color: TutorialTheme.accent.opacity(0.35), radius: TutorialTheme.highlightGlowRadius)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var highlightShape: some View {
        switch target.spotlightKind {
        case .circle:
            Circle()
                .strokeBorder(TutorialTheme.accent, lineWidth: TutorialTheme.highlightStrokeWidth)
        case .capsule:
            Capsule()
                .strokeBorder(TutorialTheme.accent, lineWidth: TutorialTheme.highlightStrokeWidth)
        case .roundedRect(let cornerRadius):
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(TutorialTheme.accent, lineWidth: TutorialTheme.highlightStrokeWidth)
        }
    }
}
