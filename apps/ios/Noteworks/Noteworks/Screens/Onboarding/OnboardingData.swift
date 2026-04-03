//
//  OnboardingData.swift
//  Noteworks
//
//  Created on 2026-04-02.
//

import Foundation

class OnboardingData: ObservableObject {
    // Step 1: Sign Up
    @Published var name = ""
    @Published var email = ""
    @Published var password = ""
    @Published var verifyPassword = ""

    // Step 2: Verify Email (Supabase email OTP is typically 6 digits)
    @Published var verificationCode = ["", "", "", "", "", ""]

    // Step 3: College
    @Published var college = ""
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

    // Validation

    var isSignUpValid: Bool {
        !name.isEmpty && !email.isEmpty && password.count >= 8 && password == verifyPassword
    }

    var isVerifyValid: Bool {
        verificationCode.allSatisfy { !$0.isEmpty }
    }

    var isCollegeValid: Bool {
        notAStudent || (!college.isEmpty && yearOfStudySelection != nil)
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

    var isMajorValid: Bool {
        undeclared || (!school.isEmpty && !major.isEmpty)
    }

    var isInterestsValid: Bool {
        !interests.isEmpty || !customInterests.isEmpty
    }
}
