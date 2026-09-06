import SwiftUI

/// Android ilovasi bilan bir xil rang palitrasi (uz.svc/MainActivity.kt bilan mos).
enum Theme {
    static let bg = Color(red: 0x0F / 255, green: 0x17 / 255, blue: 0x2A / 255)      // #0F172A
    static let panel = Color(red: 0x1E / 255, green: 0x29 / 255, blue: 0x3B / 255)   // #1E293B
    static let panelHi = Color(red: 0x24 / 255, green: 0x34 / 255, blue: 0x49 / 255) // #243449
    static let accent = Color(red: 0x10 / 255, green: 0xB9 / 255, blue: 0x81 / 255)  // #10B981
    static let muted = Color(red: 0x64 / 255, green: 0x74 / 255, blue: 0x8B / 255)   // #64748B
    static let danger = Color(red: 0xDC / 255, green: 0x26 / 255, blue: 0x26 / 255)  // #DC2626
}

extension View {
    /// Ekran fonini bir xil qilish uchun qisqartma.
    func svcBackground() -> some View {
        self.background(Theme.bg.ignoresSafeArea())
    }
}
