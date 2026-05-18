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
    /// Owned by `OnboardingFlow` so the full schools list can prefetch
    /// while the user is still on Welcome / Sign-Up. By the time we land
    /// here the cache is usually warm and the autocomplete runs locally.
    @ObservedObject var schoolSearch: SchoolSearchService
    let onNext: () -> Void
    let onBack: () -> Void
    @State private var visible = false
    /// Flipped on the first invalid Next tap. After that, all
    /// required-field errors render live until the user passes
    /// validation. The "must pick from the list" error is already live
    /// (driven by `data.hasUnrecognisedCollege`) — it's the most common
    /// mistake on this page.
    @State private var attemptedNext = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 80)

                OnboardingProgress(current: 3, total: 6)

                GlassCard {
                    VStack(alignment: .leading, spacing: 0) {
                        OnboardingHeader(title: "Getting To Know You", onBack: onBack)

                        OnboardingRow(disabled: false, onNext: handleNext) {
                            Text("Tell us about your academic background.")
                                .font(.system(size: 15))
                                .foregroundStyle(OnboardingTheme.textSecondary)
                                .lineSpacing(4)
                                .padding(.bottom, 24)

                            if data.isOAuthUser {
                                OnboardingField(
                                    label: "Name",
                                    placeholder: "Your name",
                                    disabled: false,
                                    text: $data.name
                                )
                                OnboardingError(
                                    show: attemptedNext && data.collegeOAuthNameError != nil,
                                    text: data.collegeOAuthNameError ?? ""
                                )

                                OnboardingField(
                                    label: "School Email",
                                    placeholder: "you@university.edu",
                                    disabled: false,
                                    text: $data.schoolEmail
                                )
                                OnboardingError(
                                    show: attemptedNext && data.collegeSchoolEmailError != nil,
                                    text: data.collegeSchoolEmailError ?? ""
                                )
                            }

                            // College name with autocomplete. Users must
                            // pick a row from the suggestion list — free-
                            // form names are rejected via `isCollegeValid`
                            // and surfaced as an inline error here.
                            SchoolAutocompleteField(
                                college: $data.college,
                                selectedSchoolId: $data.selectedSchoolId,
                                disabled: data.notAStudent,
                                searchService: schoolSearch
                            )
                            // The "must pick from the list" message is
                            // live — it's the single most common mistake
                            // on this page, so we don't wait for a Next
                            // tap to surface it. Empty-field errors stay
                            // gated on `attemptedNext`.
                            OnboardingError(
                                show: data.hasUnrecognisedCollege
                                    || (attemptedNext && data.collegeNameError != nil),
                                text: data.hasUnrecognisedCollege
                                    ? "Please pick a school from the list."
                                    : (data.collegeNameError ?? "")
                            )

                            OnboardingYearOfStudyPicker(
                                label: "Year of study",
                                disabled: data.notAStudent,
                                selection: $data.yearOfStudySelection
                            )
                            OnboardingError(
                                show: attemptedNext && data.yearOfStudyError != nil,
                                text: data.yearOfStudyError ?? ""
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
            // Belt-and-braces: `OnboardingFlow` already kicks off the
            // prefetch the moment a token is available, but we re-trigger
            // here so that any branch that bypasses that path (e.g. an
            // older preview / test harness) still gets a populated cache.
            if let token = appState.accessToken {
                schoolSearch.prefetchAll(accessToken: token)
            }
        }
        .onChange(of: data.notAStudent) { _, isNotStudent in
            if isNotStudent {
                data.college = ""
                data.selectedSchoolId = nil
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

    private func handleNext() {
        if data.isCollegeValid {
            onNext()
        } else {
            attemptedNext = true
        }
    }
}

// MARK: - School Autocomplete Field

private struct SchoolAutocompleteField: View {
    @Binding var college: String
    /// Set when the user picks a row from the suggestions dropdown;
    /// cleared whenever the text field is edited. `CollegeStepView` uses
    /// this to enforce "must pick from the list" — see `isCollegeValid`.
    @Binding var selectedSchoolId: String?
    let disabled: Bool
    @ObservedObject var searchService: SchoolSearchService
    @FocusState private var focused: Bool
    @State private var showSuggestions = false
    /// Suppresses the `onChange(of: college)` clear-selection side effect
    /// while we programmatically write the picked school name into the
    /// field. Without it, tapping a suggestion would set the id and then
    /// immediately wipe it again because writing `college = school.name`
    /// fires `onChange`.
    @State private var isApplyingSelection = false

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
                    // Any manual edit invalidates the previous pick — the
                    // user must confirm by tapping a suggestion again.
                    if isApplyingSelection {
                        isApplyingSelection = false
                    } else if selectedSchoolId != nil {
                        selectedSchoolId = nil
                    }
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
                            isApplyingSelection = true
                            college = school.name
                            selectedSchoolId = school.id
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
        CollegeStepView(
            data: OnboardingData(),
            schoolSearch: SchoolSearchService(),
            onNext: {},
            onBack: {}
        )
        .environmentObject(AppState(notesStore: NotesStore.preview()))
    }
}
