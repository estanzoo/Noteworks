//
//  CollegeStepView.swift
//  Noteworks
//
//  Created on 2026-04-02.
//

import SwiftUI

struct CollegeStepView: View {
    @ObservedObject var data: OnboardingData
    let onNext: () -> Void
    let onBack: () -> Void
    @State private var visible = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 80)

                OnboardingProgress(current: 3, total: 5)

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

                            OnboardingField(
                                label: "College Name",
                                placeholder: "e.g. Royal Academy of Arts",
                                disabled: data.notAStudent,
                                text: $data.college
                            )
                            OnboardingYearOfStudyPicker(
                                label: "Year of study",
                                disabled: data.notAStudent,
                                selection: $data.yearOfStudySelection
                            )
                            if data.yearOfStudySelection == OnboardingData.yearOfStudyOther && !data.notAStudent {
                                OnboardingField(
                                    label: "Other (please specify)",
                                    placeholder: "Optional — leave empty to save as “Other”",
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
