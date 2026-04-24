//
//  Item.swift
//  SwiftExperiments
//
//  Created by Thomas Høst Andersen on 27/11/2025.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
