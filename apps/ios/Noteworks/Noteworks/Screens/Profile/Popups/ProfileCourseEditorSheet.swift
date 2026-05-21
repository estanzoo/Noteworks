//
//  ProfileCourseEditorSheet.swift
//  Noteworks
//
//  Full-screen course editor launched from Profile → About You.
//  Reuses `CoursesStepView` in profile-edit presentation mode.
//

import SwiftUI

struct ProfileCourseEditorSheet: View {
    @ObservedObject var viewModel: ProfileViewModel
    @EnvironmentObject private var notesStore: NotesStore
    @StateObject private var onboardingData = OnboardingData()

    var body: some View {
        ZStack {
            OnboardingBackground()
                .ignoresSafeArea()

            CoursesStepView(
                data: onboardingData,
                presentation: .profileEdit,
                initialBubbleLabels: seededBubbleLabels,
                onSave: { labels in
                    notesStore.replaceBubbleNames(labels)
                    viewModel.closeCourseEditor()
                },
                onSkip: { viewModel.closeCourseEditor() },
                onBack: { viewModel.closeCourseEditor() },
                onClose: { viewModel.closeCourseEditor() }
            )
        }
        .onAppear {
            onboardingData.name = viewModel.profile.name
        }
    }

    private var seededBubbleLabels: [String] {
        notesStore.bubbleNames.filter {
            $0.caseInsensitiveCompare(NotesStore.initialGuestBubbleName) != .orderedSame
        }
    }
}
