//
//  Router.swift
//  SwiftExperiments
//
//  Created by Thomas Høst Andersen on 01/12/2025.
//

import SwiftUI
internal import Combine

enum Route: Hashable {
    case home
    case profile(id: Int)
    case settings
}


class Router: ObservableObject {
    @Published var path = NavigationPath()

    func push(_ route: Route) {
        path.append(route)
    }

    func pop() {
        if !path.isEmpty {
            path.removeLast()
        }
    }

    func popToRoot() {
        path = NavigationPath()
    }
}
