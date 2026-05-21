//
//  ProfileAboutPopups.swift
//  Noteworks
//
//  Edit popups for Profile → About You. Mirrors ProfileTextEditPopup,
//  SchoolSearchPopup, and GradeSelectPopup from
//  others/NoteWorks_UI 4/noteworks-library.jsx L9848–L10127.
//

import SwiftUI

// MARK: - Text edit popup

struct ProfileTextEditPopup: View {
    let field: ProfileTextEditorField
    @Binding var value: String
    let onClose: () -> Void
    let onSave: () -> Void

    var body: some View {
        ZStack {
            Color(red: 18/255, green: 28/255, blue: 38/255)
                .opacity(0.18)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(field.label.uppercased())
                            .font(.system(size: 12, weight: .heavy))
                            .tracking(0.08 * 12)
                            .foregroundStyle(ProfileTheme.textMuted)

                        Text("Edit \(field.label)")
                            .font(.system(size: 24, weight: .bold))
                            .tracking(-0.03 * 24)
                            .foregroundStyle(ProfileTheme.textPrimary)
                    }

                    Spacer(minLength: 8)

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(ProfileTheme.textMuted)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.58)))
                    }
                    .buttonStyle(.plain)
                }

                ProfileField(
                    label: field.label,
                    value: $value,
                    placeholder: "Edit \(field.label.lowercased())...",
                    multiline: field == .bio
                )

                HStack(spacing: 10) {
                    Spacer()
                    Button("Cancel", action: onClose)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(ProfileTheme.textSecondary)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.62))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(ProfileTheme.glassBorder, lineWidth: 1)
                        )
                        .buttonStyle(.plain)

                    Button("Save", action: onSave)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(ProfileTheme.accentGradient)
                        )
                        .shadow(color: ProfileTheme.accent.opacity(0.24), radius: 11, y: 5)
                        .buttonStyle(.plain)
                }
            }
            .padding(24)
            .frame(maxWidth: 480)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.92),
                                Color(red: 244/255, green: 248/255, blue: 252/255).opacity(0.88)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(ProfileTheme.glassBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 32, y: 12)
            .padding(.horizontal, 24)
        }
        .zIndex(92)
    }
}

// MARK: - School search popup

struct ProfileSchoolSearchPopup: View {
    @ObservedObject var viewModel: ProfileViewModel
    @ObservedObject var searchService: SchoolSearchService

    var body: some View {
        ZStack {
            Color(red: 18/255, green: 28/255, blue: 38/255)
                .opacity(0.18)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture { viewModel.closeSchoolEditor() }

            VStack(alignment: .leading, spacing: 16) {
                header

                TextField("Search your school...", text: $viewModel.schoolQuery)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ProfileTheme.textPrimary)
                    .padding(.horizontal, 15)
                    .frame(minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white.opacity(0.74))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(ProfileTheme.glassBorder, lineWidth: 1)
                    )
                    .onChange(of: viewModel.schoolQuery) { _, newValue in
                        searchService.query = newValue
                        searchService.search()
                    }

                ScrollView {
                    LazyVStack(spacing: 6) {
                        if searchService.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        } else if viewModel.schoolQuery.trimmingCharacters(in: .whitespaces).count < 2 {
                            Text("Type at least 2 characters to search.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ProfileTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 8)
                        } else if searchService.results.isEmpty {
                            Text("No schools found. Try a different spelling.")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(ProfileTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(searchService.results) { school in
                                Button {
                                    viewModel.selectSchool(school)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(school.name)
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(ProfileTheme.textPrimary)
                                            if let location = school.location, !location.isEmpty {
                                                Text(location)
                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundStyle(ProfileTheme.textSecondary)
                                            }
                                        }
                                        Spacer()
                                        if school.name == viewModel.aboutDraft.school {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(ProfileTheme.accent)
                                        }
                                    }
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 48, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 15)
                                            .fill(
                                                school.name == viewModel.aboutDraft.school
                                                    ? ProfileTheme.accent.opacity(0.12)
                                                    : Color.white.opacity(0.48)
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 15)
                                            .strokeBorder(
                                                school.name == viewModel.aboutDraft.school
                                                    ? ProfileTheme.accent.opacity(0.24)
                                                    : ProfileTheme.glassBorder,
                                                lineWidth: 1
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 340)
            }
            .padding(24)
            .frame(maxWidth: 540)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.92),
                                Color(red: 244/255, green: 248/255, blue: 252/255).opacity(0.88)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(ProfileTheme.glassBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 32, y: 12)
            .padding(.horizontal, 24)
        }
        .zIndex(93)
        .onAppear {
            searchService.query = viewModel.schoolQuery
            searchService.search()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("SCHOOL")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(0.08 * 12)
                    .foregroundStyle(ProfileTheme.textMuted)

                Text("Choose your school")
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.03 * 24)
                    .foregroundStyle(ProfileTheme.textPrimary)

                if !viewModel.aboutDraft.school.isEmpty {
                    Text("Current: \(viewModel.aboutDraft.school)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ProfileTheme.textSecondary)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 8)

            Button(action: { viewModel.closeSchoolEditor() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ProfileTheme.textMuted)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.58)))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Grade select popup

struct ProfileGradeSelectPopup: View {
    @ObservedObject var viewModel: ProfileViewModel

    var body: some View {
        ZStack {
            Color(red: 18/255, green: 28/255, blue: 38/255)
                .opacity(0.18)
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture { viewModel.closeGradeEditor() }

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("GRADE")
                            .font(.system(size: 12, weight: .heavy))
                            .tracking(0.08 * 12)
                            .foregroundStyle(ProfileTheme.textMuted)

                        Text("Choose your grade")
                            .font(.system(size: 24, weight: .bold))
                            .tracking(-0.03 * 24)
                            .foregroundStyle(ProfileTheme.textPrimary)
                    }

                    Spacer(minLength: 8)

                    Button(action: { viewModel.closeGradeEditor() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(ProfileTheme.textMuted)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color.white.opacity(0.58)))
                    }
                    .buttonStyle(.plain)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(PROFILE_GRADE_GROUPS) { group in
                            Text(group.label.uppercased())
                                .font(.system(size: 11, weight: .heavy))
                                .tracking(0.08 * 11)
                                .foregroundStyle(ProfileTheme.textMuted)
                                .padding(.horizontal, 8)
                                .padding(.top, 10)
                                .padding(.bottom, 4)

                            ForEach(group.options, id: \.self) { option in
                                gradeOptionButton(option)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 4)
                }
            }
            .padding(24)
            .frame(maxWidth: 560, maxHeight: min(660, UIScreen.main.bounds.height - 48))
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.92),
                                Color(red: 244/255, green: 248/255, blue: 252/255).opacity(0.88)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(ProfileTheme.glassBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.14), radius: 32, y: 12)
            .padding(.horizontal, 24)
        }
        .zIndex(93)
    }

    private func gradeOptionButton(_ option: String) -> some View {
        let selected = viewModel.aboutDraft.grade == option
        return Button {
            viewModel.selectGrade(option)
        } label: {
            HStack {
                Text(option)
                    .font(.system(size: 14, weight: selected ? .heavy : .semibold))
                    .foregroundStyle(selected ? ProfileTheme.accent : ProfileTheme.textPrimary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ProfileTheme.accent)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(selected ? ProfileTheme.accent.opacity(0.12) : Color.white.opacity(0.48))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    .strokeBorder(
                        selected ? ProfileTheme.accent.opacity(0.24) : ProfileTheme.glassBorder,
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
