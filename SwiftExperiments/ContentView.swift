//
//  ContentView.swift
//  SwiftExperiments
//
//  Created by Thomas Høst Andersen on 27/11/2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var router = Router()
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $router.path) {
            VStack {
                Button("Go to Detail") {
                    router.navigate(to: .textView)
                }
            }
            .navigationDestination(for: Route.self) { route in
                                switch route {
                                case .textView:
                                    TextView()
                                case .settings:
                                    TextView()
                                }
                            }
        }
    }
}

