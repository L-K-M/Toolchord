/* @toolchord
{
  "apiVersion": 1,
  "id": "uuid.v7",
  "title": "Generate UUID v7",
  "summary": "Time-ordered identifier",
  "regenerateTitle": "Regenerate UUID",
  "palette": {
    "group": "uuid", "groupTitle": "UUID",
    "aliases": ["uuid7", "uuid v7", "time ordered uuid", "sortable uuid"],
    "glyph": "#", "copyNoun": "UUID"
  }
}
*/
function preview(input, options, api) {
    return uuidV7(api);
}

function makeSeed(options, api) {
    return makeIdentifierSeed(api, "v7");
}

// @shared uuid.v4/uuid
// ─── UUID v4 ────────────────────────────────────────────────────────────────

function uuidV4(api) {
  var seed = api.seed;
  if (!isValidUUIDv4(seed)) {
    return { error: "needsInput", message: "Select this command again to generate a value." };
  }

  var upper = seed.toUpperCase();
  var compact = seed.replace(/-/g, "");

  var fields = [
    { id: "upper", label: "Uppercase", value: upper },
    { id: "compact", label: "No hyphens", value: compact },
    { id: "braced", label: "Braced", value: "{" + upper + "}" }
  ];

  return {
    primaryText: seed,
    status: "UUID v4",
    fields: fields
  };
}

function isValidUUIDv4(seed) {
  if (typeof seed !== "string") return false;
  var bytes = parseCanonicalUUID(seed);
  if (bytes === null) return false;
  // Version 4: byte[6] >> 4 == 4
  if ((bytes[6] >> 4) !== 4) return false;
  // Variant: byte[8] & 0xC0 == 0x80
  if ((bytes[8] & 0xC0) !== 0x80) return false;
  return true;
}

// ─── UUID v7 ────────────────────────────────────────────────────────────────

function uuidV7(api) {
  var seed = api.seed;
  if (!isValidUUIDv7(seed)) {
    return { error: "needsInput", message: "Select this command again to generate a value." };
  }

  var bytes = parseCanonicalUUID(seed);
  var upper = seed.toUpperCase();
  var compact = seed.replace(/-/g, "");

  // Extract 48-bit timestamp from first 6 bytes using BigInt for precision
  var milliseconds = 0n;
  for (var i = 0; i < 6; i++) {
    milliseconds = (milliseconds << 8n) | BigInt(bytes[i]);
  }

  var timestamp = new Date(Number(milliseconds)).toISOString().replace(/^\+0*(\d{5,})-/, "$1-");

  var fields = [
    { id: "timestamp", label: "Timestamp", value: timestamp },
    { id: "upper", label: "Uppercase", value: upper },
    { id: "compact", label: "No hyphens", value: compact }
  ];

  return {
    primaryText: seed,
    status: "UUID v7",
    fields: fields
  };
}

function isValidUUIDv7(seed) {
  if (typeof seed !== "string") return false;
  var bytes = parseCanonicalUUID(seed);
  if (bytes === null) return false;
  // Version 7: byte[6] >> 4 == 7
  if ((bytes[6] >> 4) !== 7) return false;
  // Variant: byte[8] & 0xC0 == 0x80
  if ((bytes[8] & 0xC0) !== 0x80) return false;
  return true;
}

// ─── ULID ───────────────────────────────────────────────────────────────────

var CROCKFORD = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
var CROCKFORD_INDEX = {};
for (var _i = 0; _i < CROCKFORD.length; _i++) {
  CROCKFORD_INDEX[CROCKFORD[_i]] = _i;
}

function uuidULID(api) {
  var seed = api.seed;
  if (!isValidULID(seed)) {
    return { error: "needsInput", message: "Select this command again to generate a value." };
  }

  // Extract 48-bit timestamp from first 10 Crockford chars using BigInt
  var milliseconds = 0n;
  for (var i = 0; i < 10; i++) {
    milliseconds = (milliseconds << 5n) | BigInt(CROCKFORD_INDEX[seed[i]]);
  }

  var timestamp = new Date(Number(milliseconds)).toISOString().replace(/^\+0*(\d{5,})-/, "$1-");
  var lower = seed.toLowerCase();

  var fields = [
    { id: "timestamp", label: "Timestamp", value: timestamp },
    { id: "lower", label: "Lowercase", value: lower }
  ];

  return {
    primaryText: seed,
    status: "ULID",
    fields: fields
  };
}

function isValidULID(seed) {
  if (typeof seed !== "string" || seed.length !== 26) return false;
  // First char must be 0-7 (48-bit timestamp fits in 10 Crockford chars)
  var first = seed[0];
  if (first < "0" || first > "7") return false;
  // All chars must be valid Crockford base32
  for (var i = 0; i < seed.length; i++) {
    if (CROCKFORD_INDEX[seed[i]] === undefined) return false;
  }
  return true;
}

// ─── UUID Parsing ───────────────────────────────────────────────────────────

// Parse a canonical lowercase hyphenated UUID into 16 bytes, or return null.
function parseCanonicalUUID(text) {
  if (typeof text !== "string" || text.length !== 36) return null;

  var bytes = [];
  var high = null;

  for (var i = 0; i < 36; i++) {
    // Hyphens at positions 8, 13, 18, 23
    if (i === 8 || i === 13 || i === 18 || i === 23) {
      if (text[i] !== "-") return null;
      continue;
    }

    var nibble = hexDigitValue(text.charCodeAt(i));
    if (nibble === null) return null;

    if (high !== null) {
      bytes.push((high << 4) | nibble);
      high = null;
    } else {
      high = nibble;
    }
  }

  if (high !== null || bytes.length !== 16) return null;
  return bytes;
}

function hexDigitValue(code) {
  if (code >= 48 && code <= 57) return code - 48;
  if (code >= 97 && code <= 102) return code - 87;
  return null;
}

function makeIdentifierSeed(api, variant) {
  const bytes = api.entropy.slice(0, 16);
  const time = BigInt(Math.max(0, api.now || 0)) & 0xffffffffffffn;
  if (variant === "ulid") {
    const alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
    let value = bytes.slice(0, 10).reduce((n, b) => (n << 8n) | BigInt(b), time);
    let text = "";
    for (let i = 0; i < 26; i++) {
      text = alphabet[Number(value & 31n)] + text;
      value >>= 5n;
    }
    return text;
  }
  if (variant === "v7") {
    for (let i = 0; i < 6; i++) bytes[i] = Number(time >> BigInt(8 * (5 - i)) & 255n);
    bytes[6] = (bytes[6] & 15) | 0x70;
  } else {
    bytes[6] = (bytes[6] & 15) | 0x40;
  }
  bytes[8] = (bytes[8] & 63) | 128;
  const hex = bytes.map(b => b.toString(16).padStart(2, "0")).join("");
  return [hex.slice(0,8), hex.slice(8,12), hex.slice(12,16), hex.slice(16,20), hex.slice(20)].join("-");
}
// @endshared
