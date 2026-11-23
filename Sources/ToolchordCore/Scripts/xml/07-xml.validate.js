/* @toolchord
{
  "apiVersion": 1,
  "id": "xml.validate",
  "title": "Validate XML",
  "summary": "Check well-formedness, keep the input",
  "palette": {
    "group": "xml", "groupTitle": "XML",
    "aliases": ["check xml", "well formed", "well-formed", "xml syntax", "lint xml",
                "xml validator"],
    "symbol": "checkmark.seal", "copyNoun": "input",
    "suggestions": [
      {"when": ["xml", "html"], "score": 40},
      {"when": ["xml"], "score": 75}
    ]
  }
}
*/
function preview(input, options, api) {
    return processXML(input, options, api, "validate");
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

// @shared xml.format/xml
// XML names and bindings compare by code units, without Unicode normalization.
// Offsets index the original string, so opaque elements retain their spelling.
const xmlNamePattern = /[:A-Z_a-z\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u02FF\u0370-\u037D\u037F-\u1FFF\u200C-\u200D\u2070-\u218F\u2C00-\u2FEF\u3001-\uD7FF\uF900-\uFDCF\uFDF0-\uFFFD\u{10000}-\u{EFFFF}][:A-Z_a-z\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u02FF\u0370-\u037D\u037F-\u1FFF\u200C-\u200D\u2070-\u218F\u2C00-\u2FEF\u3001-\uD7FF\uF900-\uFDCF\uFDF0-\uFFFD\u{10000}-\u{EFFFF}\-.\d\u00B7\u0300-\u036F\u203F-\u2040]*/yu;
const xmlNameStart = /^(?:[A-Z_a-z\u00C0-\u00D6\u00D8-\u00F6\u00F8-\u02FF\u0370-\u037D\u037F-\u1FFF\u200C-\u200D\u2070-\u218F\u2C00-\u2FEF\u3001-\uD7FF\uF900-\uFDCF\uFDF0-\uFFFD\u{10000}-\u{EFFFF}])/u;
const xmlNamespace = 'http://www.w3.org/XML/1998/namespace';
const xmlnsNamespace = 'http://www.w3.org/2000/xmlns/';

function parseXML(text, api) {
    let index = 0, nextCheck = 0, hasRoot = false;
    const namespaces = new Map([['xml', xmlNamespace]]);
    const top = [], stack = [];
    const bom = text.startsWith('\ufeff');
    if (bom) index++;

    function fail(message, at = index) {
        throw {error:'invalid', message, location:utf8.location(text,at)};
    }
    function checkpoint() {
        if (index >= nextCheck) {
            if (api.cancelled()) throw {error:'cancelled', message:'Evaluation was cancelled.'};
            nextCheck = index + 2048;
        }
    }
    function legal(cp) {
        return cp === 9 || cp === 10 || cp === 13 || (cp >= 32 && cp <= 0xd7ff)
            || (cp >= 0xe000 && cp <= 0xfffd) || (cp >= 0x10000 && cp <= 0x10ffff);
    }
    function advance() {
        checkpoint();
        const cp = text.codePointAt(index);
        if (!legal(cp)) fail('Illegal XML character.');
        index += cp > 65535 ? 2 : 1;
    }
    function space(c) { return c === ' ' || c === '\t' || c === '\r' || c === '\n'; }
    function skipSpace() {
        const start = index;
        while (space(text[index])) index++;
        return index !== start;
    }
    function consume(s) {
        if (!text.startsWith(s,index)) return false;
        index += s.length;
        return true;
    }
    function name(qualified = true) {
        const at = index;
        xmlNamePattern.lastIndex = at;
        const match = xmlNamePattern.exec(text);
        if (!match) fail('Expected an XML name.');
        const value = match[0];
        index += value.length;
        if (qualified) {
            const colon = value.indexOf(':');
            if (colon === 0 || (colon > 0 && (value.indexOf(':',colon+1) !== -1 || !xmlNameStart.test(value.slice(colon+1))))) {
                fail('Invalid qualified name “' + value + '”.', at);
            }
        }
        return value;
    }
    function add(start) {
        const node = {start, end:index, openEnd:index, closeStart:index, structural:false, children:null};
        const parent = stack[stack.length - 1];
        if (parent) (parent.node.children ??= []).push(node);
        else top.push(node);
        return node;
    }
    function reference() {
        const start = index++;
        if (consume('#')) {
            const hex = consume('x');
            const at = index;
            let n = 0;
            while (index < text.length) {
                const c = text.charCodeAt(index);
                const digit = (c >= 48 && c <= 57) ? c-48 : hex && c >= 65 && c <= 70 ? c-55 : hex && c >= 97 && c <= 102 ? c-87 : -1;
                if (digit < 0) break;
                n = Math.min(0x110000, n * (hex ? 16 : 10) + digit);
                index++;
            }
            if (index === at || !consume(';')) fail('Invalid character reference.',start);
            if (!legal(n)) fail('Character reference refers to an illegal XML character.',start);
            return String.fromCodePoint(n);
        }
        xmlNamePattern.lastIndex = index;
        if (!xmlNamePattern.test(text)) fail('Expected an entity or character reference after “&”.',start);
        const entity = name(false);
        if (!consume(';')) fail('Expected “;” after the entity reference.',start);
        const entities = {lt:'<', gt:'>', amp:'&', apos:"'", quot:'"'};
        if (!Object.hasOwn(entities,entity)) fail('Undefined entity “&' + entity + ';”. XML only predefines &lt;, &gt;, &amp;, &apos;, and &quot;.',start);
        return entities[entity];
    }
    function attributeValue(declaration = false) {
        skipSpace();
        if (!consume('=')) fail('Expected “=” after the attribute name.');
        skipSpace();
        const start = index, quote = text[index];
        if (quote !== "'" && quote !== '"') fail('Attribute values must be quoted.');
        index++;
        let from = index, value = '';
        while (index < text.length && text[index] !== quote) {
            if (declaration) { advance(); continue; }
            if (text[index] === '<') fail('Attribute values must not contain a raw “<”.');
            if (text[index] === '&') {
                value += text.slice(from,index) + reference();
                from = index;
            } else if ('\t\r\n'.includes(text[index])) {
                value += text.slice(from,index) + ' ';
                if (!consume('\r\n')) index++;
                from = index;
            } else advance();
        }
        if (index === text.length) fail('Expected a closing quote for the attribute value.',start);
        value += text.slice(from,index++);
        return value;
    }
    function declaration(start) {
        if (!skipSpace()) fail('Expected a version in the XML declaration.', start);
        if (name(false) !== 'version') fail('Expected version first in the XML declaration.', start);
        if (!/^1\.\d+$/.test(attributeValue(true))) fail('The XML version must have the form “1.x” with decimal digits.',start);
        let encoding = false, standalone = false;
        for (;;) {
            const separated = skipSpace();
            if (consume('?>')) { add(start); return; }
            if (!separated || index === text.length) fail('Expected “?>” or a declaration attribute.',start);
            const prop = name(false), value = attributeValue(true);
            if (prop === 'encoding' && !encoding && !standalone) {
                if (!/^[a-zA-Z][a-zA-Z0-9._-]*$/.test(value)) fail('Invalid encoding name in the XML declaration.',start);
                encoding = true;
            } else if (prop === 'standalone' && !standalone) {
                if (value !== 'yes' && value !== 'no') fail('Standalone must be “yes” or “no”.',start);
                standalone = true;
            } else fail('Unexpected or out-of-order XML declaration attribute “'+prop+'”.',start);
        }
    }
    function restore(undo) {
        for (const [k,v] of undo) {
            if (v === undefined) namespaces.delete(k);
            else namespaces.set(k,v);
        }
    }
    function startElement(start) {
        if (!stack.length && hasRoot) fail('Only one root element is allowed.',start);
        if (stack.length >= api.limits.maxNestingDepth) throw {error:'tooLarge', message:api.limits.nestingLimitMessage};
        const tag = name(), attrs = new Map(), undo = [];
        let empty = false, preserve = stack[stack.length-1]?.preserve ?? false;
        for (;;) {
            checkpoint();
            const separated = skipSpace();
            if (consume('/>')) { empty = true; break; }
            if (consume('>')) break;
            if (index === text.length) fail('Expected “>” to close the start tag.',start);
            if (!separated) fail('Expected whitespace between attributes.');
            const pos = index, key = name();
            if (attrs.has(key)) fail('Duplicate attribute “'+key+'”.',pos);
            attrs.set(key,{pos,value:attributeValue()});
        }
        for (const [key,{pos,value}] of attrs) {
            if (key === 'xmlns' || key.startsWith('xmlns:')) {
                const prefix = key === 'xmlns' ? '' : key.slice(6);
                if (prefix === 'xmlns' || value === xmlnsNamespace) fail('The “xmlns” prefix and its namespace URI must not be declared.',pos);
                if ((prefix === 'xml') !== (value === xmlNamespace)) fail('Only the “xml” prefix may be bound to the XML namespace URI.',pos);
                if (prefix && !value) fail('A namespace prefix must not be bound to an empty URI.',pos);
                undo.push([prefix,namespaces.get(prefix)]);
                namespaces.set(prefix,value);
            }
            if (key === 'xml:space' && ['preserve','default'].includes(value)) preserve = value === 'preserve';
        }
        const prefix = tag.includes(':') ? tag.split(':')[0] : '';
        if (prefix && (prefix === 'xmlns' || !namespaces.has(prefix))) fail('Undeclared namespace prefix “'+prefix+'”.',start);
        const expanded = new Set();
        for (const [key,{pos}] of attrs) {
            if (key === 'xmlns' || key.startsWith('xmlns:')) continue;
            const colon = key.indexOf(':');
            let uri = '', local = key;
            if (colon >= 0) {
                const prefix = key.slice(0,colon);
                if (!namespaces.has(prefix)) fail('Undeclared namespace prefix “'+prefix+'”.',pos);
                uri = namespaces.get(prefix); local = key.slice(colon+1);
            }
            const pair = uri + '\0' + local; // XML forbids NUL in either component.
            if (expanded.has(pair)) fail('Duplicate expanded attribute name “'+key+'”.',pos);
            expanded.add(pair);
        }
        const node = add(start);
        hasRoot = true;
        if (empty) restore(undo);
        else { node.structural = !preserve; stack.push({node,tag,undo,preserve}); }
    }
    while (index < text.length) {
        checkpoint();
        const start = index;
        if (consume('<!--')) {
            while (index < text.length && !text.startsWith('--',index)) advance();
            if (consume('-->')) add(start);
            else if (text.startsWith('--',index)) fail('Comments must not contain “--” or end with “-”.',start);
            else fail('Expected “-->” to close the comment.',start);
        } else if (consume('<?')) {
            const begin = index, target = name(false);
            const colon = target.indexOf(':');
            if (colon >= 0) fail('Processing instruction targets can’t contain “:”.',begin+colon);
            if (target === 'xml') {
                if (start !== (bom ? 1 : 0)) fail('The XML declaration must be at the very start of the document.',start);
                declaration(start); continue;
            }
            if (target.toLowerCase() === 'xml') fail('The processing instruction target “'+target+'” is reserved.',start);
            if (!skipSpace() && !text.startsWith('?>',index)) fail('Expected whitespace after the processing instruction target.',start);
            while (index < text.length && !text.startsWith('?>',index)) advance();
            if (!consume('?>')) fail('Expected “?>” to close the processing instruction.',start);
            add(start);
        } else if (text.startsWith('<!DOCTYPE',index) && !hasRoot) {
            throw {error:'unsupported', message:'Document type declarations (DOCTYPE) aren’t supported. Toolchord checks well-formedness without loading DTDs or entities.'};
        } else if (consume('<![CDATA[')) {
            if (!stack.length) fail('CDATA isn’t allowed outside the root element.',start);
            stack[stack.length-1].node.structural = false;
            while (index < text.length && !text.startsWith(']]>',index)) advance();
            if (!consume(']]>')) fail('Expected “]]>” to close the CDATA section.',start);
        } else if (consume('</')) {
            const tag = name(); skipSpace();
            if (!consume('>')) fail('Expected “>” to close the end tag.',start);
            const frame = stack.pop();
            if (!frame) fail('Unexpected end tag “</'+tag+'>”.',start);
            if (frame.tag !== tag) fail('Expected “</'+frame.tag+'>”, found “</'+tag+'>”.',start);
            frame.node.closeStart = start;
            frame.node.end = index;
            if (!frame.node.children) frame.node.structural = false;
            restore(frame.undo);
        } else if (text.startsWith('<!',index)) fail('Unexpected markup declaration.');
        else if (consume('<')) startElement(start);
        else {
            const frame = stack[stack.length-1];
            while (index < text.length && text[index] !== '<') {
                if (!frame && !space(text[index])) fail('Text isn’t allowed outside the root element.');
                if (frame && text.startsWith(']]>',index)) fail('Character data must not contain “]]>”.');
                if (frame && !space(text[index])) frame.node.structural = false;
                if (text[index] === '&') reference(); else advance();
            }
        }
    }
    if (stack.length) {
        const frame = stack[stack.length-1];
        fail('Expected “</'+frame.tag+'>” before the end of the input.',frame.node.start);
    }
    if (!hasRoot) fail('Expected a root element.');
    return {top,bom};
}

function formatXML(text, document, indent, api) {
    const output = [], stack = [], breaks = ['\n'];
    let bytes = 0;
    function append(piece) {
        bytes += utf8.size(piece);
        if (bytes > api.limits.maxOutputBytes) throw {error:'tooLarge',message:api.limits.outputLimitMessage};
        output.push(piece);
    }
    if (document.bom) append('\ufeff');
    stack.push({children:document.top, next:0, depth:0});
    let visited = 0;
    while (stack.length) {
        if ((visited++ & 2047) === 0 && api.cancelled()) throw {error:'cancelled', message:'Evaluation was cancelled.'};
        const frame = stack[stack.length-1];
        const child = frame.children[frame.next++];
        if (!child) {
            stack.pop();
            if (frame.node) {
                append(breaks[frame.depth-1]);
                append(text.slice(frame.node.closeStart,frame.node.end));
            }
            continue;
        }
        if (frame.node || frame.next > 1) append(breaks[frame.depth]);
        if (!child.structural) append(text.slice(child.start,child.end));
        else {
            append(text.slice(child.start,child.openEnd));
            breaks[frame.depth+1] ??= breaks[frame.depth] + indent;
            stack.push({node:child, children:child.children, next:0, depth:frame.depth+1});
        }
    }
    return output.join('');
}

function processXML(input, options, api, operation) {
    try {
        if (api.cancelled()) return {error:'cancelled', message:'Evaluation was cancelled.'};
        const document = parseXML(input, api);
        const indent = options.indent === '4' ? '    ' : options.indent === 'tab' ? '\t' : '  ';
        const primaryText = operation === 'validate' ? input : formatXML(input, document, indent, api);
        return {primaryText,status:'Well-formed XML',syntax:'xml'};
    } catch (error) {
        if (error.error) return error;
        throw error;
    }
}
// @endshared
