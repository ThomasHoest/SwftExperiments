import Foundation
import Observation

/// Maintains a lightweight navigation stack so that every incident report includes
/// the sequence of screens the user visited before the error occurred.
///
/// Views call `push(_:)` in `.onAppear` and `pop()` in `.onDisappear`.
/// `IncidentReporter` reads `currentPath` when assembling a payload.
@MainActor
@Observable
public final class BreadcrumbTracker {

    // MARK: - Singleton

    public static let shared = BreadcrumbTracker()

    // MARK: - State

    /// Current navigation stack, oldest entry first.
    private(set) public var stack: [String] = []

    // MARK: - Derived

    /// Returns the stack joined with " > ", or "" when empty.
    public var currentPath: String {
        stack.joined(separator: " > ")
    }

    // MARK: - Init

    private init() {}

    // MARK: - Mutations

    /// Appends `screenName` to the stack.
    public func push(_ screenName: String) {
        stack.append(screenName)
    }

    /// Removes the last element. No-op if the stack is already empty.
    public func pop() {
        guard !stack.isEmpty else { return }
        stack.removeLast()
    }

    /// Empties the stack. Intended for use by tests only.
    public func reset() {
        stack.removeAll()
    }
}
