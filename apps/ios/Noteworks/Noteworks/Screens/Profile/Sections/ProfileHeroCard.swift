//
//  ProfileHeroCard.swift
//  Noteworks
//
//  Mirrors the hero GlassCard inside ProfilePage from
//  others/noteworks-library(2).jsx L6491–L6561.
//

import SwiftUI
import PhotosUI

struct ProfileHeroCard: View {
    @ObservedObject var viewModel: ProfileViewModel
    @EnvironmentObject private var appState: AppState
    @State private var photoItem: PhotosPickerItem?

    /// Available width inside the hero card. We measure once with a
    /// transparent `GeometryReader` overlay (so it never affects layout) and
    /// drive the horizontal/vertical split off the resolved width — mirroring
    /// the JSX rule `@media(max-width:980px)` (L8001) instead of relying on
    /// `horizontalSizeClass`, which can report `.compact` even when there is
    /// plenty of room (e.g. iPhone landscape, iPad split view).
    @State private var availableWidth: CGFloat = 1024

    /// Below this card-width we collapse to the stacked layout. The side-by-
    /// side layout has to fit the avatar sidebar (~180), the AT A GLANCE pill
    /// bar (which is `fixedSize`, ~470), and still leave the name column real
    /// room. Below ~900 the name gets starved to near-zero width and wraps one
    /// letter per line (iPad portrait), so we stack instead.
    private let horizontalThreshold: CGFloat = 900
    private var isCompact: Bool { availableWidth < horizontalThreshold }

    private var trimmedHeroBio: String {
        viewModel.profile.bio.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var heroBioPlaceholder: String {
        "No bio yet — add one under About You, then save."
    }

    var body: some View {
        GlassCard(padding: 24, cornerRadius: 24) {
            Group {
                if isCompact {
                    // Keep the name beside the photo (like the wide layout) and
                    // stack the description, AT A GLANCE, BIO, and plan chips in
                    // that right column so they all fill the space next to the
                    // avatar.
                    HStack(alignment: .top, spacing: 18) {
                        sidebar
                        VStack(alignment: .leading, spacing: 14) {
                            nameBlock
                            atAGlanceBlock
                                .frame(maxWidth: .infinity, alignment: .leading)
                            bioBlock
                            planChips
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 28) {
                        sidebar
                        mainContent
                    }
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { availableWidth = geo.size.width }
                        .onChange(of: geo.size.width) { _, newValue in
                            availableWidth = newValue
                        }
                }
            )
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task { @MainActor in
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    // Fires the upload + AppState.refreshProfile pipeline so
                    // the new photo propagates to community posts/comments
                    // on the next feed read.
                    viewModel.setPhoto(data, using: appState)
                }
            }
        }
    }

    // MARK: - Sidebar (avatar + photo actions)

    private var sidebar: some View {
        // Capture out of the actor-isolated view model so the PhotosPicker's
        // `@Sendable` label closure can read it without a concurrency warning.
        let hasPhoto = viewModel.profile.photoData != nil || viewModel.profile.avatarUrl != nil
        return VStack(spacing: 12) {
            ZStack {
                AvatarBadge(profile: viewModel.profile, size: 126, fontSize: 38)

                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Text(hasPhoto ? "Change Photo" : "Set Photo")
                        .font(.system(size: 10.5, weight: .bold))
                        .tracking(0.01 * 10.5)
                        .foregroundStyle(ProfileTheme.accent)
                        .padding(.horizontal, 12)
                        .frame(minWidth: 76, minHeight: 28)
                        .background(
                            Capsule().fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.8), Color.white.opacity(0.58)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        )
                        .background(Capsule().fill(.ultraThinMaterial))
                        .overlay(
                            Capsule().strokeBorder(Color.white.opacity(0.68), lineWidth: 1)
                        )
                        .shadow(color: ProfileTheme.accent.opacity(0.16), radius: 5, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .offset(y: 42)
            }
            .frame(width: 126, height: 126)
            .padding(.bottom, 12)

            if viewModel.academicEmailVerified {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("Verified")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(ProfileTheme.accent)
                .padding(.horizontal, 10)
                .frame(minHeight: 24)
                .background(Capsule().fill(ProfileTheme.accent.opacity(0.14)))
                .overlay(Capsule().strokeBorder(ProfileTheme.accent.opacity(0.22), lineWidth: 1))
            }

            if viewModel.isUploadingPhoto {
                Text("Uploading…")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ProfileTheme.textMuted)
            } else if let message = viewModel.photoUploadError {
                Text(message)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.red.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 180)
            }

            if hasPhoto {
                ProfileSecondaryButton(title: "Remove Photo", compact: true) {
                    viewModel.removePhoto()
                }
            }
        }
        .frame(maxWidth: 180)
    }

    // MARK: - Main (text + chips)

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                nameBlock
                Spacer(minLength: 8)
                atAGlanceBlock
                    .fixedSize(horizontal: true, vertical: false)
            }

            bioBlock
            planChips
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Bio — mirrors `.profile-hero-about` (JSX L7928): light glass strip
    /// with 16pt radius, white 0.46 border, and 12/14 padding.
    private var bioBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("BIO")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.08 * 11)
                .foregroundStyle(ProfileTheme.textMuted)

            Text(trimmedHeroBio.isEmpty ? heroBioPlaceholder : trimmedHeroBio)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(trimmedHeroBio.isEmpty ? ProfileTheme.textMuted : ProfileTheme.textSecondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.26))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.46), lineWidth: 1)
        )
    }

    private var planChips: some View {
        HStack(spacing: 8) {
            ProfileAccentChip(text: viewModel.profile.subscription.plan, emphasized: true)
            ProfileAccentChip(text: "\(viewModel.profile.credits.balance) Credits Available")
            Spacer(minLength: 0)
        }
    }

    private var nameBlock: some View {
        // Empty `Profile.initial` plus a brand-new user with no
        // server-side name shouldn't render a blank name row or a
        // dangling " at " subtitle — fall back to friendly defaults.
        let displayName = viewModel.profile.name.isEmpty
            ? "Welcome to NoteWorks"
            : viewModel.profile.name
        let major  = viewModel.profile.major.trimmingCharacters(in: .whitespaces)
        let school = viewModel.profile.school.trimmingCharacters(in: .whitespaces)
        let subtitle: String?
        switch (major.isEmpty, school.isEmpty) {
        case (false, false): subtitle = "\(major) at \(school)"
        case (false, true):  subtitle = major
        case (true,  false): subtitle = school
        case (true,  true):  subtitle = nil
        }
        return VStack(alignment: .leading, spacing: 5) {
            Text(displayName)
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.03 * 24)
                .foregroundStyle(ProfileTheme.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ProfileTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Mirrors `.profile-hero-glance` (JSX L7927): horizontal glass container
    /// with 18pt radius, white 0.48 border, and 10/12 padding wrapping the
    /// "AT A GLANCE" label + summary pills.
    /// Uses `HStack` (not `FlowLayout`) so the block reports a finite,
    /// content-sized intrinsic width — `FlowLayout` returns
    /// `proposal.width ?? .infinity`, which would otherwise claim the entire
    /// row and squash the name block to width 0.
    private var atAGlanceBlock: some View {
        HStack(spacing: 8) {
            Text("AT A GLANCE")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.08 * 11)
                .foregroundStyle(ProfileTheme.textMuted)
                .padding(.trailing, 4)

            ProfileSummaryPill(title: "Plan", value: viewModel.profile.subscription.status)
            ProfileSummaryPill(title: "Credits", value: "\(viewModel.usageTotal) used")
            ProfileSummaryPill(title: "Linked", value: "\(viewModel.linkedCount)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.28))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.48), lineWidth: 1)
        )
    }
}

// Note: `FlowLayout` is defined once in the Onboarding module and reused here.
