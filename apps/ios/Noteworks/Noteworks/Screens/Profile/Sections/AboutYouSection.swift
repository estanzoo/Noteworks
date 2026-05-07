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
                    enabled: viewModel.aboutHasChanges
                ) {
                    viewModel.saveAbout()
                }
                .frame(maxWidth: 180)
            }
        }
    }

    private var schoolField: some View {
        ProfileField(
            label: "School",
            value: Binding(
                get: { viewModel.aboutDraft.school },
                set: { viewModel.aboutDraft.school = $0; viewModel.aboutSaved = false }
            ),
            placeholder: "Your school"
        )
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

    private var gradeField: some View {
        ProfileField(
            label: "Grade",
            value: Binding(
                get: { viewModel.aboutDraft.grade },
                set: { viewModel.aboutDraft.grade = $0; viewModel.aboutSaved = false }
            ),
            placeholder: "Grade / year"
        )
    }

    private var statusMessage: String {
        if viewModel.aboutSaved { return "Changes saved to your profile." }
        if viewModel.aboutHasChanges { return "You have unsaved profile changes." }
        return "No pending changes."
    }
}
