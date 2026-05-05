import CoreData

// IMPORTANT: The Voxio.xcdatamodeld bundle must be manually added to the Xcode project.
// In Xcode: File → Add Files to "Voxio" → select iOS/Voxio/Core/Persistence/Voxio.xcdatamodeld
// Ensure the Voxio app target membership checkbox is ticked.

final class PersistenceController {
    static let shared = PersistenceController()
    static let preview = PersistenceController(inMemory: true)

    let container: NSPersistentContainer

    var viewContext: NSManagedObjectContext { container.viewContext }

    func newBackgroundContext() -> NSManagedObjectContext {
        container.newBackgroundContext()
    }

    private init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "Voxio")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error { fatalError("Core Data error: \(error)") }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }
}
