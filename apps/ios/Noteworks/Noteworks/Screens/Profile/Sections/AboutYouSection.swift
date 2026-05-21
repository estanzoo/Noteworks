//
//  AboutYouSection.swift
//  Noteworks
//
//  Mirrors the "about" case in renderDetail() from
//  others/NoteWorks_UI 4/noteworks-library.jsx L10678–L10771.
//

import SwiftUI

struct AboutYouSection: View {
    @ObservedObject var viewModel: ProfileViewModel
    @ObservedObject var schoolSearch: SchoolSearchService
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var notesStore: NotesStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProfileSectionHeader(
                eyebrow: "About You",
                title: "Bio and academic details",
                copy: "Edit the identity that shows up across shared notes, community posts, and collaboration spaces. Changes update the profile card only after you save."
            )

            VStack(spacing: 10) {
                ProfileAboutTextRow(
                    label: "Name",
                    value: viewModel.aboutDraft.name,
                    multiline: false
                ) {
                    viewModel.openProfileTextEditor(.name)
                }

                ProfileAboutTextRow(
                    label: "Bio",
                    value: viewModel.aboutDraft.bio,
                    multiline: true
                ) {
                    viewModel.openProfileTextEditor(.bio)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ProfileAboutMetaRow(
                        label: "School",
                        value: viewModel.aboutDraft.school,
                        onEdit: { viewModel.openSchoolEditor() }
                    )
                    ProfileAboutMetaRow(
                        label: "Major",
                        value: viewModel.aboutDraft.major,
                        onEdit: { viewModel.openProfileTextEditor(.major) }
                    )
                    ProfileAboutMetaRow(
                        label: "Grade",
                        value: viewModel.aboutDraft.grade,
                        onEdit: { viewModel.openGradeEditor() }
                    )
                }
                VStack(spacing: 10) {
                    ProfileAboutMetaRow(
                        label: "School",
                        value: viewModel.aboutDraft.school,
                        onEdit: { viewModel.openSchoolEditor() }
                    )
                    ProfileAboutMetaRow(
                        label: "Major",
                        value: viewModel.aboutDraft.major,
                        onEdit: { viewModel.openProfileTextEditor(.major) }
                    )
                    ProfileAboutMetaRow(
                        label: "Grade",
                        value: viewModel.aboutDraft.grade,
                        onEdit: { viewModel.openGradeEditor() }
                    )
                }
            }

            if viewModel.aboutSchoolNeedsSelection {
                Text("Please pick a school from the list.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ProfileTheme.negative)
            }

            courseListRow

            HStack(alignment: .center, spacing: 16) {
                Text(statusMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(viewModel.aboutSaved ? ProfileTheme.positive : ProfileTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                ProfilePrimaryButton(
                    title: "Save Changes",
                    enabled: viewModel.canSaveAbout
                ) {
                    Task { await viewModel.saveAbout(using: appState) }
                }
                .frame(maxWidth: 180)
            }
        }
    }

    private var courseListRow: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Course List")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ProfileTheme.textPrimary)

                Text(courseListSummary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ProfileTheme.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ProfileSecondaryButton(title: "Edit Course List", compact: true) {
                viewModel.openCourseEditor()
            }
        }
        .profileRowCard()
    }

    private var courseListSummary: String {
        let labels = notesStore.bubbleNames.filter {
            $0.caseInsensitiveCompare(NotesStore.initialGuestBubbleName) != .orderedSame
        }
        if labels.isEmpty {
            return "No courses yet. Add courses to generate Home bubbles."
        }
        return labels.joined(separator: " · ")
    }

    private var statusMessage: String {
        if viewModel.aboutSaved { return "Changes saved to your profile." }
        if viewModel.aboutSchoolNeedsSelection { return "Choose a school from the suggestions." }
        if viewModel.aboutHasChanges { return "You have unsaved profile changes." }
        return "No pending changes."
    }
}
