//
//  Item.swift
//  HarvestPlus
//
//  Created by Razvan Politic on 14/04/2026.
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
