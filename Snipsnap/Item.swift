//
//  Item.swift
//  Snipsnap
//
//  Created by Ethan Watson on 6/27/26.
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
