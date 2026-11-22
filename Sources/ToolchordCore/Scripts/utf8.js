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
