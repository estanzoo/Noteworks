//
//  SchoolAutocompleteField.swift
//  Noteworks
//
//  Shared school picker used in onboarding and Profile → About You.
//  Filters the prefetched `SchoolSearchService` cache as the user types.
//

import SwiftUI

enum SchoolAutocompleteAppearance {
    case onboarding
    case profile
}

struct SchoolAutocompleteField: View {
    @Binding var schoolName: String
    /// Set when the user picks a row from the suggestions dropdown;
    /// cleared whenever the text field is edited manually.
    @Binding var selectedSchoolId: String?
    let disabled: Bool
    @ObservedObject var searchService: SchoolSearchService
    var appearance: SchoolAutocompleteAppearance = .onboarding
    var label: String = "College Name"
    var placeholder: String = "e.g. Royal Academy of Arts"

    @FocusState private var focused: Bool
    @State private var showSuggestions = false
    /// Suppresses the `onChange(of: schoolName)` clear-selection side
    /// effect while we programmatically write the picked school name.
    @State private var isApplyingSelection = false

    var body: some View {
        VStack(alignment: .leading, spacing: appearance == .profile ? 8 : 6) {
            Text(appearance == .profile ? label.uppercased() : label)
                .font(labelFont)
                .tracking(labelTracking)
                .foregroundStyle(labelColor)

            TextField(placeholder, text: $schoolName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(fieldFont)
                .foregroundStyle(fieldTextColor)
                .padding(.horizontal, fieldHorizontalPadding)
                .padding(.vertical, fieldVerticalPadding)
                .background(fieldBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            focused && !disabled ? focusedBorderColor : idleBorderColor,
                            lineWidth: focusedBorderWidth
                        )
                }
                .shadow(color: focused && !disabled ? focusShadowColor : .clear, radius: focusShadowRadius)
                .focused($focused)
                .disabled(disabled)
                .onChange(of: schoolName) { _, newValue in
                    searchService.query = newValue
                    searchService.search()
                    showSuggestions = true
                    if isApplyingSelection {
                        isApplyingSelection = false
                    } else if selectedSchoolId != nil {
                        selectedSchoolId = nil
                    }
                }
                .onChange(of: focused) { _, isFocused in
                    if isFocused && schoolName.count >= 2 {
                        showSuggestions = true
                    }
                }

            if showSuggestions && !disabled && !searchService.results.isEmpty && focused {
                suggestionsList
            }

            if searchService.isLoading && focused && schoolName.count >= 2 {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Searching schools...")
                        .font(.system(size: 13))
                        .foregroundStyle(secondaryTextColor)
                }
                .padding(.top, 4)
            }
        }
        .opacity(disabled ? 0.35 : 1)
        .animation(.easeOut(duration: 0.3), value: disabled)
        .padding(.bottom, appearance == .onboarding ? 18 : 0)
    }

    private var suggestionsList: some View {
        VStack(spacing: 0) {
            ForEach(searchService.results) { school in
                Button {
                    isApplyingSelection = true
                    schoolName = school.name
                    selectedSchoolId = school.id
                    showSuggestions = false
                    focused = false
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "building.columns")
                            .font(.system(size: appearance == .profile ? 12 : 14))
                            .foregroundStyle(accentColor)
                            .frame(width: 28, height: 28)
                            .background(accentColor.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 7))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(school.name)
                                .font(.system(size: appearance == .profile ? 14 : 15, weight: .medium))
                                .foregroundStyle(fieldTextColor)
                                .lineLimit(1)

                            if let location = school.location, !location.isEmpty {
                                Text(location)
                                    .font(.system(size: 12))
                                    .foregroundStyle(secondaryTextColor)
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
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(dropdownBorderColor, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.easeOut(duration: 0.15), value: searchService.results.count)
        .zIndex(1)
    }

    // MARK: - Appearance tokens

    private var labelFont: Font {
        switch appearance {
        case .onboarding:
            return .system(size: 13, weight: .semibold)
        case .profile:
            return .system(size: 12, weight: .semibold)
        }
    }

    private var labelTracking: CGFloat {
        appearance == .profile ? 0.04 * 12 : 0
    }

    private var labelColor: Color {
        switch appearance {
        case .onboarding: return OnboardingTheme.textLabel
        case .profile:    return ProfileTheme.textMuted
        }
    }

    private var fieldFont: Font {
        .system(size: appearance == .profile ? 14 : 17)
    }

    private var fieldTextColor: Color {
        switch appearance {
        case .onboarding: return OnboardingTheme.textPrimary
        case .profile:    return ProfileTheme.textPrimary
        }
    }

    private var secondaryTextColor: Color {
        switch appearance {
        case .onboarding: return OnboardingTheme.textSecondary
        case .profile:    return ProfileTheme.textSecondary
        }
    }

    private var accentColor: Color {
        switch appearance {
        case .onboarding: return OnboardingTheme.accent
        case .profile:    return ProfileTheme.accent
        }
    }

    private var fieldHorizontalPadding: CGFloat {
        appearance == .profile ? 14 : 16
    }

    private var fieldVerticalPadding: CGFloat {
        appearance == .profile ? 11 : 14
    }

    private var fieldBackground: some ShapeStyle {
        switch appearance {
        case .onboarding:
            return AnyShapeStyle(disabled ? Color.black.opacity(0.03) : OnboardingTheme.glassBg)
        case .profile:
            return AnyShapeStyle(Color.white.opacity(0.5))
        }
    }

    private var idleBorderColor: Color {
        switch appearance {
        case .onboarding: return OnboardingTheme.glassBorder
        case .profile:    return Color.black.opacity(0.06)
        }
    }

    private var focusedBorderColor: Color {
        accentColor.opacity(appearance == .profile ? 0.5 : 0.6)
    }

    private var focusedBorderWidth: CGFloat {
        appearance == .profile ? 1.5 : 1.5
    }

    private var focusShadowColor: Color {
        accentColor.opacity(appearance == .profile ? 0.16 : 0.12)
    }

    private var focusShadowRadius: CGFloat {
        appearance == .profile ? 3 : 6
    }

    private var dropdownBorderColor: Color {
        switch appearance {
        case .onboarding: return OnboardingTheme.glassBorder
        case .profile:    return ProfileTheme.glassBorder
        }
    }
}
