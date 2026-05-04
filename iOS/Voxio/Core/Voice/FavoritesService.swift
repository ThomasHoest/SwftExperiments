import Combine
import Foundation

@MainActor
class FavoritesService {
    private var cache: [String: [Favorite]] = [:]

    private func fetch(for speaker: Speaker) async -> [Favorite] {
        if let cached = cache[speaker.host] {
            Log.verbose("[Favorites] cache hit for \(speaker.name) (\(cached.count) favorites)")
            return cached
        }
        Log.verbose("[Favorites] fetching favorites from API for \(speaker.name)")
        do {
            let list = try await speaker.getFavorites()
            cache[speaker.host] = list
            Log.info("[Favorites] cached \(list.count) favorites for \(speaker.name): \(list.map(\.displayName))")
            return list
        } catch SpeakerError.httpError(404) {
            cache[speaker.host] = []
            Log.info("[Favorites] \(speaker.name) has no favorites stored (404)")
            return []
        } catch {
            Log.error("[Favorites] fetch failed for \(speaker.name): \(error)")
            return []
        }
    }

    func play(index: Int, on speaker: Speaker) async {
        let list = await fetch(for: speaker)
        guard index >= 1, index <= list.count else {
            Log.info("[Favorites] index \(index) out of range (have \(list.count)) on \(speaker.name)")
            return
        }
        let fav = list[index - 1]
        Log.info("[Favorites] playing #\(index) '\(fav.displayName)' on \(speaker.name)")
        try? await speaker.playFavorite(presetIndex: fav.presetIndex)
    }

    func playDefault(on speaker: Speaker) async {
        let list = await fetch(for: speaker)
        guard let first = list.first else {
            Log.info("[Favorites] no favorites on \(speaker.name)")
            return
        }
        Log.info("[Favorites] playing default '\(first.displayName)' on \(speaker.name)")
        try? await speaker.playFavorite(presetIndex: first.presetIndex)
    }

    func listFavorites(for speaker: Speaker) async -> [String] {
        await fetch(for: speaker).map { $0.displayName }
    }

    /// Resolves a spoken favorite name to the best-matching `Favorite`.
    /// Tries exact match first, then substring containment, then returns nil.
    func resolve(favoriteNamed name: String, for speaker: Speaker) async -> Favorite? {
        let list  = await fetch(for: speaker)
        let lower = name.lowercased()
        if let exact = list.first(where: { $0.displayName.lowercased() == lower }) {
            return exact
        }
        return list.first(where: {
            $0.displayName.lowercased().contains(lower) ||
            lower.contains($0.displayName.lowercased())
        })
    }

    /// Plays a favorite identified by spoken name. Returns `true` on success.
    @discardableResult
    func playNamed(_ name: String, on speaker: Speaker) async -> Bool {
        guard let fav = await resolve(favoriteNamed: name, for: speaker) else {
            Log.info("[Favorites] '\(name)' not found on \(speaker.name)")
            return false
        }
        Log.info("[Favorites] playNamed '\(fav.displayName)' on \(speaker.name)")
        try? await speaker.playFavorite(presetIndex: fav.presetIndex)
        return true
    }

    func favorite(at index: Int, for speaker: Speaker) async -> Favorite? {
        let list = await fetch(for: speaker)
        guard index >= 1, index <= list.count else {
            Log.info("[Favorites] index \(index) out of range (have \(list.count)) on \(speaker.name)")
            return nil
        }
        return list[index - 1]
    }

    func invalidate(for speaker: Speaker) {
        cache.removeValue(forKey: speaker.host)
    }
}
