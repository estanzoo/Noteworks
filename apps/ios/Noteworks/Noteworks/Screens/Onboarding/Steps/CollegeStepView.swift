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
                                schoolName: $data.college,
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
                data.school = ""
                data.major = ""
                data.undeclared = false
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
