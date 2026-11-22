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

function preview(input, options, api) {
    try {
        if (api.cancelled()) return {error:'unsupported', message:'Evaluation was cancelled.'};
        if (api.id === 'json.escapeString') {
            const quoted = options.quotes !== 'false';
            let output = JSON.stringify(input).replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
            if (!quoted) output = output.slice(1, -1);
            return {primaryText:output, status:'Escaped', syntax:quoted ? 'json' : 'plain'};
        }
        if (api.id === 'json.unescapeString') return {primaryText:jsonUnescape(input, api), status:'Unescaped'};
        const doc = parseJSONSource(input, api);
        const indent = options.indent === '4' ? '    ' : options.indent === 'tab' ? '\t' : '  ';
        const text = api.id === 'json.validate' ? input : jsonRender(doc.tokens, api.id === 'json.format' ? indent : '', api);
        return {primaryText:text, status:'Valid JSON', syntax:'json', warnings:doc.warnings};
    } catch (error) {
        if (error.error) return error;
        throw error;
    }
}
