/* @toolchord
{
  "apiVersion": 1,
  "id": "json.minify",
  "title": "Minify JSON",
  "summary": "Remove insignificant whitespace",
  "palette": {
    "group": "json", "groupTitle": "JSON",
    "aliases": ["compact json", "compress json", "uglify json", "single line json"],
    "glyph": "{…}", "copyNoun": "JSON",
    "suggestions": [{"when": ["json"], "score": 85}]
  }
}
*/
function preview(input, options, api) {
    return processJSON(input, options, api, "minify");
}

// @shared json.format/utf8
// JavaScriptCore does not provide the browser's TextEncoder/TextDecoder APIs.
const utf8 = {
    size(text) {
        let count = 0;
        for (const scalar of text) {
            const n = scalar.codePointAt(0);
            count += n < 128 ? 1 : n < 2048 ? 2 : n < 65536 ? 3 : 4;
        }
        return count;
    },
    encode(text) {
        const out = [];
        for (const scalar of text) {
            const n = scalar.codePointAt(0);
            if (n < 128) out.push(n);
            else if (n < 2048) out.push(192 | n >> 6, 128 | n & 63);
            else if (n < 65536) out.push(224 | n >> 12, 128 | n >> 6 & 63, 128 | n & 63);
            else out.push(240 | n >> 18, 128 | n >> 12 & 63, 128 | n >> 6 & 63, 128 | n & 63);
        }
        return out;
    },
    decode(bytes) {
        const chunks = [], units = [];
        for (let i = 0; i < bytes.length;) {
            const lead = bytes[i++];
            let n = lead, tail = 0, minimum = 0;
            if (lead >= 128) {
                if (lead >= 194 && lead <= 223) { n = lead & 31; tail = 1; minimum = 128; }
                else if (lead >= 224 && lead <= 239) { n = lead & 15; tail = 2; minimum = 2048; }
                else if (lead >= 240 && lead <= 244) { n = lead & 7; tail = 3; minimum = 65536; }
                else return null;
                for (let k = 0; k < tail; k++) {
                    if (i === bytes.length || (bytes[i] & 192) !== 128) return null;
                    n = n * 64 + (bytes[i++] & 63);
                }
                if (n < minimum || n > 0x10ffff || (n >= 0xd800 && n <= 0xdfff)) return null;
            }
            if (n <= 65535) units.push(n);
            else { n -= 65536; units.push(0xd800 + (n >> 10), 0xdc00 + (n & 1023)); }
            if (units.length >= 4096) { chunks.push(String.fromCharCode(...units)); units.length = 0; }
        }
        return chunks.join('') + String.fromCharCode(...units);
    },
    location(text, offset) {
        let line = 1, column = 1;
        for (let i = 0; i < offset;) {
            const n = text.codePointAt(i);
            i += n > 65535 ? 2 : 1;
            if (n === 13) { if (text[i] === '\n' && i < offset) i++; line++; column = 1; }
            else if (n === 10) { line++; column = 1; }
            else column++;
        }
        return {line,column};
    },
    trimBounds(text) {
        const space = /[\p{White_Space}\u200b]/u;
        let first = 0, end = text.length;
        while (first < end && space.test(text[first])) first++;
        while (end > first && space.test(text[end-1])) end--;
        return [first,end];
    }
};
// @endshared

// @shared json.format/json-parser
function parseJSONSource(text, api) {

    var len = text.length;

    function padHex(value, width) {
        var s = value.toString(16).toUpperCase();
        while (s.length < width) s = "0" + s;
        return s;
    }

    function errInvalid(message, idx) {
        var loc = utf8.location(text, idx);
        return { error: "invalid", message: message, location: { line: loc.line, column: loc.column } };
    }

    function errTooLarge(message) {
        return { error: "tooLarge", message: message };
    }

    function errCancelled() {
        return { error: "unsupported", message: "Evaluation was cancelled." };
    }

    var pos = 0;
    var nextCheck = 0;
    var tokens = [];
    var warnings = [];
    var duplicateCount = 0;

    function checkpoint() {
        if (pos >= nextCheck) {
            if (api.cancelled()) throw errCancelled();
            nextCheck = pos + 4096;
        }
    }

    function isDigit(cu) { return cu >= 0x30 && cu <= 0x39; }
    function isLetter(cu) { return (cu >= 0x41 && cu <= 0x5A) || (cu >= 0x61 && cu <= 0x7A); }

    function skipWhitespace() {
        while (pos < len) {
            var c = text.charCodeAt(pos);
            if (c !== 0x20 && c !== 0x09 && c !== 0x0A && c !== 0x0D) break;
            checkpoint();
            pos++;
        }
        checkpoint();
        if (pos + 1 < len && text.charCodeAt(pos) === 0x2F) {
            var nx = text.charCodeAt(pos + 1);
            if (nx === 0x2F || nx === 0x2A) {
                throw errInvalid("Comments aren\u2019t allowed in JSON.", pos);
            }
        }
    }

    function Frame(isObject) {
        this.object = isObject;
        this.state = "first";
        this.commaPos = -1;
        this.names = new Set();
        this.closer = isObject ? "}" : "]";
    }

    function simpleEscapeChar(cu) {
        switch (cu) {
            case 0x22: return '"';
            case 0x2F: return '/';
            case 0x5C: return '\\';
            case 0x62: return '\b';
            case 0x66: return '\f';
            case 0x6E: return '\n';
            case 0x72: return '\r';
            case 0x74: return '\t';
            default: return null;
        }
    }

    function parseHexUnit(escapePos) {
        // escapePos points to the backslash; hex digits start at escapePos+2
        var end = escapePos + 6;
        if (end > len) {
            throw errInvalid("Expected four hex digits after “\\u”.", escapePos);
        }
        var result = 0;
        for (var i = escapePos + 2; i < end; i++) {
            var d = text.charCodeAt(i);
            var val;
            if (d >= 0x30 && d <= 0x39) val = d - 0x30;
            else if (d >= 0x41 && d <= 0x46) val = d - 0x41 + 10;
            else if (d >= 0x61 && d <= 0x66) val = d - 0x61 + 10;
            else throw errInvalid("Expected four hex digits after “\\u”.", escapePos);
            result = result * 16 + val;
        }
        return result;
    }

    function errInvalidEscape(escapePos) {
        var ch = escapePos + 1 < len ? String.fromCodePoint(text.codePointAt(escapePos + 1)) : "";
        throw errInvalid("Invalid escape “" + "\\" + ch + "”.", escapePos);
    }

    function parseString(decodeName) {
        var start = pos;
        pos++; // skip opening quote
        var rawStart = pos;
        var name = "";
        while (pos < len) {
            checkpoint();
            var cu = text.charCodeAt(pos);
            if (cu === 0x22) {
                if (decodeName) {
                    name += text.substring(rawStart, pos);
                }
                pos++;
                tokens.push(text.substring(start, pos));
                return name;
            }
            if (cu < 0x20) {
                throw errInvalid(
                    "Escape control character U+" + padHex(cu, 4) + " in this string.", pos);
            }
            if (cu === 0x5C) {
                if (decodeName) {
                    name += text.substring(rawStart, pos);
                }
                var escapePos = pos;
                pos++;
                if (pos >= len) {
                    throw errInvalid("Unterminated string.", start);
                }
                var esc = text.charCodeAt(pos);
                if (esc === 0x75) {
                    var unit = parseHexUnit(escapePos);
                    if (decodeName) {
                        name += String.fromCharCode(unit);
                    }
                    pos += 5;
                } else if (simpleEscapeChar(esc) !== null) {
                    if (decodeName) {
                        name += simpleEscapeChar(esc);
                    }
                    pos++;
                } else {
                    throw errInvalidEscape(escapePos);
                }
                rawStart = pos;
            } else {
                pos++;
            }
        }
        throw errInvalid("Unterminated string.", start);
    }

    function parseNumber() {
        var start = pos;
        if (text.charCodeAt(pos) === 0x2D) pos++;
        if (pos >= len || !isDigit(text.charCodeAt(pos))) {
            throw errInvalid("Expected a JSON value.", pos);
        }
        var firstDigit = pos;
        if (text.charCodeAt(pos) === 0x30) {
            pos++;
            if (pos < len && isDigit(text.charCodeAt(pos))) {
                throw errInvalid("Numbers can\u2019t have leading zeros.", firstDigit);
            }
        } else {
            while (pos < len && isDigit(text.charCodeAt(pos))) { checkpoint(); pos++; }
        }
        if (pos < len && text.charCodeAt(pos) === 0x2E) {
            var dot = pos;
            pos++;
            if (pos >= len || !isDigit(text.charCodeAt(pos))) {
                throw errInvalid("Expected a digit after “.”.", dot);
            }
            while (pos < len && isDigit(text.charCodeAt(pos))) { checkpoint(); pos++; }
        }
        if (pos < len && (text.charCodeAt(pos) === 0x65 || text.charCodeAt(pos) === 0x45)) {
            pos++;
            if (pos < len && (text.charCodeAt(pos) === 0x2B || text.charCodeAt(pos) === 0x2D)) pos++;
            if (pos >= len || !isDigit(text.charCodeAt(pos))) {
                throw errInvalid("Expected a digit in the exponent.", pos);
            }
            while (pos < len && isDigit(text.charCodeAt(pos))) { checkpoint(); pos++; }
        }
        tokens.push(text.substring(start, pos));
    }

    function parseValue(depth, closer) {
        skipWhitespace();
        if (pos >= len) {
            if (closer !== null) {
                throw errInvalid("Expected “" + closer + "” before the end of the input.", len);
            }
            throw errInvalid("Expected a JSON value.", pos);
        }
        var start = pos;
        var cu = text.charCodeAt(pos);
        if (cu === 0x7B || cu === 0x5B) {
            var isObj = cu === 0x7B;
            if (depth >= api.limits.maxNestingDepth) {
                throw errTooLarge(api.limits.nestingLimitMessage);
            }
            tokens.push(text.charAt(pos));
            pos++;
            return isObj ? "object" : "array";
        }
        if (cu === 0x22) {
            parseString(false);
            return "string";
        }
        if (cu === 0x27) {
            throw errInvalid("Use double quotes for JSON strings.", pos);
        }
        if (cu === 0x2B) {
            throw errInvalid("Numbers can\u2019t start with “+”.", pos);
        }
        if (cu === 0x2E) {
            throw errInvalid("Expected a digit before “.”.", pos);
        }
        if (cu === 0x2D) {
            var tail = text.substring(pos);
            if (tail.substring(0, 9) === "-Infinity") {
                throw errInvalid("“-Infinity” isn\u2019t valid JSON. Use null or a string.", pos);
            }
        }
        if (cu === 0x2D || (cu >= 0x30 && cu <= 0x39)) {
            parseNumber();
            return "number";
        }
        if (isLetter(cu)) {
            while (pos < len && isLetter(text.charCodeAt(pos))) {
                checkpoint();
                pos++;
            }
            var word = text.substring(start, pos);
            if (word === "NaN" || word === "Infinity") {
                throw errInvalid("“" + word + "” isn\u2019t valid JSON. Use null or a string.", start);
            }
            if (word !== "true" && word !== "false" && word !== "null") {
                throw errInvalid("Invalid literal. Use true, false, or null.", start);
            }
            tokens.push(word);
            return "literal";
        }
        var scalar = String.fromCodePoint(text.codePointAt(pos));
        throw errInvalid("Expected a value, found “" + scalar + "”.", pos);
    }

    function checkBOM() {
        if (len >= 3 && text.charCodeAt(0) === 0xFEFF) {
            throw errInvalid("Remove the byte order mark (U+FEFF) at the start of the input.", 0);
        }
    }

    if (api.cancelled()) throw errCancelled();
    checkBOM();

    var root = parseValue(0, null);
    var frames = [];
    if (root === "object" || root === "array") {
        frames.push(new Frame(root === "object"));
    }

    while (frames.length > 0) {
        skipWhitespace();
        var fi = frames.length - 1;
        var frame = frames[fi];
        var object = frame.object;
        var closer = frame.closer;

        if (pos >= len) {
            throw errInvalid("Expected “" + closer + "” before the end of the input.", len);
        }

        if (frame.state === "commaOrEnd") {
            if (text.charCodeAt(pos) === (closer === "}" ? 0x7D : 0x5D)) {
                tokens.push(text.charAt(pos));
                pos++;
                frames.pop();
            } else {
                if (text.charCodeAt(pos) !== 0x2C) {
                    throw errInvalid("Expected “,” or “" + closer + "”.", pos);
                }
                frame.state = "afterComma";
                frame.commaPos = pos;
                tokens.push(",");
                pos++;
            }
        } else {
            // state === "first" || state === "afterComma"
            if (text.charCodeAt(pos) === (closer === "}" ? 0x7D : 0x5D)) {
                if (frame.state === "afterComma") {
                    throw errInvalid("Remove the trailing comma before “" + closer + "”.", frame.commaPos);
                }
                tokens.push(text.charAt(pos));
                pos++;
                frames.pop();
                continue;
            }
            if (object) {
                if (text.charCodeAt(pos) !== 0x22) {
                    if (text.charCodeAt(pos) === 0x27) {
                        throw errInvalid("Use double quotes for JSON strings.", pos);
                    }
                    throw errInvalid("Member names must be double-quoted strings.", pos);
                }
                var nameStart = pos;
                var name = parseString(true);
                if (frame.names.has(name)) {
                    duplicateCount++;
                    if (duplicateCount <= 5) {
                        var loc = utf8.location(text, nameStart);
                        warnings.push("Duplicate member name \u201c" + name.replace(/[\uD800-\uDFFF]/gu, "\uFFFD") + "\u201d at line " + loc.line + ", column " + loc.column + ". Some parsers keep only the last value.");
                    }
                } else {
                    frame.names.add(name);
                }
                skipWhitespace();
                if (pos >= len || text.charCodeAt(pos) !== 0x3A) {
                    throw errInvalid("Expected “:” after the member name.", pos);
                }
                tokens.push(":");
                pos++;
            }
            frame.state = "commaOrEnd";
            var kind = parseValue(frames.length, closer);
            if (kind === "object" || kind === "array") {
                frames.push(new Frame(kind === "object"));
            }
        }
    }

    skipWhitespace();
    if (pos !== len) {
        throw errInvalid("Unexpected text after the JSON value.", pos);
    }
    if (duplicateCount > 5) {
        warnings.push("\u2026and " + (duplicateCount - 5) + " more duplicate member names.");
    }

    return { tokens: tokens, rootKind: root, warnings: warnings };
}
// @endshared

// @shared json.format/json
// Keep original JSON lexemes. In particular, converting a number to a JavaScript
// Number or collecting object members by name would change what the user copies.
function jsonUnescape(text, api) {
    let [first, end] = utf8.trimBounds(text);
    const quoted = first >= 0 && end - first >= 2 && text[first] === '"' && text[end - 1] === '"';
    let index = quoted ? first + 1 : 0;
    end = quoted ? end - 1 : text.length;
    const escapes = {'"':'"', '\\':'\\', '/':'/', b:'\b', f:'\f', n:'\n', r:'\r', t:'\t'};
    function fail(message, position) {
        throw {error:'invalid', message, location:utf8.location(text, position)};
    }
    function hexUnit(position) {
        const digits = text.slice(position + 2, position + 6);
        if (position + 6 > end || !/^[0-9a-f]{4}$/i.test(digits)) {
            fail('Expected four hex digits after “\\u”.', position);
        }
        return parseInt(digits, 16);
    }
    const chunks = [];
    let start = index;
    for (; index < end; index++) {
        if (text[index] === '"' && quoted) fail('Unescaped “"” inside the string.', index);
        if (text[index] !== '\\') continue;
        chunks.push(text.slice(start, index));
        let code = text[index + 1];
        if (Object.hasOwn(escapes, code) && index + 1 < end) {
            chunks.push(escapes[code]);
            index++;
        } else if (code === 'u' && index + 1 < end) {
            const high = hexUnit(index);
            if (high < 0xd800 || high > 0xdfff) {
                chunks.push(String.fromCharCode(high));
                index += 5;
            } else {
                let low;
                if (high < 0xdc00 && index + 12 <= end && text.startsWith('\\u', index + 6)) {
                    low = hexUnit(index + 6);
                }
                if (low === undefined || low < 0xdc00 || low > 0xdfff) {
                    fail('Unpaired surrogate “' + text.slice(index, index + 6) + '” can’t be decoded to text.', index);
                }
                chunks.push(String.fromCharCode(high, low));
                index += 11;
            }
        } else {
            code = index + 1 < text.length ? String.fromCodePoint(text.codePointAt(index + 1)) : '';
            fail('Invalid escape “\\' + code + '”.', index);
        }
        start = index + 1;
    }
    chunks.push(text.slice(start, end));
    const result = chunks.join('');
    if (utf8.size(result) > api.limits.maxOutputBytes) throw {error:'tooLarge', message:api.limits.outputLimitMessage};
    return result;
}

function jsonRender(tokens, indent, api) {
    const result = [];
    let bytes = 0;
    function append(piece) {
        bytes += utf8.size(piece);
        if (bytes > api.limits.maxOutputBytes) throw {error:'tooLarge', message:api.limits.outputLimitMessage};
        result.push(piece);
    }
    let depth = 0;
    const lines = ['\n'];
    function newline() {
        if (lines[depth] === undefined) lines[depth] = '\n' + indent.repeat(depth);
        append(lines[depth]);
    }
    for (let i = 0; i < tokens.length; i++) {
        if ((i & 2047) === 0 && api.cancelled()) throw {error:'unsupported', message:'Evaluation was cancelled.'};
        const token = tokens[i];
        if (indent && (token === ']' || token === '}')) {
            depth--;
            if (tokens[i - 1] !== '[' && tokens[i - 1] !== '{') newline();
        }
        append(token);
        if (!indent) continue;
        if (token === '[' || token === '{') {
            depth++;
            if (tokens[i + 1] !== ']' && tokens[i + 1] !== '}') newline();
        } else if (token === ',') newline();
        else if (token === ':') append(' ');
    }
    return result.join('');
}

function processJSON(input, options, api, operation) {
    try {
        if (api.cancelled()) return {error:'unsupported', message:'Evaluation was cancelled.'};
        if (operation === 'escapeString') {
            const quoted = options.quotes !== 'false';
            let output = JSON.stringify(input).replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
            if (!quoted) output = output.slice(1, -1);
            return {primaryText:output, status:'Escaped', syntax:quoted ? 'json' : 'plain'};
        }
        if (operation === 'unescapeString') return {primaryText:jsonUnescape(input, api), status:'Unescaped'};
        const doc = parseJSONSource(input, api);
        const indent = options.indent === '4' ? '    ' : options.indent === 'tab' ? '\t' : '  ';
        const text = operation === 'validate' ? input : jsonRender(doc.tokens, operation === 'format' ? indent : '', api);
        return {primaryText:text, status:'Valid JSON', syntax:'json', warnings:doc.warnings};
    } catch (error) {
        if (error.error) return error;
        throw error;
    }
}
// @endshared
