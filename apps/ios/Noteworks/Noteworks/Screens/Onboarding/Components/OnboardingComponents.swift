//
//  OnboardingComponents.swift
//  Noteworks
//
//  Created on 2026-04-02.
//

import SwiftUI

// MARK: - Beta Badge

struct BetaBadge: View {
    var body: some View {
        Text("BETA")
            .font(.system(size: 11, weight: .bold))
            .kerning(0.7)
            .foregroundStyle(Color(red: 122/255, green: 138/255, blue: 150/255))
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
            }
    }
}

// MARK: - Progress Bar

struct OnboardingProgress: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.black.opacity(0.06))
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(OnboardingTheme.accentGradient)
                        .frame(width: geo.size.width * CGFloat(current) / CGFloat(total), height: 3)
                        .animation(.easeInOut(duration: 0.6), value: current)
                }
            }
            .frame(height: 3)

            Text("\(current)/\(total)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 154/255, green: 164/255, blue: 174/255))
        }
        .padding(.bottom, 28)
    }
}

// MARK: - Arrow (Next) Button

struct ArrowButton: View {
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(disabled
                        ? AnyShapeStyle(Color.white.opacity(0.25))
                        : AnyShapeStyle(OnboardingTheme.accentGradient))
                    .frame(width: 54, height: 54)
                    .shadow(color: disabled ? .clear : OnboardingTheme.accent.opacity(0.35), radius: 10, y: 4)

                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(disabled ? Color.black.opacity(0.15) : .white)
            }
        }
        .disabled(disabled)
    }
}

// MARK: - Back Button

struct OnboardingBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(OnboardingTheme.textPrimary)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                }
        }
    }
}

// MARK: - Step Header (Back + Title)

struct OnboardingHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            OnboardingBackButton(action: onBack)
            Text(title)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(OnboardingTheme.textPrimary)
            Spacer()
        }
        .padding(.bottom, 24)
    }
}

// MARK: - Styled Text Field

struct OnboardingField: View {
    let label: String
    let placeholder: String
    var isSecure: Bool = false
    var isEmail: Bool = false
    var disabled: Bool = false
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OnboardingTheme.textLabel)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } else {
                    TextField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(isEmail ? .emailAddress : .default)
                        .textContentType(isEmail ? .emailAddress : nil)
                }
            }
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
        }
        .opacity(disabled ? 0.35 : 1)
        .animation(.easeOut(duration: 0.3), value: disabled)
        .padding(.bottom, 18)
    }
}

// MARK: - Year of study (inline dropdown)

struct OnboardingYearOfStudyPicker: View {
    let label: String
    var disabled: Bool = false
    @Binding var selection: String?
    @State private var isOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OnboardingTheme.textLabel)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isOpen.toggle() }
            } label: {
                HStack {
                    Text(selection ?? "Select year")
                        .font(.system(size: 17))
                        .foregroundStyle(
                            selection == nil ? OnboardingTheme.textSecondary : OnboardingTheme.textPrimary
                        )
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(OnboardingTheme.textSecondary.opacity(0.8))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isOpen)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(disabled ? Color.black.opacity(0.03) : OnboardingTheme.glassBg)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            isOpen && !disabled
                                ? OnboardingTheme.accent.opacity(0.6)
                                : OnboardingTheme.glassBorder,
                            lineWidth: 1.5
                        )
                }
                .shadow(color: isOpen && !disabled ? OnboardingTheme.accent.opacity(0.12) : .clear, radius: 6)
            }
            .buttonStyle(.plain)
            .disabled(disabled)

            if isOpen && !disabled {
                VStack(spacing: 0) {
                    ForEach(OnboardingData.yearOfStudyOptions, id: \.self) { option in
                        Button {
                            selection = option
                            withAnimation(.easeInOut(duration: 0.2)) { isOpen = false }
                        } label: {
                            HStack(spacing: 12) {
                                if selection == option {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(OnboardingTheme.accent)
                                        .frame(width: 18)
                                } else {
                                    Spacer().frame(width: 18)
                                }

                                Text(option)
                                    .font(.system(size: 16, weight: selection == option ? .semibold : .regular))
                                    .foregroundStyle(
                                        selection == option
                                            ? OnboardingTheme.accent
                                            : OnboardingTheme.textPrimary
                                    )

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if option != OnboardingData.yearOfStudyOptions.last {
                            Divider()
                                .padding(.leading, 46)
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
            }
        }
        .opacity(disabled ? 0.35 : 1)
        .animation(.easeOut(duration: 0.3), value: disabled)
        .padding(.bottom, 18)
    }
}

// MARK: - Error Text

struct OnboardingError: View {
    let show: Bool
    let text: String

    var body: some View {
        if show {
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OnboardingTheme.errorColor)
                .padding(.top, -12)
                .padding(.bottom, 12)
        }
    }
}

// MARK: - Checkbox

struct OnboardingCheckbox: View {
    let label: String
    @Binding var isChecked: Bool

    var body: some View {
        Button {
            isChecked.toggle()
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(
                        isChecked ? OnboardingTheme.accent.opacity(0.6) : Color.black.opacity(0.1),
                        lineWidth: 1.5
                    )
                    .background {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(isChecked ? OnboardingTheme.accent.opacity(0.15) : Color.white.opacity(0.4))
                    }
                    .overlay {
                        if isChecked {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(OnboardingTheme.accent)
                        }
                    }
                    .frame(width: 24, height: 24)

                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(red: 60/255, green: 60/255, blue: 67/255).opacity(0.6))
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}

// MARK: - Skip Button

struct SkipButton: View {
    let action: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(action: action) {
                Text("Skip for now")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.black.opacity(0.25))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 16)
    }
}

// MARK: - Row (content + arrow button)

struct OnboardingRow<Content: View>: View {
    let disabled: Bool
    let onNext: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ArrowButton(disabled: disabled, action: onNext)
        }
    }
}
