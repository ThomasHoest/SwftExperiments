import Foundation

@MainActor
class FavoritesService {
    private var cache: [String: [Favorite]] = [:]

    private func fetch(for speaker: Speaker) async -> [Favorite] {
        if let cached = cache[speaker.host] { return cached }
        guard let list = try? await speaker.getFavorites() else { return [] }
        cache[speaker.host] = list
        Log.info("[Favorites] cached \(list.count) favorites for \(speaker.name)")
        return list
    }

    func play(index: Int, on speaker: Speaker) async {
        let list = await fetch(for: speaker)
        guard index >= 1, index <= list.count else {
            Log.info("[Favorites] index \(index) out of range (have \(list.count)) on \(speaker.name)")
            return
        }
        let fav = list[index - 1]
        Log.info("[Favorites] playing #\(index) '\(fav.displayName)' on \(speaker.name)")
        try? await speaker.playFavorite(id: fav.id)
    }

    func playDefault(on speaker: Speaker) async {
        let list = await fetch(for: speaker)
        guard let first = list.first else {
            Log.info("[Favorites] no favorites on \(speaker.name)")
            return
        }
        Log.info("[Favorites] playing default '\(first.displayName)' on \(speaker.name)")
        try? await speaker.playFavorite(id: first.id)
    }

    func listFavorites(for speaker: Speaker) async -> [String] {
        await fetch(for: speaker).map { $0.displayName }
    }

    func invalidate(for speaker: Speaker) {
        cache.removeValue(forKey: speaker.host)
    }
}
