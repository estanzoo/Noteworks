//
//  TutorialCoordinator.swift
//  Noteworks
//
//  State machine for the post-onboarding product tour (NoteWorks_UI 5).
//

import Foundation
import SwiftUI

@MainActor
final class TutorialCoordinator: ObservableObject {

    private static let completedKey = "noteworks.tutorial.completed"

    @Published var isActive = false
    @Published var stepIndex = 0
    @Published var showSkipConfirm = false
    @Published var showComplete = false

    /// One-shot: set by onboarding course setup before entering MainTabView.
    @Published var pendingAutoStart = false

    /// Note editor presented during AI tutorial steps.
    @Published var tutorialNoteId: String?

    /// Community post composer presented during the composer tutorial step.
    @Published private(set) var tutorialCommunityComposerOpen = false

    /// AI Enhancements dropdown open during ai-gap / ai-smart tutorial steps.
    @Published private(set) var tutorialAIPanelOpen = false

    var steps: [NoteWorksTutorialStep] { NoteWorksTutorialSteps.all }

    var currentStep: NoteWorksTutorialStep? {
        guard isActive, stepIndex >= 0, stepIndex < steps.count else { return nil }
        return steps[stepIndex]
    }

    var currentStepId: String? { currentStep?.id }

    var activeTarget: TutorialTarget? { currentStep?.target }

    var isFirstStep: Bool { stepIndex == 0 }
    var isLastStep: Bool { stepIndex >= steps.count - 1 }

    var hasCompletedTutorial: Bool {
        UserDefaults.standard.bool(forKey: Self.completedKey)
    }

    func consumePendingAutoStartIfNeeded() {
        guard pendingAutoStart, !hasCompletedTutorial else {
            pendingAutoStart = false
            return
        }
        pendingAutoStart = false
        startTutorial()
    }

    func startTutorial() {
        showComplete = false
        showSkipConfirm = false
        stepIndex = 0
        isActive = true
        refreshDerivedState()
    }

    func restartTutorial() {
        tutorialNoteId = nil
        startTutorial()
    }

    func goToNextStep() {
        stepIndex = min(stepIndex + 1, steps.count - 1)
        refreshDerivedState()
    }

    func goToPreviousStep() {
        let leavingComposer = currentStepId == "community-composer"
        stepIndex = max(stepIndex - 1, 0)
        if leavingComposer {
            tutorialCommunityComposerOpen = false
        }
        refreshDerivedState()
    }

    func requestSkip() {
        showSkipConfirm = true
    }

    func confirmSkip() {
        showSkipConfirm = false
        closeTutorial(showWelcome: true)
    }

    func finishTutorial() {
        closeTutorial(showWelcome: true)
    }

    func dismissCompleteScreen() {
        showComplete = false
        markCompleted()
    }

    /// Returns true when the tap should also run the underlying control action.
    @discardableResult
    func handleAction(_ action: TutorialAction, advanceImmediately: Bool = false) -> Bool {
        guard isActive, !showSkipConfirm else { return false }
        guard let step = currentStep, step.action == action else { return false }
        let advance: () -> Void = { [weak self] in
            self?.goToNextStep()
        }
        if advanceImmediately {
            advance()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: advance)
        }
        return true
    }

    /// Creates (or reuses) the note used during AI tutorial steps.
    func ensureTutorialNote(in store: NotesStore, forceNew: Bool = false) -> String {
        if !forceNew,
           let existingId = tutorialNoteId,
           store.note(id: existingId) != nil {
            return existingId
        }
        let note = store.createDraftNote()
        tutorialNoteId = note.id
        return note.id
    }

    func primaryButtonTapped() {
        guard let step = currentStep else { return }
        if isLastStep {
            finishTutorial()
        } else {
            goToNextStep()
        }
    }

    private func closeTutorial(showWelcome: Bool) {
        isActive = false
        stepIndex = 0
        tutorialNoteId = nil
        tutorialCommunityComposerOpen = false
        tutorialAIPanelOpen = false
        if showWelcome {
            showComplete = true
        } else {
            markCompleted()
        }
    }

    private func refreshDerivedState() {
        tutorialCommunityComposerOpen = currentStepId == "community-composer"
        tutorialAIPanelOpen = currentStepId == "ai-gap" || currentStepId == "ai-smart"
    }

    private func markCompleted() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
    }

    func displayTitle(firstName: String) -> String {
        guard let step = currentStep else { return "" }
        if step.id == "welcome", !firstName.isEmpty {
            return "\(firstName), \(step.title)"
        }
        return step.title
    }

    func firstName(from profile: UserProfile?) -> String {
        let raw = profile?.displayName ?? profile?.name ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.split(separator: " ").first.map(String.init) ?? trimmed
    }
}
