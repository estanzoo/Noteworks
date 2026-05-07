//
//  FeedbackSection.swift
//  Noteworks
//
//  Mirrors the "feedback" case in renderDetail() from
//  others/noteworks-library(2).jsx L6292–L6469.
//

import SwiftUI
import PhotosUI

struct FeedbackSection: View {
    @ObservedObject var viewModel: ProfileViewModel
    @State private var photoItems: [PhotosPickerItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ProfileSectionHeader(
                eyebrow: "Feedback",
                title: "Help shape the beta",
                copy: "Capture where it happened, how serious it feels, and what you expected so the next design pass has something actionable to work from."
            )

            tipsCard

            pillRow(
                heading: "Type",
                values: viewModel.feedbackTypes,
                current: viewModel.feedbackType
            ) { viewModel.feedbackType = $0 }

            pillRow(
                heading: "Where did it happen?",
                values: viewModel.feedbackAreas,
                current: viewModel.feedbackArea
            ) { viewModel.feedbackArea = $0 }

            if viewModel.feedbackArea == "Other" {
                ProfileField(
                    label: "Where exactly?",
                    value: $viewModel.feedbackAreaOther,
                    placeholder: "Tell us where this happened..."
                )
            }

            pillRow(
                heading: "Impact",
                values: viewModel.feedbackPriorities,
                current: viewModel.feedbackPriority
            ) { viewModel.feedbackPriority = $0 }

            ProfileField(
                label: "Short Summary",
                value: $viewModel.feedbackTitle,
                placeholder: "\(viewModel.feedbackType) in \(viewModel.effectiveFeedbackArea.lowercased())..."
            )

            ProfileField(
                label: "What happened?",
                value: $viewModel.feedbackText,
                placeholder: "Describe the \(viewModel.feedbackType.lowercased()) in \(viewModel.effectiveFeedbackArea.lowercased()), what you expected, and any detail that would help us reproduce it...",
                multiline: true
            )

            photosBlock
            followUpBlock
            submitBar
        }
        .onChange(of: photoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { @MainActor in
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        viewModel.appendFeedbackPhoto(data)
                    }
                }
                photoItems = []
            }
        }
    }

    // MARK: - Tips card

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BETA FEEDBACK TIPS")
                .font(.system(size: 12, weight: .bold))
                .tracking(0.08 * 12)
                .foregroundStyle(ProfileTheme.textMuted)
            Text("The fastest useful report usually includes three things: where you were, what felt off, and what you expected instead.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ProfileTheme.textSecondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            ProfileTheme.accent.opacity(0.12),
                            Color.white.opacity(0.38),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ProfileTheme.accent.opacity(0.18), lineWidth: 1)
        )
    }

    // MARK: - Pill row helper

    private func pillRow(heading: String, values: [String], current: String, onSelect: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ProfileTheme.textMuted)
            FlowLayout(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    ProfileChoicePill(
                        label: value,
                        active: value == current
                    ) {
                        onSelect(value)
                    }
                }
            }
        }
    }

    // MARK: - Photos

    private var photosBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Photos")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ProfileTheme.textMuted)

            HStack(spacing: 10) {
                PhotosPicker(selection: $photoItems, matching: .images, photoLibrary: .shared()) {
                    Text("Upload Photos")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ProfileTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .frame(minHeight: 46)
                        .background(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(Color.white.opacity(0.42))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(Color.black.opacity(0.06), lineWidth: 1.5)
                        )
                }
                .buttonStyle(PillPressStyle())

                Text("Screenshots help us understand beta issues faster.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ProfileTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !viewModel.feedbackPhotos.isEmpty {
                FlowLayout(spacing: 10) {
                    ForEach(viewModel.feedbackPhotos) { photo in
                        if let image = UIImage(data: photo.data) {
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 104, height: 104)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(ProfileTheme.glassBorder, lineWidth: 1)
                                    )

                                Button {
                                    viewModel.removeFeedbackPhoto(photo.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 24, height: 24)
                                        .background(Circle().fill(Color(red: 16/255, green: 22/255, blue: 32/255).opacity(0.58)))
                                }
                                .buttonStyle(.plain)
                                .padding(6)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Follow-up

    private var followUpBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow follow-up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ProfileTheme.textPrimary)
                    Text(viewModel.feedbackFollowUp
                         ? "We can reach back out at \(viewModel.feedbackOtherEmail.trimmingCharacters(in: .whitespaces).isEmpty ? viewModel.profile.email : viewModel.feedbackOtherEmail.trimmingCharacters(in: .whitespaces))."
                         : "Keep this report as a one-way beta note.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(ProfileTheme.textSecondary)
                }
                Spacer(minLength: 8)

                Group {
                    if viewModel.feedbackFollowUp {
                        ProfilePrimaryButton(title: "Follow-up On") {
                            viewModel.feedbackFollowUp = false
                            viewModel.feedbackOtherEmailOpen = false
                        }
                    } else {
                        ProfileSecondaryButton(title: "Follow-up Off") {
                            viewModel.feedbackFollowUp = true
                        }
                    }
                }
                .frame(maxWidth: 160)
            }
            .profileRowCard()

            if viewModel.feedbackFollowUp {
                VStack(alignment: .leading, spacing: 10) {
                    InlineLinkAction(
                        label: viewModel.feedbackOtherEmailOpen
                            ? "Use your account email instead"
                            : "Want us to get back to you with another email?"
                    ) {
                        if viewModel.feedbackOtherEmailOpen { viewModel.feedbackOtherEmail = "" }
                        viewModel.feedbackOtherEmailOpen.toggle()
                    }

                    if viewModel.feedbackOtherEmailOpen {
                        VStack(alignment: .leading, spacing: 10) {
                            ProfileField(
                                label: "Follow-up Email",
                                value: $viewModel.feedbackOtherEmail,
                                placeholder: "name@example.com",
                                keyboardType: .emailAddress,
                                autocapitalization: .never
                            )
                            Text("We'll use this email only to follow up on this feedback thread.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(ProfileTheme.textSecondary)
                                .lineSpacing(3)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.32))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(ProfileTheme.glassBorder, lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Submit bar

    private var submitBar: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(
                viewModel.feedbackSent
                    ? "\(viewModel.feedbackType) feedback for \(viewModel.effectiveFeedbackArea) captured for the next beta pass."
                    : "This report will be tagged as \(viewModel.feedbackPriority.lowercased()) impact in \(viewModel.effectiveFeedbackArea.lowercased())."
            )
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(viewModel.feedbackSent ? ProfileTheme.positive : ProfileTheme.textSecondary)
            .lineSpacing(4)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            ProfilePrimaryButton(
                title: "Submit Beta Feedback",
                enabled: viewModel.canSubmitFeedback
            ) {
                viewModel.submitFeedback()
            }
            .frame(maxWidth: 220)
        }
        .padding(.top, 4)
    }
}
