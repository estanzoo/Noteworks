//
//  OnboardingData.swift
//  Noteworks
//
//  Created on 2026-04-02.
//

import Foundation

class OnboardingData: ObservableObject {
    // OAuth
    @Published var isOAuthUser = false
    @Published var schoolEmail = ""

    // Step 1: Sign Up
    @Published var name = ""
    @Published var email = ""
    @Published var password = ""
    @Published var verifyPassword = ""

    // Step 2: Verify Email (Supabase email OTP is typically 6 digits)
    @Published var verificationCode = ["", "", "", "", "", ""]

    // Step 3: College
    @Published var college = ""
    /// `schools.id` of the row the user picked from the autocomplete. We
    /// require this to be set before letting the user advance: the
    /// onboarding flow no longer accepts free-form college names, so a
    /// non-empty `college` string with `selectedSchoolId == nil` means
    /// the user typed something we don't recognise.
    @Published var selectedSchoolId: String?
    /// Selected label from `yearOfStudyOptions`, or `nil` until the user picks.
    @Published var yearOfStudySelection: String?
    /// When selection is "Other", optional detail (empty → stored as "Other").
    @Published var yearOfStudyOtherDetail = ""
    @Published var notAStudent = false

    /// Dropdown options (stored as text for backend / `year_of_study`).
    static let yearOfStudyOther = "Other"
    static let yearOfStudyOptions = [
        "Freshman (Year 1)",
        "Sophomore (Year 2)",
        "Junior (Year 3)",
        "Senior (Year 4)",
        yearOfStudyOther
    ]

    // Step 4: Major
    @Published var school = ""
    @Published var major = ""
    @Published var undeclared = false

    // Step 5: Interests
    @Published var interests: [String] = []
    @Published var customInterests: [String] = []

    static let presetInterests = [
        "AI", "Design", "Soccer", "Football", "Basketball",
        "Gaming", "Travel", "Mindfulness", "Coding", "Stock",
        "Crypto", "Vlogging"
    ]

    // MARK: - Validation
    //
    // Each step view drives its own "did the user try Next yet?" state and
    // surfaces the messages below as inline errors. The `is*Valid` flags
    // are kept around for any caller that just needs a yes/no answer (the
    // step views themselves now rely on the granular helpers).

    /// Loose email-shape regex — matches what `submit-onboarding` accepts
    /// (`^[^\s@]+@[^\s@]+\.[^\s@]+$`). Catches the obvious "no @", "no
    /// dot", "trailing space" mistakes without trying to be RFC-correct.
    private static let emailRegex = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#

    private static func looksLikeEmail(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.range(of: emailRegex, options: .regularExpression) != nil
    }

    // Step 1 — Sign Up

    var signUpNameError: String? {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Please enter your name."
            : nil
    }

    var signUpEmailError: String? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Please enter your email." }
        if !Self.looksLikeEmail(trimmed) { return "Enter a valid email address." }
        return nil
    }

    var signUpPasswordError: String? {
        if password.isEmpty { return "Please choose a password." }
        if password.count < 8 { return "Password must be at least 8 characters." }
        return nil
    }

    var signUpVerifyPasswordError: String? {
        if verifyPassword.isEmpty { return "Re-enter your password." }
        if password != verifyPassword { return "Passwords don't match." }
        return nil
    }

    var isSignUpValid: Bool {
        signUpNameError == nil
            && signUpEmailError == nil
            && signUpPasswordError == nil
            && signUpVerifyPasswordError == nil
    }

    // Step 2 — Verify Email

    var verifyCodeError: String? {
        let digits = verificationCode.joined()
        if digits.isEmpty { return "Enter the 6-digit code we sent to your email." }
        if digits.count < 6 || !digits.allSatisfy({ $0.isNumber }) {
            return "Enter all 6 digits of the verification code."
        }
        return nil
    }

    var isVerifyValid: Bool { verifyCodeError == nil }

    // Step 3 — College

    /// Optional school-email error. Only enforced when the field is
    /// visible (OAuth users), since email-password sign-ups already
    /// captured the email up-front.
    var collegeSchoolEmailError: String? {
        guard isOAuthUser else { return nil }
        let trimmed = schoolEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Please enter your school email." }
        if !Self.looksLikeEmail(trimmed) { return "Enter a valid school email." }
        return nil
    }

    var collegeNameError: String? {
        guard !notAStudent else { return nil }
        let trimmed = college.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Please choose your college." }
        if selectedSchoolId == nil { return "Please pick a school from the list." }
        return nil
    }

    var yearOfStudyError: String? {
        guard !notAStudent else { return nil }
        return yearOfStudySelection == nil ? "Please pick your year of study." : nil
    }

    var isCollegeValid: Bool {
        collegeSchoolEmailError == nil
            && collegeNameError == nil
            && yearOfStudyError == nil
    }

    /// Convenience used by the inline error directly under the college
    /// field — true the moment the user has typed something we can't
    /// match, even before they tap Next.
    var hasUnrecognisedCollege: Bool {
        guard !notAStudent else { return false }
        let trimmed = college.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && selectedSchoolId == nil
    }

    /// Maps UI year selection to `year_of_graduation` (integer) for `submit-onboarding`.
    var resolvedYearOfGraduation: Int {
        if notAStudent { return 2100 }
        let cal = Calendar.current
        let y = cal.component(.year, from: Date())
        guard let sel = yearOfStudySelection else { return y + 4 }
        if sel == Self.yearOfStudyOther {
            let t = yearOfStudyOtherDetail.trimmingCharacters(in: .whitespacesAndNewlines)
            if let n = Int(t), (2000...2100).contains(n) { return n }
            return y + 4
        }
        switch sel {
        case "Freshman (Year 1)": return y + 4
        case "Sophomore (Year 2)": return y + 3
        case "Junior (Year 3)": return y + 2
        case "Senior (Year 4)": return y + 1
        default: return y + 4
        }
    }

    /// `school_affiliation` for submit-onboarding (required non-empty string).
    var schoolAffiliationForSubmit: String {
        notAStudent
            ? "Not a college student"
            : college.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Step 4 — Major

    var majorFacultyError: String? {
        guard !undeclared else { return nil }
        return school.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Please enter your faculty."
            : nil
    }

    var majorNameError: String? {
        guard !undeclared else { return nil }
        return major.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Please enter your major."
            : nil
    }

    var isMajorValid: Bool {
        majorFacultyError == nil && majorNameError == nil
    }

    // Step 5 — Interests

    var interestsError: String? {
        (interests.isEmpty && customInterests.isEmpty)
            ? "Pick at least one topic you're interested in."
            : nil
    }

    var isInterestsValid: Bool { interestsError == nil }

    /// Course-code-shaped list submitted to `submit-onboarding`.
    ///
    /// The onboarding UI today collects free-form interests/tags; the API
    /// accepts up to 50 strings of at most 50 characters each
    /// (`docs/Frontend_Auth_and_Onboarding_Guide.md` step 6 table). We map
    /// preset + custom interests through, trim whitespace, drop empties,
    /// de-duplicate case-insensitively, and clamp lengths. Later product
    /// work can replace this with a real course picker — the wire format
    /// stays the same.
    var selectedCourseCodes: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for raw in interests + customInterests {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let clipped = String(trimmed.prefix(50))
            let key = clipped.lowercased()
            if seen.insert(key).inserted {
                result.append(clipped)
            }
            if result.count == 50 { break }
        }
        return result
    }
}
