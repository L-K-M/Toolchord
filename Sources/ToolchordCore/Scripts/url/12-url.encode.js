/* @toolchord
{
  "apiVersion": 1,
  "id": "url.encode",
  "title": "Encode URL Component",
  "summary": "Percent-encode reserved characters",
  "palette": {
    "group": "url", "groupTitle": "URL",
    "aliases": ["url encode", "percent encode", "urlencode", "encodeuricomponent",
                "escape url"],
    "glyph": "%", "copyNoun": "component",
    "suggestions": [{"when": ["plain", "!multiline"], "score": 30}]
  }
}
*/
function preview(input, options, api) {
    return processURL(input, options, api, "encode");
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

// @shared url.encode/url
function processURL(input, options, api, operation) {
    const sizeError = {error:'tooLarge', message:api.limits.outputLimitMessage};
    function decode(segment, offset, form) {
        for (let i = segment.indexOf('%'); i >= 0; i = segment.indexOf('%', i+3)) {
            if (!/^[\da-f]{2}$/i.test(segment.slice(i+1,i+3))) {
                const fragment = [...segment.slice(i+1,i+5)].slice(0,2).join('');
                throw {error:'invalid', message:'Invalid percent escape “%'+fragment+'”.',location:utf8.location(input,offset+i)};
            }
        }
        let decoded;
        try { decoded = decodeURIComponent(form ? segment.replace(/\+/g,' ') : segment); }
        catch { throw {error:'invalid', message:'Decoded bytes are not UTF-8 text.'}; }
        if (utf8.size(decoded) > api.limits.maxOutputBytes) throw sizeError;
        return decoded.replace(/^\uFEFF/, '');
    }
    try {
        if (api.cancelled()) return {error:'cancelled', message:'Evaluation was cancelled.'};
        if (operation === 'encode') {
            const text = encodeURIComponent(input).replace(/[!'()*]/g,c => '%' + c.charCodeAt(0).toString(16).toUpperCase());
            return {primaryText:text, status:'Encoded'};
        }
        if (operation === 'decode') return {primaryText:decode(input,0,false), status:'Decoded'};

        // Split on the original delimiters before decoding, preserving ordering,
        // duplicates, empty names and the distinction between '+' and '%2B'.
        const [start,end] = utf8.trimBounds(input);
        const url = input.slice(start,end);
        const fragment = url.indexOf('#'), content = fragment < 0 ? url : url.slice(0,fragment);
        const question = content.indexOf('?'), marker = content.search(/[=&]/);
        const scheme = /^([a-z][a-z\d+.-]*):(\/\/)?/i.exec(content);
        const hasScheme = scheme && (scheme[1].length >= 2 || scheme[2]);
        const fields = [];
        const field = (id,label,value) => fields.push({id,label,value});
        if (hasScheme) {
            field('scheme','Scheme',scheme[1]);
            const body = content.slice(scheme[0].length,question < 0 ? content.length : question);
            if (scheme[2]) {
                const slash = body.indexOf('/');
                const authority = slash < 0 ? body : body.slice(0,slash);
                const at = authority.lastIndexOf('@');
                if (at >= 0) field('userinfo','User info',authority.slice(0,at));
                const host = authority.slice(at+1);
                let bracketed = false, colon = -1;
                for (let i = 0; i < host.length; i++) {
                    if (host[i] === '[') bracketed = true;
                    if (host[i] === ']') bracketed = false;
                    if (!bracketed && host[i] === ':') colon = i;
                }
                const port = colon >= 0 && /^\d+$/.test(host.slice(colon+1));
                field('host','Host',port ? host.slice(0,colon) : host);
                if (port) field('port','Port',host.slice(colon+1));
                if (slash >= 0) field('path','Path',body.slice(slash));
            } else if (body) field('path','Path',body);
            if (fragment >= 0) field('fragment','Fragment',url.slice(fragment+1));
        }
        const rawQuery = !hasScheme && marker >= 0 && (question < 0 || marker < question);
        const queryStart = rawQuery ? 0 : question < 0 ? content.length : question+1;
        const chunks = ['['];
        let bytes = 2, count = 0;
        const form = options.mode === 'form';
        function quote(text) {
            // Escape control bytes with uppercase hexadecimal digits, preserving
            // literal backslashes that the source itself contains.
            return '"' + text.replace(/["\\\u0000-\u001f\u2028\u2029]/g, c => {
                const simple = {'"':'\\"','\\':'\\\\','\b':'\\b','\f':'\\f','\n':'\\n','\r':'\\r','\t':'\\t'};
                return simple[c] || '\\u' + c.charCodeAt(0).toString(16).padStart(4,'0').toUpperCase();
            }) + '"';
        }
        for (let pos = queryStart; pos < content.length;) {
            if ((count & 1023) === 0 && api.cancelled()) return {error:'cancelled',message:'Evaluation was cancelled.'};
            let next = content.indexOf('&',pos);
            if (next < 0) next = content.length;
            if (next > pos) {
                const pair = content.slice(pos,next), eq = pair.indexOf('=');
                const name = decode(eq < 0 ? pair : pair.slice(0,eq), start+pos, form);
                const value = eq < 0 ? '' : decode(pair.slice(eq+1),start+pos+eq+1,form);
                const row = (count ? ',\n' : '\n') + '  {"name": ' + quote(name) + ', "value": ' + quote(value) + '}';
                bytes += utf8.size(row);
                if (bytes + 1 > api.limits.maxOutputBytes) throw sizeError;
                chunks.push(row);
                field('param-'+count,name || '(empty name)',value);
                count++;
            }
            pos = next+1;
        }
        chunks.push(count ? '\n]' : ']');
        return {primaryText:chunks.join(''), status:count ? count + (count === 1 ? ' parameter' : ' parameters') : 'No query parameters',
                presentation:'fields',syntax:'json',fields};
    } catch (error) {
        if (error.error) return error;
        throw error;
    }
}
// @endshared
