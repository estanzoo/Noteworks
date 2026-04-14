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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 80)

                OnboardingProgress(current: 4, total: 5)

                GlassCard {
                    VStack(alignment: .leading, spacing: 0) {
                        OnboardingHeader(title: "Enter Your Major", onBack: onBack)

                        OnboardingRow(disabled: !data.isMajorValid, onNext: onNext) {
                            OnboardingField(
                                label: "Faculty Name",
                                placeholder: "e.g. School of Engineering",
                                disabled: data.undeclared,
                                text: $data.school
                            )
                            OnboardingField(
                                label: "Major Name",
                                placeholder: "e.g. Computer Science",
                                disabled: data.undeclared,
                                text: $data.major
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
}

#Preview {
    ZStack {
        OnboardingBackground()
            .ignoresSafeArea()
        MajorStepView(data: OnboardingData(), onNext: {}, onBack: {})
    }
}

