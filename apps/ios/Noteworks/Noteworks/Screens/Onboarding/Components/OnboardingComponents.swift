//
//  OnboardingComponents.swift
//  Noteworks
//
//  Created on 2026-04-02.
//

import SwiftUI
import UIKit

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
                // `.top` made the dismiss animation slide upward out of the card.
                // Options sit below the field — fade/slide out toward the bottom only.
                .transition(.opacity.combined(with: .move(edge: .bottom)))
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

// MARK: - OTP Input

/// Six-box verification code entry.
/// - iPhone: native text fields + system number pad docked at the bottom.
/// - iPad: native text fields + shared bottom number pad (replaces the
///   floating system keyboard so the pad always sits in the bottom slot).
struct OnboardingOTPInput: View {
    @Binding var digits: [String]

    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            OnboardingOTPInputPad(digits: $digits)
        } else {
            OnboardingOTPInputPhone(digits: $digits)
        }
    }
}

// MARK: - iPhone

private struct OnboardingOTPInputPhone: View {
    @Binding var digits: [String]
    @FocusState private var focusedIndex: Int?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { index in
                TextField("", text: digitBinding(at: index))
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.center)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(OnboardingTheme.textPrimary)
                    .frame(width: 48, height: 68)
                    .background(OnboardingTheme.glassBg)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
                    .overlay { otpBorder(isFocused: focusedIndex == index, hasDigit: !digits[index].isEmpty) }
                    .focused($focusedIndex, equals: index)
                    .textContentType(index == 0 ? .oneTimeCode : nil)
                    .onChange(of: digits[index]) { oldValue, newValue in
                        handleDigitChange(at: index, oldValue: oldValue, newValue: newValue)
                    }
            }
        }
    }

    private func digitBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard index < digits.count else { return "" }
                return digits[index]
            },
            set: { newValue in
                guard index < digits.count else { return }
                digits[index] = newValue
            }
        )
    }

    private func handleDigitChange(at index: Int, oldValue: String, newValue: String) {
        let filtered = newValue.filter(\.isNumber)
        if filtered != newValue {
            digits[index] = filtered
            return
        }

        if filtered.count > 1 {
            applyPastedDigits(filtered)
            return
        }

        if filtered.count == 1, oldValue.isEmpty, index < digits.count - 1 {
            Task { @MainActor in
                await Task.yield()
                focusedIndex = index + 1
            }
            return
        }

        if filtered.isEmpty {
            if !oldValue.isEmpty {
                if index > 0 { scheduleFocus(index - 1) }
                return
            }
            if index > 0 {
                let previous = index - 1
                digits[previous] = ""
                scheduleFocus(previous)
            }
        }
    }

    private func applyPastedDigits(_ code: String) {
        for offset in digits.indices { digits[offset] = "" }
        for (offset, character) in code.prefix(6).enumerated() {
            digits[offset] = String(character)
        }
        scheduleFocus(min(code.count, digits.count - 1))
    }

    private func scheduleFocus(_ index: Int) {
        DispatchQueue.main.async { focusedIndex = index }
    }
}

// MARK: - iPad

private struct OnboardingOTPInputPad: View {
    @Binding var digits: [String]
    @StateObject private var controller = OTPPadController()
    @State private var focusedIndex = 0

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { index in
                OTPPadDigitCell(
                    index: index,
                    controller: controller,
                    isFocused: focusedIndex == index
                )
                .frame(width: 48, height: 68)
            }
        }
        .onAppear {
            controller.wire(
                getDigits: { digits },
                setDigits: { digits = $0 },
                setFocusedIndex: { focusedIndex = $0 }
            )
        }
    }
}

private final class OTPPadController: ObservableObject {
    private var getDigits: () -> [String] = { [] }
    private var setDigits: ([String]) -> Void = { _ in }
    private var setFocusedIndex: (Int) -> Void = { _ in }
    private var fields: [Int: UITextField] = [:]
    private var currentDigits: [String] = Array(repeating: "", count: 6)
    var focusedIndex = 0

    private(set) lazy var numberPad: OTPBottomNumberPad = {
        let pad = OTPBottomNumberPad()
        pad.onDigit = { [weak self] digit in self?.insertDigit(digit) }
        pad.onDelete = { [weak self] in self?.deleteDigit() }
        return pad
    }()

    func wire(
        getDigits: @escaping () -> [String],
        setDigits: @escaping ([String]) -> Void,
        setFocusedIndex: @escaping (Int) -> Void
    ) {
        self.getDigits = getDigits
        self.setDigits = setDigits
        self.setFocusedIndex = setFocusedIndex
        currentDigits = getDigits()
        if currentDigits.count < 6 {
            currentDigits.append(contentsOf: Array(repeating: "", count: 6 - currentDigits.count))
        }
        syncFields(currentDigits)
    }

    func register(field: UITextField, at index: Int) {
        fields[index] = field
    }

    func insertDigit(_ digit: String) {
        guard focusedIndex >= 0, focusedIndex < currentDigits.count else { return }

        let wasEmpty = currentDigits[focusedIndex].isEmpty
        currentDigits[focusedIndex] = digit
        setDigits(currentDigits)
        syncFields(currentDigits)

        guard wasEmpty, focusedIndex < currentDigits.count - 1 else { return }
        let nextIndex = focusedIndex + 1
        DispatchQueue.main.async { [weak self] in
            self?.focus(at: nextIndex)
        }
    }

    func deleteDigit() {
        guard focusedIndex >= 0, focusedIndex < currentDigits.count else { return }

        if !currentDigits[focusedIndex].isEmpty {
            currentDigits[focusedIndex] = ""
            setDigits(currentDigits)
            syncFields(currentDigits)
            if focusedIndex > 0 {
                let previous = focusedIndex - 1
                DispatchQueue.main.async { [weak self] in
                    self?.focus(at: previous)
                }
            }
            return
        }

        guard focusedIndex > 0 else { return }
        let previous = focusedIndex - 1
        currentDigits[previous] = ""
        setDigits(currentDigits)
        syncFields(currentDigits)
        DispatchQueue.main.async { [weak self] in
            self?.focus(at: previous)
        }
    }

    func applyPastedDigits(_ incoming: String, startingAt index: Int) {
        var writeIndex = index
        for character in incoming.prefix(6) {
            guard writeIndex < currentDigits.count else { break }
            currentDigits[writeIndex] = String(character)
            writeIndex += 1
        }
        setDigits(currentDigits)
        syncFields(currentDigits)
        let target = min(writeIndex, currentDigits.count - 1)
        DispatchQueue.main.async { [weak self] in
            self?.focus(at: target)
        }
    }

    func focus(at index: Int) {
        focusedIndex = index
        setFocusedIndex(index)
        DispatchQueue.main.async { [weak self] in
            self?.fields[index]?.becomeFirstResponder()
        }
    }

    private func syncFields(_ digits: [String]) {
        objectWillChange.send()
        for (index, field) in fields {
            field.text = index < digits.count ? digits[index] : ""
        }
    }

    func notifyFocus(_ index: Int) {
        focusedIndex = index
        setFocusedIndex(index)
    }

    func digit(at index: Int) -> String {
        guard index < currentDigits.count else { return "" }
        return currentDigits[index]
    }
}

private struct OTPPadDigitCell: UIViewRepresentable {
    let index: Int
    let controller: OTPPadController
    let isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(index: index, controller: controller)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.textAlignment = .center
        field.font = .systemFont(ofSize: 24, weight: .semibold)
        field.textColor = UIColor(red: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1)
        field.tintColor = UIColor(red: 94 / 255, green: 173 / 255, blue: 211 / 255, alpha: 1)
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        field.layer.cornerRadius = 16
        field.layer.borderWidth = 1.5
        field.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        if index == 0 { field.textContentType = .oneTimeCode }
        // Replace the floating iPad system keyboard with the bottom slot pad.
        field.inputView = controller.numberPad
        controller.register(field: field, at: index)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.index = index
        controller.register(field: uiView, at: index)
        let value = controller.digit(at: index)
        if uiView.text != value {
            uiView.text = value
        }
        updateBorder(for: uiView, value: value)
    }

    private func updateBorder(for field: UITextField, value: String) {
        if isFocused {
            field.layer.borderColor = UIColor(red: 94 / 255, green: 173 / 255, blue: 211 / 255, alpha: 0.9).cgColor
        } else if !value.isEmpty {
            field.layer.borderColor = UIColor(red: 94 / 255, green: 173 / 255, blue: 211 / 255, alpha: 0.6).cgColor
        } else {
            field.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var index: Int
        let controller: OTPPadController

        init(index: Int, controller: OTPPadController) {
            self.index = index
            self.controller = controller
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            controller.notifyFocus(index)
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            controller.notifyFocus(index)

            if string.isEmpty {
                controller.deleteDigit()
                textField.text = controller.digit(at: index)
                return false
            }

            let incoming = string.filter(\.isNumber)
            guard !incoming.isEmpty else { return false }

            if incoming.count > 1 {
                controller.applyPastedDigits(incoming, startingAt: index)
            } else {
                controller.insertDigit(incoming)
            }
            textField.text = controller.digit(at: index)
            return false
        }
    }
}

// MARK: - Bottom Number Pad (iPad keyboard slot)

private final class OTPBottomNumberPad: UIInputView {
    var onDigit: ((String) -> Void)?
    var onDelete: (() -> Void)?

    private let rows: [[PadKey]] = [
        [.digit("1"), .digit("2"), .digit("3")],
        [.digit("4"), .digit("5"), .digit("6")],
        [.digit("7"), .digit("8"), .digit("9")],
        [.spacer, .digit("0"), .delete],
    ]

    init() {
        super.init(
            frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 291),
            inputViewStyle: .keyboard
        )
        backgroundColor = UIColor.systemGray4
        setupButtons()
        allowsSelfSizing = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 291)
    }

    private func setupButtons() {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])

        for row in rows {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.spacing = 8
            rowStack.distribution = .fillEqually
            for key in row {
                rowStack.addArrangedSubview(makeButton(for: key))
            }
            stack.addArrangedSubview(rowStack)
        }
    }

    private func makeButton(for key: PadKey) -> UIView {
        switch key {
        case .spacer:
            return UIView()
        case .digit(let value):
            let button = UIButton(type: .system)
            button.setTitle(value, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 28, weight: .regular)
            button.setTitleColor(.label, for: .normal)
            button.backgroundColor = .white
            button.layer.cornerRadius = 8
            button.layer.shadowColor = UIColor.black.cgColor
            button.layer.shadowOpacity = 0.12
            button.layer.shadowRadius = 0
            button.layer.shadowOffset = CGSize(width: 0, height: 1)
            button.heightAnchor.constraint(equalToConstant: 54).isActive = true
            button.addAction(UIAction { [weak self] _ in self?.onDigit?(value) }, for: .touchUpInside)
            return button
        case .delete:
            let button = UIButton(type: .system)
            button.setImage(UIImage(systemName: "delete.backward"), for: .normal)
            button.tintColor = .label
            button.backgroundColor = .clear
            button.heightAnchor.constraint(equalToConstant: 54).isActive = true
            button.addAction(UIAction { [weak self] _ in self?.onDelete?() }, for: .touchUpInside)
            return button
        }
    }

    private enum PadKey {
        case digit(String)
        case delete
        case spacer
    }
}

// MARK: - Shared OTP chrome

@ViewBuilder
private func otpBorder(isFocused: Bool, hasDigit: Bool) -> some View {
    RoundedRectangle(cornerRadius: 16)
        .strokeBorder(
            isFocused
                ? OnboardingTheme.accent.opacity(0.9)
                : hasDigit
                    ? OnboardingTheme.accent.opacity(0.6)
                    : OnboardingTheme.glassBorder,
            lineWidth: 1.5
        )
}
