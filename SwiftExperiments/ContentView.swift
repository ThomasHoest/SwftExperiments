//
//  ContentView.swift
//  SwiftExperiments
//
//  Created by Thomas Høst Andersen on 27/11/2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @EnvironmentObject var router : Router
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: router.path) {
            VStack {
                Button("Go to Detail") {
                    path.append("detail")
                }
            }
            .navigationDestination(for: String.self) { value in
                if value == "detail" {
                    TextView()
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
