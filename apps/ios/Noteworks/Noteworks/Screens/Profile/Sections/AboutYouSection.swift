//
//  AboutYouSection.swift
//  Noteworks
//
//  Mirrors the "about" case in renderDetail() from
//  others/noteworks-library(2).jsx L5996–L6022.
//

import SwiftUI

struct AboutYouSection: View {
    @ObservedObject var viewModel: ProfileViewModel
    @ObservedObject var schoolSearch: SchoolSearchService
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProfileSectionHeader(
                eyebrow: "About You",
                title: "Bio and academic details",
                copy: "Edit the identity that shows up across shared notes, community posts, and collaboration spaces. Changes update the profile card only after you save."
            )

            ProfileField(
                label: "Name",
                value: Binding(
                    get: { viewModel.aboutDraft.name },
                    set: { viewModel.aboutDraft.name = $0; viewModel.aboutSaved = false }
                ),
                placeholder: "Your display name"
            )

            ProfileField(
                label: "Bio",
                value: Binding(
                    get: { viewModel.aboutDraft.bio },
                    set: { viewModel.aboutDraft.bio = $0; viewModel.aboutSaved = false }
                ),
                placeholder: "Tell classmates what you're focused on this semester...",
                multiline: true
            )

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    schoolField
                    majorField
                    gradeField
                }
                VStack(alignment: .leading, spacing: 14) {
                    schoolField
                    majorField
                    gradeField
                }
            }

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
        .onAppear {
            if let token = appState.accessToken {
                schoolSearch.prefetchAll(accessToken: token)
            }
        }
        .onChange(of: appState.accessToken) { _, token in
            schoolSearch.prefetchAll(accessToken: token)
        }
    }

    private var schoolField: some View {
        VStack(alignment: .leading, spacing: 8) {
            SchoolAutocompleteField(
                schoolName: Binding(
                    get: { viewModel.aboutDraft.school },
                    set: {
                        viewModel.aboutDraft.school = $0
                        viewModel.aboutSaved = false
                    }
                ),
                selectedSchoolId: Binding(
                    get: { viewModel.aboutDraft.selectedSchoolId },
                    set: {
                        viewModel.aboutDraft.selectedSchoolId = $0
                        viewModel.aboutSaved = false
                    }
                ),
                disabled: false,
                searchService: schoolSearch,
                appearance: .profile,
                label: "School",
                placeholder: "Start typing your school name"
            )

            if viewModel.aboutSchoolNeedsSelection {
                Text("Please pick a school from the list.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ProfileTheme.negative)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var majorField: some View {
        ProfileField(
            label: "Major",
            value: Binding(
                get: { viewModel.aboutDraft.major },
                set: { viewModel.aboutDraft.major = $0; viewModel.aboutSaved = false }
            ),
            placeholder: "Your major"
        )
    }

    /// Grade is derived from onboarding (`year_of_graduation`); use the
    /// same `ProfileField` chrome as School / Major so the column widths
    /// and row heights line up in the horizontal `ViewThatFits` layout.
    private var gradeField: some View {
        ProfileField(
            label: "Grade",
            value: Binding(
                get: { viewModel.profile.grade },
                set: { _ in }
            ),
            placeholder: "Set during onboarding",
            readOnly: true
        )
    }

    private var statusMessage: String {
        if viewModel.aboutSaved { return "Changes saved to your profile." }
        if viewModel.aboutSchoolNeedsSelection { return "Choose a school from the suggestions." }
        if viewModel.aboutHasChanges { return "You have unsaved profile changes." }
        return "No pending changes."
    }
}
