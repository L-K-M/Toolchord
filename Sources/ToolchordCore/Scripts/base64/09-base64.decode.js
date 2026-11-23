/* @toolchord
{
  "apiVersion": 1,
  "id": "base64.decode",
  "title": "Decode Base64",
  "summary": "Standard alphabet to UTF-8 text",
  "options": [
    {"id": "ignoreWhitespace", "label": "Ignore whitespace", "defaultValue": "false"}
  ],
  "palette": {
    "group": "base64", "groupTitle": "Base64",
    "aliases": ["base64 decode", "b64 decode", "from base64", "decode b64"],
    "glyph": "64", "copyNoun": "decoded text",
    "suggestions": [{"when": ["base64"], "score": 95}]
  }
}
*/
function preview(input, options, api) {
    return processBase64(input, options, api, "base64.decode");
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

// @shared base64.encode/base64
const base64Standard = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const base64URL = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

function decodeBase64Text(input, options, api) {
    const [start,end] = options.trim ? utf8.trimBounds(input) : [0,input.length];
    const alphabet = options.url ? base64URL : base64Standard;
    const digits = [];
    let firstPad = -1, pads = 0, last = start;
    function fail(message, offset) {
        throw {error:'invalid', message, offset, location:utf8.location(input,offset)};
    }
    for (let i = start; i < end;) {
        const offset = i, c = String.fromCodePoint(input.codePointAt(i));
        i += c.length;
        if ((offset & 4095) === 0 && api.cancelled()) throw {error:'cancelled', message:'Evaluation was cancelled.'};
        if (' \n\r\t'.includes(c) && options.ignoreWhitespace) continue;
        if (!options.ignoreWhitespace && /[\p{White_Space}\u200b]/u.test(c)) {
            fail('Base64 contains whitespace. Turn on Ignore whitespace to decode wrapped text.', offset);
        }
        if (c === '=') {
            if (firstPad < 0) firstPad = offset;
            if (++pads > 2) fail('Too much padding.',offset);
            continue;
        }
        if (firstPad >= 0) fail('Padding “=” is only allowed at the end.',firstPad);
        const digit = alphabet.indexOf(c);
        if (digit < 0) {
            if (c === '+' || c === '/') fail('Contains standard Base64 characters (“+” or “/”). Use Decode Base64.',offset);
            if (c === '-' || c === '_') fail('Contains URL-safe characters (“-” or “_”). Use Decode Base64URL.',offset);
            fail('Invalid Base64 character “'+c+'”.',offset);
        }
        digits.push(digit);
        last = offset;
    }
    const rem = digits.length % 4, invalidLength = 'Base64 length is invalid. Check for missing or extra characters.';
    if (rem === 1) fail(invalidLength,last);
    if (pads && !((pads === 2 && rem === 2) || (pads === 1 && rem === 3))) fail(invalidLength,firstPad);
    if (!pads && !options.url && rem) fail('Standard Base64 needs “=” padding. Add padding or use Decode Base64URL.',end);
    const final = digits[digits.length-1];
    if (rem === 2 && (final & 15) || rem === 3 && (final & 3)) {
        fail('The last character has nonzero padding bits, so this isn’t canonical Base64.',last);
    }
    const byteCount = Math.floor(digits.length * 6 / 8);
    if (byteCount > api.limits.maxOutputBytes) throw {error:'tooLarge', message:api.limits.outputLimitMessage};
    const bytes = new Uint8Array(byteCount);
    let buffer = 0, bits = 0, index = 0;
    for (const digit of digits) {
        buffer = buffer << 6 | digit;
        bits += 6;
        if (bits >= 8) { bits -= 8; bytes[index++] = buffer >>> bits; }
    }
    const text = utf8.decode(bytes);
    if (text === null) throw {error:'invalid', message:'Decoded bytes are not UTF-8 text.'};
    return {text:text.replace(/^\uFEFF/, ''),byteCount};
}

function processBase64(input, options, api, operation) {
    try {
        if (api.cancelled()) return {error:'cancelled', message:'Evaluation was cancelled.'};
        const url = operation.startsWith('base64url.');
        if (operation.endsWith('.decode')) {
            const {text,byteCount} = decodeBase64Text(input,{url,trim:true,ignoreWhitespace:options.ignoreWhitespace === 'true'},api);
            const unit = byteCount >= 1048576 ? 1048576 : byteCount >= 1024 ? 1024 : 1;
            const size = unit === 1 ? byteCount + (byteCount === 1 ? ' byte' : ' bytes')
                : Math.round(byteCount / unit * 10) / 10 + (unit === 1024 ? ' KiB' : ' MiB');
            return {primaryText:text,status:'Decoded · '+size};
        }
        const bytes = utf8.encode(input), rem = bytes.length % 3;
        const size = Math.floor(bytes.length / 3) * 4 + (rem ? url ? rem + 1 : 4 : 0);
        if (size > api.limits.maxOutputBytes) return {error:'tooLarge', message:api.limits.outputLimitMessage};
        const alphabet = url ? base64URL : base64Standard;
        const parts = [];
        for (let i = 0; i < bytes.length; i += 3) {
            if (i % 3072 === 0 && api.cancelled()) return {error:'cancelled', message:'Evaluation was cancelled.'};
            const n = bytes[i] << 16 | bytes[i+1] << 8 | bytes[i+2];
            parts.push(alphabet[n >>> 18],alphabet[n >>> 12 & 63]);
            if (i+1 < bytes.length) parts.push(alphabet[n >>> 6 & 63]); else if (!url) parts.push('=');
            if (i+2 < bytes.length) parts.push(alphabet[n & 63]); else if (!url) parts.push('=');
        }
        return {primaryText:parts.join(''),status:url ? 'Base64URL' : 'Base64'};
    } catch (error) {
        if (error.error) return error;
        throw error;
    }
}
// @endshared
