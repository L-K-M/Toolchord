// plaintext.js — Make Plain Text for Toolchord.
// Exposes global function: preview(input, options, api)
//
// api.id: "plaintext.clean"
// api.limits: { maxOutputBytes, outputLimitMessage }
// api.cancelled(): boolean
// options: { punctuation: "true" | "false", trim: "true" | "false" }
// input: string | null (null = no input)
//
// Returns:
//   Success: { primaryText, status, presentation: "text", syntax: "plain", fields, warnings }
//   Error:   { error: "needsInput" | "tooLarge" | "cancelled", message }

function preview(input, options, api) {
  if (input === null || input === undefined) {
    return { error: "needsInput", message: "Paste text to clean." };
  }
  if (api.cancelled()) return { error: "cancelled", message: "" };

  var doPunctuation = !(options && options.punctuation === "false");
  var doTrim = !(options && options.trim === "false");

  // Collect code points from the input string.
  var cps = [];
  for (var i = 0; i < input.length; i++) {
    var c = input.charCodeAt(i);
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < input.length) {
      var lo = input.charCodeAt(i + 1);
      if (lo >= 0xDC00 && lo <= 0xDFFF) {
        cps.push(((c - 0xD800) << 10) + (lo - 0xDC00) + 0x10000);
        i++;
        continue;
      }
    }
    cps.push(c);
  }

  var count = cps.length;

  // Empty input → empty output
  if (count === 0) {
    return {
      primaryText: "",
      status: "Already plain text",
      presentation: "text",
      syntax: "plain"
    };
  }

  // Counters
  var lineBreaks = 0;
  var invisible = 0;
  var spaces = 0;
  var punctuation = 0;
  var trailing = 0;

  // Kind tracking: { name, count, firstIndex }
  var invisibleKinds = [];
  var spacesKinds = [];
  var invisibleKindIndex = 0;
  var spacesKindIndex = 0;

  // Warning counters
  var bidiRemoved = 0;
  var tagRemoved = 0;

  // Output buffer (code points)
  var output = [];

  // Trailing space buffer
  var trailingBuffer = [];

  var idx = 0;
  var iterations = 0;
  while (idx < count) {
    iterations += 1;
    if ((iterations & 0xFFF) === 0 && api.cancelled()) {
      return { error: "cancelled", message: "" };
    }

    var v = cps[idx];

    // Category 1: Line breaks (always)
    if (v === 0x000D) {
      // CR
      if (idx + 1 < count && cps[idx + 1] === 0x000A) {
        // CRLF → LF (one change)
        output.push(0x000A);
        lineBreaks += 1;
        idx += 2;
        // Flush trailing buffer
        trailing += trailingBuffer.length;
        trailingBuffer.length = 0;
        continue;
      } else {
        // Lone CR → LF
        output.push(0x000A);
        lineBreaks += 1;
        idx += 1;
        // Flush trailing buffer
        trailing += trailingBuffer.length;
        trailingBuffer.length = 0;
        continue;
      }
    }

    // Check for LF first (not a change, just a line break for trimming)
    if (v === 0x000A) {
      output.push(0x000A);
      // Flush trailing buffer
      trailing += trailingBuffer.length;
      trailingBuffer.length = 0;
      idx += 1;
      continue;
    }

    // Category 1 continued: other line breaks
    if (v === 0x000B || v === 0x000C || v === 0x0085 || v === 0x2028 || v === 0x2029) {
      output.push(0x000A);
      lineBreaks += 1;
      idx += 1;
      // Flush trailing buffer
      trailing += trailingBuffer.length;
      trailingBuffer.length = 0;
      continue;
    }

    // Check for emoji tag sequence starting with U+1F3F4
    if (v === 0x1F3F4) {
      var seq = tryConsumeEmojiTagSequence(cps, idx);
      if (seq) {
        // Copy the entire sequence unchanged
        if (doTrim && trailingBuffer.length > 0) {
          for (var fb = 0; fb < trailingBuffer.length; fb++) {
            output.push(trailingBuffer[fb]);
          }
          trailingBuffer.length = 0;
        }
        for (var sc = 0; sc < seq.length; sc++) {
          output.push(seq[sc]);
        }
        idx += seq.length;
        continue;
      }
    }

    // Category 2: Hidden characters (always removed)
    var hiddenKind = classifyHidden(v);
    if (hiddenKind !== null) {
      invisible += 1;
      var existing = findKind(invisibleKinds, hiddenKind);
      if (existing >= 0) {
        invisibleKinds[existing].count += 1;
      } else {
        invisibleKinds.push({ name: hiddenKind, count: 1, firstIndex: invisibleKindIndex });
        invisibleKindIndex += 1;
      }

      // Track bidi and tag warnings
      if (isBidiControl(v)) {
        bidiRemoved += 1;
      }
      if (isTagChar(v)) {
        tagRemoved += 1;
      }

      idx += 1;
      continue;
    }

    // Category 3: Unusual spaces (always → U+0020)
    var spaceKind = classifySpace(v);
    if (spaceKind !== null) {
      spaces += 1;
      var existingSp = findKind(spacesKinds, spaceKind);
      if (existingSp >= 0) {
        spacesKinds[existingSp].count += 1;
      } else {
        spacesKinds.push({ name: spaceKind, count: 1, firstIndex: spacesKindIndex });
        spacesKindIndex += 1;
      }

      // If trimming, add to trailing buffer; otherwise output space
      if (doTrim) {
        trailingBuffer.push(0x0020);
      } else {
        output.push(0x0020);
      }
      idx += 1;
      continue;
    }

    // Category 4: Punctuation (only when enabled)
    if (doPunctuation) {
      var repl = classifyPunctuation(v);
      if (repl !== null) {
        punctuation += 1;
        // Flush trailing buffer before punctuation output
        if (doTrim && trailingBuffer.length > 0) {
          for (var fb2 = 0; fb2 < trailingBuffer.length; fb2++) {
            output.push(trailingBuffer[fb2]);
          }
          trailingBuffer.length = 0;
        }
        for (var rp = 0; rp < repl.length; rp++) {
          output.push(repl[rp]);
        }
        idx += 1;
        continue;
      }
    }

    // Category 5: Trailing spaces (only when trim is on)
    // Regular space (U+0020) or tab (U+0009)
    if (doTrim && (v === 0x0020 || v === 0x0009)) {
      trailingBuffer.push(v);
      idx += 1;
      continue;
    }

    // Default: copy unchanged
    if (doTrim && trailingBuffer.length > 0) {
      for (var fb3 = 0; fb3 < trailingBuffer.length; fb3++) {
        output.push(trailingBuffer[fb3]);
      }
      trailingBuffer.length = 0;
    }
    output.push(v);
    idx += 1;
  }

  // Flush remaining trailing buffer at end of text
  if (doTrim) {
    trailing += trailingBuffer.length;
    trailingBuffer.length = 0;
  } else if (trailingBuffer.length > 0) {
    for (var fb4 = 0; fb4 < trailingBuffer.length; fb4++) {
      output.push(trailingBuffer[fb4]);
    }
    trailingBuffer.length = 0;
  }

  var totalChanges = lineBreaks + invisible + spaces + punctuation + trailing;

  // Build primaryText from code points
  var primaryText = codePointsToString(output);

  // Check output size
  var outputBytes = utf8ByteCount(primaryText);
  if (outputBytes > api.limits.maxOutputBytes) {
    return { error: "tooLarge", message: api.limits.outputLimitMessage };
  }

  var status;
  if (totalChanges === 0) {
    status = "Already plain text";
  } else if (totalChanges === 1) {
    status = "1 change";
  } else {
    status = totalChanges + " changes";
  }

  // Build fields (order: invisible, spaces, punctuation, lineBreaks, trailing)
  var fields = [];

  if (invisible > 0) {
    var note = kindNote(invisibleKinds);
    fields.push({
      id: "invisible",
      label: "Hidden characters removed",
      value: String(invisible),
      note: note,
      isCopyable: false,
      isMonospaced: false
    });
  }

  if (spaces > 0) {
    var note2 = kindNote(spacesKinds);
    fields.push({
      id: "spaces",
      label: "Spaces normalized",
      value: String(spaces),
      note: note2,
      isCopyable: false,
      isMonospaced: false
    });
  }

  if (punctuation > 0) {
    fields.push({
      id: "punctuation",
      label: "Quotes and dashes straightened",
      value: String(punctuation),
      isCopyable: false,
      isMonospaced: false
    });
  }

  if (lineBreaks > 0) {
    fields.push({
      id: "lineBreaks",
      label: "Line breaks normalized",
      value: String(lineBreaks),
      isCopyable: false,
      isMonospaced: false
    });
  }

  if (trailing > 0) {
    fields.push({
      id: "trailing",
      label: "Trailing spaces removed",
      value: String(trailing),
      isCopyable: false,
      isMonospaced: false
    });
  }

  // Build warnings
  var warnings = [];
  if (bidiRemoved > 0) {
    var n = bidiRemoved;
    var charWord = n === 1 ? "character" : "characters";
    warnings.push("Removed " + n + " bidirectional control " + charWord + ", which can make text display in a different order than it is stored.");
  }
  if (tagRemoved > 0) {
    var n2 = tagRemoved;
    var charWord2 = n2 === 1 ? "character" : "characters";
    warnings.push("Removed " + n2 + " tag " + charWord2 + ", which can hide text from readers.");
  }

  return {
    primaryText: primaryText,
    status: status,
    presentation: "text",
    syntax: "plain",
    fields: fields,
    warnings: warnings
  };
}

// ─── Classification helpers ─────────────────────────────────────────────────

function classifyHidden(v) {
  if (v >= 0x0000 && v <= 0x0008) return "control character";
  if (v >= 0x000E && v <= 0x001F) return "control character";
  if (v === 0x007F) return "control character";
  if (v >= 0x0080 && v <= 0x0084) return "control character";
  if (v >= 0x0086 && v <= 0x009F) return "control character";
  if (v === 0x00AD) return "soft hyphen";
  if (v === 0x061C) return "Arabic letter mark";
  if (v === 0x180E) return "Mongolian vowel separator";
  if (v === 0x200B) return "zero-width space";
  if (v === 0x200E) return "left-to-right mark";
  if (v === 0x200F) return "right-to-left mark";
  if ((v >= 0x202A && v <= 0x202E) || (v >= 0x2066 && v <= 0x2069)) return "bidirectional control";
  if (v === 0x2060) return "word joiner";
  if (v >= 0x2061 && v <= 0x2064) return "invisible operator";
  if (v >= 0x206A && v <= 0x206F) return "deprecated format character";
  if (v === 0xFEFF) return "byte order mark";
  if (v >= 0xFFF9 && v <= 0xFFFB) return "interlinear annotation character";
  if (v === 0xFFFC) return "object replacement character";
  if (v === 0xE0001 || (v >= 0xE0020 && v <= 0xE007F)) return "tag character";
  return null;
}

function classifySpace(v) {
  if (v === 0x00A0) return "non-breaking space";
  if (v === 0x2000) return "en quad";
  if (v === 0x2001) return "em quad";
  if (v === 0x2002) return "en space";
  if (v === 0x2003) return "em space";
  if (v === 0x2004) return "three-per-em space";
  if (v === 0x2005) return "four-per-em space";
  if (v === 0x2006) return "six-per-em space";
  if (v === 0x2007) return "figure space";
  if (v === 0x2008) return "punctuation space";
  if (v === 0x2009) return "thin space";
  if (v === 0x200A) return "hair space";
  if (v === 0x202F) return "narrow no-break space";
  if (v === 0x205F) return "medium mathematical space";
  return null;
}

function classifyPunctuation(v) {
  if (v === 0x2018 || v === 0x2019 || v === 0x201A || v === 0x201B || v === 0x2032) {
    return [0x27]; // '
  }
  if (v === 0x201C || v === 0x201D || v === 0x201E || v === 0x201F || v === 0x2033) {
    return [0x22]; // "
  }
  if (v === 0x2010 || v === 0x2011 || v === 0x2012 || v === 0x2013 || v === 0x2212) {
    return [0x2D]; // -
  }
  if (v === 0x2014 || v === 0x2015) {
    return [0x2D, 0x2D]; // --
  }
  if (v === 0x2026) {
    return [0x2E, 0x2E, 0x2E]; // ...
  }
  return null;
}

function isBidiControl(v) {
  return (v >= 0x202A && v <= 0x202E) || (v >= 0x2066 && v <= 0x2069);
}

function isTagChar(v) {
  return v === 0xE0001 || (v >= 0xE0020 && v <= 0xE007F);
}

// ─── Emoji tag sequence ─────────────────────────────────────────────────────

function tryConsumeEmojiTagSequence(cps, from) {
  // Must start with U+1F3F4
  if (from >= cps.length || cps[from] !== 0x1F3F4) return null;

  var j = from + 1;
  var tagCount = 0;
  while (j < cps.length && tagCount < 32) {
    var v = cps[j];
    if (v >= 0xE0020 && v <= 0xE007E) {
      tagCount += 1;
      j += 1;
    } else {
      break;
    }
  }
  // Must end with E007F
  if (j >= cps.length || cps[j] !== 0xE007F) return null;
  // Must have at least 1 tag char
  if (tagCount < 1) return null;

  j += 1; // include E007F

  var result = [];
  for (var k = from; k < j; k++) {
    result.push(cps[k]);
  }
  return result;
}

// ─── Kind note formatting ───────────────────────────────────────────────────

function findKind(kinds, name) {
  for (var i = 0; i < kinds.length; i++) {
    if (kinds[i].name === name) return i;
  }
  return -1;
}

function kindNote(kinds) {
  // Sort by count descending, then by firstIndex ascending for ties
  var sorted = kinds.slice().sort(function (a, b) {
    if (a.count !== b.count) return b.count - a.count;
    return a.firstIndex - b.firstIndex;
  });

  var items = [];
  for (var idx = 0; idx < sorted.length; idx++) {
    var kind = sorted[idx];
    var name;
    if (idx === 0) {
      // Capitalize first letter
      var firstChar = kind.name.charAt(0).toUpperCase();
      name = firstChar + kind.name.substring(1);
    } else {
      name = kind.name;
    }
    items.push(name + " (" + kind.count + ")");
  }

  var result;
  if (items.length <= 3) {
    result = items.join(", ");
  } else {
    var extra = kinds.length - 3;
    var prefix = [];
    for (var p = 0; p < 3; p++) {
      prefix.push(items[p]);
    }
    result = prefix.join(", ") + ", and " + extra + " more";
  }

  return result;
}

// ─── String helpers ─────────────────────────────────────────────────────────

function codePointsToString(cps) {
  var parts = [];
  for (var i = 0; i < cps.length; i++) {
    var cp = cps[i];
    if (cp <= 0xFFFF) {
      parts.push(String.fromCharCode(cp));
    } else {
      cp -= 0x10000;
      parts.push(String.fromCharCode(0xD800 + (cp >> 10)));
      parts.push(String.fromCharCode(0xDC00 + (cp & 0x3FF)));
    }
  }
  // Use a bounded approach to avoid spread/join arg-length risks
  return parts.join("");
}

function utf8ByteCount(str) {
  var count = 0;
  for (var i = 0; i < str.length; i++) {
    var c = str.charCodeAt(i);
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < str.length) {
      var lo = str.charCodeAt(i + 1);
      if (lo >= 0xDC00 && lo <= 0xDFFF) {
        count += 4;
        i++;
        continue;
      }
    }
    if (c < 0x80) {
      count += 1;
    } else if (c < 0x800) {
      count += 2;
    } else {
      count += 3;
    }
  }
  return count;
}
