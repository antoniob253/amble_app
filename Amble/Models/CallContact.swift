import Foundation
import SwiftUI

/// Lightweight representation of a person the user wants to call — used
/// by `CallView`. Replaces the old `FamilyMember` type after the Family
/// tab was removed; CallView doesn't need the step-seed / persistence
/// machinery that type carried.
struct CallContact: Identifiable, Hashable {
    let id: UUID
    let name: String
    let relation: String
    let phone: String
    /// Hex color for the avatar circle.
    let colorHex: UInt32

    init(id: UUID = UUID(),
         name: String,
         relation: String,
         phone: String,
         colorHex: UInt32 = 0xD49060) {
        self.id = id
        self.name = name
        self.relation = relation
        self.phone = phone
        self.colorHex = colorHex
    }

    var color: Color { Color(hex: colorHex) }
    var initial: String { String(name.prefix(1)).uppercased() }
}
