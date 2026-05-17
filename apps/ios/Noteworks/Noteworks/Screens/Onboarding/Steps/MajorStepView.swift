//
//  MajorStepView.swift
//  Noteworks
//
//  Created on 2026-04-02.
//

import SwiftUI

struct MajorStepView: View {
    @ObservedObject var data: OnboardingData
    let onNext: () -> Void
    let onBack: () -> Void
    @State private var visible = false
    /// See `SignUpStepView.attemptedNext` — only show the "please enter"
    /// errors after the user has tried to advance once.
    @State private var attemptedNext = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 80)

                OnboardingProgress(current: 4, total: 6)

                GlassCard {
                    VStack(alignment: .leading, spacing: 0) {
                        OnboardingHeader(title: "Enter Your Major", onBack: onBack)

                        OnboardingRow(disabled: false, onNext: handleNext) {
                            OnboardingField(
                                label: "Faculty/School Name",
                                placeholder: "e.g. School of Engineering",
                                disabled: data.undeclared,
                                text: $data.school
                            )
                            OnboardingError(
                                show: attemptedNext && data.majorFacultyError != nil,
                                text: data.majorFacultyError ?? ""
                            )

                            OnboardingField(
                                label: "Major Name",
                                placeholder: "e.g. Computer Science",
                                disabled: data.undeclared,
                                text: $data.major
                            )
                            OnboardingError(
                                show: attemptedNext && data.majorNameError != nil,
                                text: data.majorNameError ?? ""
                            )

                            OnboardingCheckbox(label: "Undeclared?", isChecked: $data.undeclared)
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
    }

    private func handleNext() {
        if data.isMajorValid {
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
        MajorStepView(data: OnboardingData(), onNext: {}, onBack: {})
    }
}
