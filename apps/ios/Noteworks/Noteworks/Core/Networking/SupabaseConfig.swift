//
//  SupabaseConfig.swift
//  Noteworks
//
//  Created on 2026-03-18.
//

import Foundation

enum SupabaseConfig {
    static let baseURL = "https://canhewvuprjwmpopcloj.supabase.co"
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNhbmhld3Z1cHJqd21wb3BjbG9qIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njk5NjI1NDgsImV4cCI6MjA4NTUzODU0OH0.jp-RcV0gxHHozwgL4pOlNkwUsjUbzoZTJ6MRJH4Oo8Y"

    static let functionsBase = "\(baseURL)/functions/v1"

    static var submitOnboardingURL: URL {
        URL(string: "\(functionsBase)/submit-onboarding")!
    }

    static func getSchoolsURL(search: String, page: Int = 1, pageSize: Int = 10) -> URL {
        var components = URLComponents(string: "\(functionsBase)/get-schools")!
        var items = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "pageSize", value: "\(pageSize)"),
        ]
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            items.append(URLQueryItem(name: "search", value: trimmed))
        }
        components.queryItems = items
        return components.url!
    }

    static func uploadNotePDFURL(noteId: String, filename: String? = nil) -> URL {
        var components = URLComponents(string: "\(functionsBase)/upload-note-pdf")!
        var items = [URLQueryItem(name: "note_id", value: noteId)]
        if let filename { items.append(URLQueryItem(name: "filename", value: filename)) }
        components.queryItems = items
        return components.url!
    }

    static func getNotePDFURL(noteId: String, expiresIn: Int? = nil) -> URL {
        var components = URLComponents(string: "\(functionsBase)/get-note-pdf-url")!
        var items = [URLQueryItem(name: "note_id", value: noteId)]
        if let expiresIn { items.append(URLQueryItem(name: "expires_in", value: "\(expiresIn)")) }
        components.queryItems = items
        return components.url!
    }
}
