//
//  CollegeStepView.swift
//  Noteworks
//
//  Created on 2026-04-02.
//

import SwiftUI

struct CollegeStepView: View {
    @ObservedObject var data: OnboardingData
    @EnvironmentObject var appState: AppState
    let onNext: () -> Void
    let onBack: () -> Void
    @State private var visible = false
    @StateObject private var schoolSearch = SchoolSearchService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 80)

                OnboardingProgress(current: 3, total: 6)

                GlassCard {
                    VStack(alignment: .leading, spacing: 0) {
                        OnboardingHeader(title: "Getting To Know You", onBack: onBack)

                        OnboardingRow(disabled: !data.isCollegeValid, onNext: onNext) {
                            Text("Tell us about your academic background.")
                                .font(.system(size: 15))
                                .foregroundStyle(OnboardingTheme.textSecondary)
                                .lineSpacing(4)
                                .padding(.bottom, 24)

                            if data.isOAuthUser {
                                OnboardingField(
                                    label: "School Email",
                                    placeholder: "you@university.edu",
                                    disabled: false,
                                    text: $data.schoolEmail
                                )
                            }

                            // College name with autocomplete
                            SchoolAutocompleteField(
                                college: $data.college,
                                disabled: data.notAStudent,
                                searchService: schoolSearch
                            )

                            OnboardingYearOfStudyPicker(
                                label: "Year of study",
                                disabled: data.notAStudent,
                                selection: $data.yearOfStudySelection
                            )
                            if data.yearOfStudySelection == OnboardingData.yearOfStudyOther && !data.notAStudent {
                                OnboardingField(
                                    label: "Other (please specify)",
                                    placeholder: "Optional — leave empty to save as \"Other\"",
                                    disabled: false,
                                    text: $data.yearOfStudyOtherDetail
                                )
                            }
                            OnboardingCheckbox(label: "Not a College Student?", isChecked: $data.notAStudent)
                        }

                        SkipButton(action: onNext)
                    }
                }
            }
            .padding(.horizontal, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 16)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) { visible = true }
            schoolSearch.accessToken = appState.accessToken
        }
        .onChange(of: data.notAStudent) { _, isNotStudent in
            if isNotStudent {
                data.college = ""
                data.yearOfStudySelection = nil
                data.yearOfStudyOtherDetail = ""
            }
        }
        .onChange(of: data.yearOfStudySelection) { _, newValue in
            if newValue != OnboardingData.yearOfStudyOther {
                data.yearOfStudyOtherDetail = ""
            }
        }
    }
}

// MARK: - School Autocomplete Field

private struct SchoolAutocompleteField: View {
    @Binding var college: String
    let disabled: Bool
    @ObservedObject var searchService: SchoolSearchService
    @FocusState private var focused: Bool
    @State private var showSuggestions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("College Name")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OnboardingTheme.textLabel)

            TextField("e.g. Royal Academy of Arts", text: $college)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(size: 17))
                .foregroundStyle(OnboardingTheme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(disabled ? Color.black.opacity(0.03) : OnboardingTheme.glassBg)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            focused && !disabled
                                ? OnboardingTheme.accent.opacity(0.6)
                                : OnboardingTheme.glassBorder,
                            lineWidth: 1.5
                        )
                }
                .shadow(color: focused && !disabled ? OnboardingTheme.accent.opacity(0.12) : .clear, radius: 6)
                .focused($focused)
                .disabled(disabled)
                .onChange(of: college) { _, newValue in
                    searchService.query = newValue
                    searchService.search()
                    showSuggestions = true
                }
                .onChange(of: focused) { _, isFocused in
                    if isFocused && college.count >= 2 {
                        showSuggestions = true
                    }
                }

            // Suggestions dropdown
            if showSuggestions && !disabled && !searchService.results.isEmpty && focused {
                VStack(spacing: 0) {
                    ForEach(searchService.results) { school in
                        Button {
                            college = school.name
                            showSuggestions = false
                            focused = false
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "building.columns")
                                    .font(.system(size: 14))
                                    .foregroundStyle(OnboardingTheme.accent)
                                    .frame(width: 28, height: 28)
                                    .background(OnboardingTheme.accent.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 7))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(school.name)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(OnboardingTheme.textPrimary)
                                        .lineLimit(1)

                                    if let location = school.location, !location.isEmpty {
                                        Text(location)
                                            .font(.system(size: 12))
                                            .foregroundStyle(OnboardingTheme.textSecondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if school.id != searchService.results.last?.id {
                            Divider()
                                .padding(.leading, 54)
                        }
                    }
                }
                .background(.ultraThinMaterial)
                .background(Color.white.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(OnboardingTheme.glassBorder, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeOut(duration: 0.15), value: searchService.results.count)
            }

            // Loading indicator
            if searchService.isLoading && focused && college.count >= 2 {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Searching schools...")
                        .font(.system(size: 13))
                        .foregroundStyle(OnboardingTheme.textSecondary)
                }
                .padding(.top, 4)
            }
        }
        .opacity(disabled ? 0.35 : 1)
        .animation(.easeOut(duration: 0.3), value: disabled)
        .padding(.bottom, 18)
    }
}

#Preview {
    ZStack {
        OnboardingBackground()
            .ignoresSafeArea()
        CollegeStepView(data: OnboardingData(), onNext: {}, onBack: {})
            .environmentObject(AppState(notesStore: NotesStore.preview()))
    }
}
