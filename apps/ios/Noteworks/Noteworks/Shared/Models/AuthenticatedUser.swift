//
//  AuthenticatedUser.swift
//  Noteworks
//
//  Minimal identity captured at sign-in time. The full profile (name,
//  school, onboarding status, etc.) is hydrated separately into
//  `AppState.profile` via `GET /functions/v1/get-user-profile`.
//

import Foundation

struct AuthenticatedUser: Equatable {
    let id: String
    let email: String
}
