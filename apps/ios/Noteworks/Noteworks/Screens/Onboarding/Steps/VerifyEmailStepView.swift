//
//  VerifyEmailStepView.swift
//  Noteworks
//
//  Created on 2026-04-02.
//

import SwiftUI

struct VerifyEmailStepView: View {
    @ObservedObject var data: OnboardingData
    let onNext: () -> Void
    let onBack: () -> Void
    let onResend: () -> Void
    @State private var visible = false
    @FocusState private var focusedIndex: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 80)

                OnboardingProgress(current: 2, total: 6)

                GlassCard {
                    VStack(alignment: .leading, spacing: 0) {
                        OnboardingHeader(title: "Verify your Email", onBack: onBack)

                        OnboardingRow(disabled: !data.isVerifyValid, onNext: onNext) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("We've sent a verification code to ")
                                    .foregroundStyle(OnboardingTheme.textSecondary)
                                +
                                Text(data.email.isEmpty ? "your email" : data.email)
                                    .foregroundStyle(OnboardingTheme.accent)
                                    .fontWeight(.semibold)
                            }
                            .font(.system(size: 15))
                            .lineSpacing(4)
                            .padding(.bottom, 28)

                            HStack(spacing: 8) {
                                ForEach(0..<6, id: \.self) { i in
                                    TextField("", text: $data.verificationCode[i])
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .multilineTextAlignment(.center)
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundStyle(OnboardingTheme.textPrimary)
                                        .frame(width: 48, height: 68)
                                        .background(OnboardingTheme.glassBg)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 16)
                                                .strokeBorder(
                                                    !data.verificationCode[i].isEmpty
                                                        ? OnboardingTheme.accent.opacity(0.6)
                                                        : OnboardingTheme.glassBorder,
                                                    lineWidth: 1.5
                                                )
                                        }
                                        .focused($focusedIndex, equals: i)
                                        .onChange(of: data.verificationCode[i]) { oldVal, newVal in
                                            if newVal.count > 1 {
                                                data.verificationCode[i] = String(newVal.suffix(1))
                                            }
                                            if !data.verificationCode[i].isEmpty && i < 5 {
                                                focusedIndex = i + 1
                                            } else if data.verificationCode[i].isEmpty && !oldVal.isEmpty && i > 0 {
                                                focusedIndex = i - 1
                                            }
                                        }
                                }
                            }
                            .padding(.bottom, 24)

                            Button("Resend code", action: onResend)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(OnboardingTheme.accent)
                                .buttonStyle(.plain)
                        }
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
            focusedIndex = 0
        }
    }
}
