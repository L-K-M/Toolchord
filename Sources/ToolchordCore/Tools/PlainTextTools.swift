import Foundation

/// Scripted cleaning, plus the scalar hint used by input detection.
public enum PlainTextTools {
    public static var commands: [ToolCommand] { BundledScripts.commands(in: "plaintext") }

    static func isSpecial(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        // Category 2: Hidden characters
        case 0x0000...0x0008, 0x000E...0x001F, 0x007F: return true
        case 0x0080...0x0084, 0x0086...0x009F: return true
        case 0x00AD: return true // soft hyphen
        case 0x061C: return true // Arabic letter mark
        case 0x180E: return true // Mongolian vowel separator
        case 0x200B: return true // zero-width space
        case 0x200E, 0x200F: return true // LTR/RTL mark
        case 0x202A...0x202E: return true // bidi controls
        case 0x2060: return true // word joiner
        case 0x2061...0x2064: return true // invisible operator
        case 0x2066...0x2069: return true // bidi controls
        case 0x206A...0x206F: return true // deprecated format
        case 0xFEFF: return true // BOM
        case 0xFFF9...0xFFFB: return true // interlinear annotation
        case 0xFFFC: return true // object replacement
        case 0xE0001: return true // tag character
        case 0xE0020...0xE007F: return true // tag characters
        // Category 3: Unusual spaces
        case 0x00A0: return true // non-breaking space
        case 0x2000: return true // en quad
        case 0x2001: return true // em quad
        case 0x2002: return true // en space
        case 0x2003: return true // em space
        case 0x2004: return true // three-per-em space
        case 0x2005: return true // four-per-em space
        case 0x2006: return true // six-per-em space
        case 0x2007: return true // figure space
        case 0x2008: return true // punctuation space
        case 0x2009: return true // thin space
        case 0x200A: return true // hair space
        case 0x202F: return true // narrow no-break space
        case 0x205F: return true // medium mathematical space
        // Category 4: Punctuation
        case 0x2018, 0x2019, 0x201A, 0x201B, 0x2032: return true
        case 0x201C, 0x201D, 0x201E, 0x201F, 0x2033: return true
        case 0x2010, 0x2011, 0x2012, 0x2013, 0x2212: return true
        case 0x2014, 0x2015: return true
        case 0x2026: return true
        // Line break specials (not CR/LF)
        case 0x000B, 0x000C, 0x0085, 0x2028, 0x2029: return true
        default: return false
        }
    }
}
