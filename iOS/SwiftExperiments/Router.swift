//
//  Router.swift
//  SwiftExperiments
//
//  Created by Thomas Høst Andersen on 01/12/2025.
//

import SwiftUI
internal import Combine

enum Route: Hashable {
    case transcriptionView
    case settings
}


class Router: ObservableObject {
    @Published var path = NavigationPath()

    // Go to a new route
    func navigate(to route: Route) {
        path.append(route)
    }
    
    // Return to previous page
    func navigateBack() {
        path.removeLast()
    }
    
    // Return to home page
    func navigateToRoot() {
        path.removeLast(path.count)
    }
    
    // Go back to a specific view
    func popToView(count: Int) {
        path.removeLast(count)
    }
}
