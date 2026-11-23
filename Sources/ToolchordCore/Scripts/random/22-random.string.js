/* @toolchord
{
  "apiVersion": 1,
  "id": "random.string",
  "title": "Generate Random String",
  "summary": "Secure random characters",
  "regenerateTitle": "Regenerate String",
  "options": [
    {"id": "length", "label": "Length", "defaultValue": "32",
     "choices": [
       {"id": "16", "label": "16"},
       {"id": "24", "label": "24"},
       {"id": "32", "label": "32"},
       {"id": "64", "label": "64"}
     ]},
    {"id": "characters", "label": "Characters", "defaultValue": "alnum",
     "choices": [
       {"id": "alnum", "label": "Letters & digits"},
       {"id": "symbols", "label": "With symbols"},
       {"id": "hex", "label": "Hex"}
     ]}
  ],
  "palette": {
    "group": "random", "groupTitle": "Random",
    "aliases": ["random string", "password", "token", "secret", "api key",
                "random password", "random token"],
    "symbol": "dice", "copyNoun": "string"
  }
}
*/
function preview(input, options, api) {
    return randomString(options, api);
}

function makeSeed(options, api) {
    return makeRandomSeed(api, "string");
}

// @shared random.string/random
// ─── Constants ──────────────────────────────────────────────────────────────

var SEED_BYTE_COUNT = 512;

var ALPHANUMERICS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
var SYMBOLS = ALPHANUMERICS + "!#$%&()*+,-./:;<=>?@[]^_{|}~";
var HEX_DIGITS = "0123456789abcdef";

var FIRST_SENTENCE = "Lorem ipsum dolor sit amet, consectetur adipiscing elit.";

var VOCABULARY = [
  "lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing", "elit", "sed", "do",
  "eiusmod", "tempor", "incididunt", "ut", "labore", "et", "dolore", "magna", "aliqua", "enim",
  "ad", "minim", "veniam", "quis", "nostrud", "exercitation", "ullamco", "laboris", "nisi", "aliquip",
  "ex", "ea", "commodo", "consequat", "duis", "aute", "irure", "in", "reprehenderit", "voluptate",
  "velit", "esse", "cillum", "fugiat", "nulla", "pariatur", "excepteur", "sint", "occaecat", "cupidatat",
  "non", "proident", "sunt", "culpa", "qui", "officia", "deserunt", "mollit", "anim", "id",
  "est", "laborum", "praesent", "vitae", "semper", "porta", "mauris", "viverra", "facilisis", "integer"
];

// ─── Random String ──────────────────────────────────────────────────────────

function randomString(options, api) {
  var seed = api.seed;
  if (seed === null || seed === undefined || seed === "") {
    return { error: "needsInput", message: "Select this command again to generate a value." };
  }

  // Validate seed: must be 1024 hex chars (512 bytes)
  var seedBytes = decodeHex(seed);
  if (seedBytes === null || seedBytes.length !== SEED_BYTE_COUNT) {
    return { error: "needsInput", message: "Select this command again to generate a value." };
  }

  var length = parseInt((options && options.length) || "32", 10);
  if (isNaN(length) || length <= 0) length = 32;

  var characters = (options && options.characters) || "alnum";
  var alphabet;
  if (characters === "symbols") {
    alphabet = SYMBOLS;
  } else if (characters === "hex") {
    alphabet = HEX_DIGITS;
  } else {
    alphabet = ALPHANUMERICS;
  }

  // Derive independent bytes for this option combination via HKDF
  var info = "toolchord.random.string;length=" + length + ";characters=" + characters;
  var derivedHex = api.native("crypto.hkdfHex", seed, info, SEED_BYTE_COUNT);
  var derivedBytes = hexToBytes(derivedHex);

  // Unbiased rejection mapping
  var text = mapBytes(derivedBytes, alphabet, length);
  if (text === null) {
    return { error: "needsInput", message: "Select this command again to generate a value." };
  }

  // Entropy: floor(length * log2(alphabet.length))
  var entropyBits = Math.floor(length * Math.log(alphabet.length) / Math.log(2));

  return {
    primaryText: text,
    status: length + " characters",
    fields: [
      { id: "entropy", label: "Entropy", value: entropyBits + " bits", isCopyable: false, isMonospaced: false }
    ],
    sensitivity: "secret"
  };
}

// Unbiased mapping by rejection: bytes at or above the largest multiple
// of the alphabet size are skipped. Returns null if not enough valid bytes.
function mapBytes(bytes, alphabet, length) {
  var size = alphabet.length;
  var limit = 256 - (256 % size);
  var chars = [];
  for (var i = 0; i < bytes.length && chars.length < length; i++) {
    if (bytes[i] < limit) {
      chars.push(alphabet[bytes[i] % size]);
    }
  }
  if (chars.length < length) return null;
  return chars.join("");
}

// ─── Random Lorem Ipsum ─────────────────────────────────────────────────────

function randomLorem(options, api) {
  var seedText = api.seed;
  if (seedText === null || seedText === undefined || seedText === "") {
    return { error: "needsInput", message: "Select this command again to generate a value." };
  }

  var seed;
  try {
    if (!/^\+?[0-9]+$/.test(seedText)) throw Error();
    seed = BigInt(seedText);
    if (seed > 0xffffffffffffffffn) throw Error();
  } catch (e) {
    return { error: "needsInput", message: "Select this command again to generate a value." };
  }

  var lengthChoice = (options && options.length) || "paragraph";
  var paragraphs;
  if (lengthChoice === "sentence") {
    paragraphs = 0;
  } else if (lengthChoice === "three") {
    paragraphs = 3;
  } else if (lengthChoice === "five") {
    paragraphs = 5;
  } else {
    paragraphs = 1;
  }

  var text;
  if (paragraphs === 0) {
    text = FIRST_SENTENCE;
  } else {
    text = loremParagraphs(paragraphs, seed);
  }

  var words = text.split(" ").filter(function (w) { return w.length > 0; }).length;
  var status = words === 1 ? "1 word" : words + " words";

  return {
    primaryText: text,
    status: status
  };
}

function loremParagraphs(count, seed) {
  var gen = splitMix64(seed);
  var result = [];
  for (var p = 0; p < count; p++) {
    var sentenceCount = nextInRange(gen, 4, 7);
    var sentences = [];
    if (p === 0) {
      sentences.push(FIRST_SENTENCE);
    }
    while (sentences.length < sentenceCount) {
      sentences.push(loremSentence(gen));
    }
    result.push(sentences.join(" "));
  }
  return result.join("\n\n");
}

function loremSentence(gen) {
  var wordCount = nextInRange(gen, 6, 14);
  var vocabLen = VOCABULARY.length;
  var words = [];
  for (var i = 0; i < wordCount; i++) {
    words.push(VOCABULARY[nextInRange(gen, 0, vocabLen - 1)]);
  }
  // Conditional comma insertion (matches Swift: count >= 8 && next() % 2 == 0)
  if (wordCount >= 8 && gen.next() % 2n === 0n) {
    var commaAfter = nextInRange(gen, 2, wordCount - 3);
    words[commaAfter] += ",";
  }
  // Capitalize first word
  words[0] = words[0].charAt(0).toUpperCase() + words[0].slice(1);
  return words.join(" ") + ".";
}

// ─── SplitMix64 (JS BigInt) ─────────────────────────────────────────────────

// SplitMix64: a small, well-distributed PRNG, deterministic per seed.
// Uses JS BigInt for exact 64-bit unsigned arithmetic.
var SM_INC = 0x9E3779B97F4A7C15n;
var SM_K1 = 0xBF58476D1CE4E5B9n;
var SM_K2 = 0x94D049BB133111EBn;
var MASK64 = 0xFFFFFFFFFFFFFFFFn;

function splitMix64(state) {
  return {
    _state: state & MASK64,
    next: function () {
      this._state = (this._state + SM_INC) & MASK64;
      var z = this._state;
      z = ((z ^ (z >> 30n)) & MASK64) * SM_K1 & MASK64;
      z = ((z ^ (z >> 27n)) & MASK64) * SM_K2 & MASK64;
      return (z ^ (z >> 31n)) & MASK64;
    }
  };
}

function nextInRange(gen, lo, hi) {
  var count = hi - lo + 1;
  return lo + Number(gen.next() % BigInt(count));
}

// ─── Hex Helpers ────────────────────────────────────────────────────────────

function decodeHex(text) {
  if (text.length % 2 !== 0) return null;
  var bytes = [];
  for (var i = 0; i < text.length; i += 2) {
    var high = hexDigitValue(text.charCodeAt(i));
    var low = hexDigitValue(text.charCodeAt(i + 1));
    if (high === null || low === null) return null;
    bytes.push((high << 4) | low);
  }
  return bytes;
}

function hexToBytes(hex) {
  var bytes = [];
  for (var i = 0; i < hex.length; i += 2) {
    bytes.push(parseInt(hex.substr(i, 2), 16));
  }
  return bytes;
}

function hexDigitValue(code) {
  if (code >= 48 && code <= 57) return code - 48;
  if (code >= 97 && code <= 102) return code - 87;
  return null;
}

function makeRandomSeed(api, variant) {
  const hex = api.entropy.map(byte => byte.toString(16).padStart(2, "0")).join("");
  return variant === "string" ? hex : BigInt("0x" + hex.slice(0, 16)).toString();
}
// @endshared
