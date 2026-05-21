//
//  CreditsStore.swift
//  Noteworks
//
//  Local-first credit balance per signed-in user. Beta defaults every
//  account to Pro with 120 starter credits; AI features spend against
//  this balance and refuse when funds are insufficient.
//

import Foundation
import Combine

// MARK: - Tier

enum SubscriptionTier: String, Codable, Equatable {
    case free
    case pro

    var displayPlanName: String {
        switch self {
        case .free: return "NoteWorks Free"
        case .pro:  return "NoteWorks Pro"
        }
    }

    /// Credits granted when a brand-new account snapshot is created.
    var initialCredits: Int {
        switch self {
        case .free: return 0
        case .pro:  return 120
        }
    }
}

// MARK: - Features & pricing

enum CreditFeature: String, Codable, CaseIterable {
    case gapDetection
    case smartOrganization

    var usageLabel: String {
        switch self {
        case .gapDetection:      return "Gap Detection"
        case .smartOrganization: return "Smart Organization"
        }
    }
}

enum CreditPricing {
    static func gapDetection(
        yourNotePages: Int,
        peerNoteCount: Int,
        classMaterialCount: Int
    ) -> Int {
        let yourNotes = max(4, yourNotePages / 4 + 4)
        let others = peerNoteCount * 6
        let materials = classMaterialCount * 3
        return yourNotes + others + materials
    }

    static func smartOrganization(pageCount: Int) -> Int {
        max(4, min(12, pageCount + 3))
    }
}

// MARK: - Ledger

struct CreditLedgerEntry: Codable, Equatable, Identifiable {
    let id: String
    var label: String
    var detail: String
    var delta: Int
    var date: Date

    init(id: String = UUID().uuidString, label: String, detail: String, delta: Int, date: Date = Date()) {
        self.id = id
        self.label = label
        self.detail = detail
        self.delta = delta
        self.date = date
    }
}

private struct CreditAccountSnapshot: Codable {
    var tier: SubscriptionTier
    var balance: Int
    var history: [CreditLedgerEntry]
    var usageTotals: [String: Int]
}

// MARK: - Store

@MainActor
final class CreditsStore: ObservableObject {

    static let shared = CreditsStore()

    @Published private(set) var tier: SubscriptionTier = .pro
    @Published private(set) var balance: Int = 0
    @Published private(set) var accountRevision: Int = 0

    private var history: [CreditLedgerEntry] = []
    private var usageTotals: [String: Int] = [:]
    private var activeUserId: String?
    private var saveTask: Task<Void, Never>?

    private init() {}

    // MARK: - Lifecycle

    func activate(userId: String) {
        guard activeUserId != userId else { return }
        activeUserId = userId
        if let snapshot = loadSnapshot(for: userId) {
            apply(snapshot)
        } else {
            seedProAccount()
            saveImmediately()
        }
        bumpRevision()
    }

    func deactivate() {
        flushSave()
        activeUserId = nil
        tier = .pro
        balance = 0
        history = []
        usageTotals = [:]
    }

    // MARK: - Queries

    func canAfford(_ amount: Int) -> Bool {
        amount <= 0 || balance >= amount
    }

    var insufficientCreditsMessage: String {
        "You don't have enough credits for this feature."
    }

    // MARK: - Spend

    @discardableResult
    func spend(
        _ amount: Int,
        feature: CreditFeature,
        label: String,
        detail: String
    ) -> Bool {
        guard amount > 0 else { return true }
        guard balance >= amount else { return false }

        balance -= amount
        usageTotals[feature.rawValue, default: 0] += amount
        history.insert(
            CreditLedgerEntry(label: label, detail: detail, delta: -amount),
            at: 0
        )
        trimHistory()
        saveDebounced()
        bumpRevision()
        return true
    }

    // MARK: - Profile mapping

    func profileCredits() -> Credits {
        Credits(
            balance: balance,
            history: history.prefix(20).enumerated().map { index, entry in
                CreditEntry(
                    id: index + 1,
                    label: entry.label,
                    detail: entry.detail,
                    delta: entry.delta
                )
            },
            usage: CreditFeature.allCases.map { feature in
                let spent = usageTotals[feature.rawValue, default: 0]
                return CreditUsage(
                    id: featureUsageId(feature),
                    label: feature.usageLabel,
                    used: spent,
                    total: max(spent, tier.initialCredits),
                    detail: spent == 0 ? "No usage yet" : "Credits spent on \(feature.usageLabel.lowercased())"
                )
            }
        )
    }

    func profileSubscription() -> Subscription {
        Subscription(
            plan: tier.displayPlanName,
            status: "Active",
            renewsOn: tier == .pro ? "Monthly · 120 credits" : ""
        )
    }

    // MARK: - Private

    private func seedProAccount() {
        tier = .pro
        balance = SubscriptionTier.pro.initialCredits
        history = [
            CreditLedgerEntry(
                label: "Pro welcome credits",
                detail: "Starting balance for NoteWorks Pro",
                delta: +balance
            )
        ]
        usageTotals = [:]
    }

    private func apply(_ snapshot: CreditAccountSnapshot) {
        tier = snapshot.tier
        balance = max(0, snapshot.balance)
        history = snapshot.history
        usageTotals = snapshot.usageTotals
    }

    private func featureUsageId(_ feature: CreditFeature) -> Int {
        switch feature {
        case .gapDetection: return 1
        case .smartOrganization: return 2
        }
    }

    private func trimHistory() {
        if history.count > 100 {
            history = Array(history.prefix(100))
        }
    }

    private func bumpRevision() {
        accountRevision &+= 1
    }

    // MARK: - Persistence

    private func snapshotFileURL(for userId: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = docs.appendingPathComponent("credits", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder.appendingPathComponent("\(userId).json")
    }

    private func loadSnapshot(for userId: String) -> CreditAccountSnapshot? {
        let url = snapshotFileURL(for: userId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CreditAccountSnapshot.self, from: data)
    }

    private func saveDebounced() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            saveImmediately()
        }
    }

    private func saveImmediately() {
        guard let userId = activeUserId else { return }
        let snapshot = CreditAccountSnapshot(
            tier: tier,
            balance: balance,
            history: history,
            usageTotals: usageTotals
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: snapshotFileURL(for: userId), options: [.atomic])
    }

    private func flushSave() {
        saveTask?.cancel()
        saveImmediately()
    }
}
