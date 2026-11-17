import AppKit

/// Monospaced fonts for the input editor and results.
enum CodeFonts {
    /// `family` at `size`, or the system's monospaced font (SF Mono) when
    /// the family is nil, not installed, or not monospaced: code columns
    /// must line up whatever a stored or pasted theme names.
    static func font(family: String?, size: CGFloat) -> NSFont {
        if let family,
           let font = NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: family]), size: size),
           font.familyName == family, font.isFixedPitch {
            return font
        }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Installed monospaced families, sorted for the typeface picker.
    /// Families whose names start with "." are system-private.
    @MainActor
    static func installedFamilies() -> [String] {
        let manager = NSFontManager.shared
        let families = manager.availableFontFamilies.filter { family in
            guard !family.hasPrefix("."),
                  let member = manager.availableMembers(ofFontFamily: family)?.first,
                  let name = member.first as? String,
                  let font = NSFont(name: name, size: 12) else { return false }
            return font.isFixedPitch
        }
        return families.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
