import SwiftUI

enum Theme {
    static let primary = Color(red: 0.231, green: 0.510, blue: 0.965) // #3B82F6
    static let background = Color.black
    static let surface = Color(red: 0.110, green: 0.110, blue: 0.118) // #1c1c1e
    static let surfaceLight = Color(red: 0.173, green: 0.173, blue: 0.180) // #2c2c2e

    static let textPrimary = Color.white
    static let textSecondary = Color(red: 0.612, green: 0.639, blue: 0.686) // #9CA3AF

    static let error = Color(red: 0.937, green: 0.267, blue: 0.267) // #EF4444
    static let success = Color(red: 0.133, green: 0.773, blue: 0.369) // #22C55E
    static let warning = Color(red: 0.918, green: 0.702, blue: 0.031) // #EAB308
    static let gold = Color(red: 1.0, green: 0.843, blue: 0.0) // #FFD700

    static let watching = success
    static let completed = primary
    static let dropped = error

    static let overlay = Color.black.opacity(0.5)
}
