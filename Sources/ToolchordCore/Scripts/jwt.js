// JSON numbers and member order (including duplicates) are significant when
// inspecting claims. Keep validated tokens until producing individual fields.
function jwtReadString(value, api) {
    try { return jsonUnescape(value, api); }
    catch (error) {
        // Decoded member offsets would point into a different document than the token on screen.
        if (error.error === 'invalid') throw {error:'invalid', message:error.message};
        throw error;
    }
}

function jwtMembers(tokens, api) {
    const members = [];
    for (let i = 1; i < tokens.length - 1;) {
        const name = jwtReadString(tokens[i], api);
        i += 2;
        const start = i;
        let depth = 0;
        do {
            const token = tokens[i++];
            if (token === '{' || token === '[') depth++;
            else if (token === '}' || token === ']') depth--;
        } while (depth > 0);
        members.push({name, value:tokens.slice(start, i).join('')});
        if (tokens[i] === ',') i++;
    }
    return members;
}

// Decimal shifting keeps sub-millisecond values just below a second or day on
// the correct side of the boundary, even when Number rounds them upwards.
function jwtDate(value, now) {
    if (!/^[-\d]/.test(value)) return null;
    const negative = value[0] === '-';
    const [mantissa, exponent] = value.replace(/^-/, '').split(/[eE]/);
    const dot = mantissa.indexOf('.');
    const fractionLength = dot < 0 ? 0 : mantissa.length - dot - 1;
    const digits = mantissa.replace('.', '').replace(/^0+/, '');
    const places = digits.length + Number(exponent || 0) - fractionLength + 3;
    let ms = null;
    if (!digits) ms = 0;
    else if (places <= 15) {
        const count = Math.max(0, places);
        const integer = Number(digits.slice(0, count).padEnd(count, '0'));
        ms = negative ? -integer - (/[1-9]/.test(digits.slice(count)) ? 1 : 0) : integer;
    }
    let seconds = Number(value);
    if (seconds === 0 && digits) seconds = negative ? -Number.MIN_VALUE : Number.MIN_VALUE;
    if (ms === null || ms < -62135596800000 || ms > 253402300799999) {
        return {instant:'Outside the supported date range', seconds};
    }
    const delta = seconds - now;
    let relative = 'now';
    for (const [size, name] of [[31536000,'year'],[2592000,'month'],[86400,'day'],[3600,'hour'],[60,'minute'],[1,'second']]) {
        if (Math.abs(delta) < size) continue;
        const count = Math.floor(Math.abs(delta) / size);
        const amount = count + ' ' + name + (count === 1 ? '' : 's');
        relative = delta <= 0 ? 'Expired ' + amount + ' ago' : 'Expires in ' + amount;
        break;
    }
    return {instant:new Date(ms).toISOString(), seconds, relative};
}

function preview(input, options, api) {
    try {
        if (api.cancelled()) return {error:'unsupported', message:'Evaluation was cancelled.'};
        const [first, end] = utf8.trimBounds(input);
        let token = input.slice(first, end);
        const warnings = [];
        if (/^Bearer /i.test(token)) {
            token = token.replace(/^Bearer +/i, '');
            warnings.push('Removed the “Bearer” prefix.');
        }
        const parts = token.split('.');
        if (parts.length === 5) return {error:'unsupported', message:'This is an encrypted JWT (JWE). Toolchord can’t decode it without the key.'};
        if (parts.length !== 3) return {error:'invalid', message:'A JWT has three parts separated by dots (header.payload.signature).'};
        function read(segment, name, offset) {
            if (!segment) throw {error:'invalid', message:'The ' + name + ' must not be empty.', location:utf8.location(input, offset)};
            let decoded;
            try { decoded = decodeBase64Text(segment, {url:true, ignoreWhitespace:false, trim:false}, api).text; }
            catch (error) {
                if (error.error !== 'invalid') throw error;
                if (error.message === 'Decoded bytes are not UTF-8 text.') throw {error:'invalid', message:'The ' + name + ' isn’t UTF-8 text.'};
                throw {error:'invalid', message:'The ' + name + ' isn’t valid Base64URL: ' + error.message,
                       location:utf8.location(input, offset + (error.offset || 0))};
            }
            let doc;
            try { doc = parseJSONSource(decoded, api); }
            catch (error) {
                if (error.error !== 'invalid') throw error;
                throw {error:'invalid', message:'The ' + name + ' isn’t valid JSON: ' + error.message};
            }
            const formatted = jsonRender(doc.tokens, '  ', api);
            if (doc.rootKind !== 'object') throw {error:'invalid', message:name === 'header' ? 'The header must be a JSON object.' : 'The claims must be a JSON object.'};
            warnings.push(...doc.warnings);
            return {formatted, members:jwtMembers(doc.tokens, api)};
        }
        const start = input.indexOf(token);
        const header = read(parts[0], 'header', start);
        const payload = read(parts[1], 'payload', start + parts[0].length + 1);
        const alg = header.members.findLast(m => m.name === 'alg');
        if (alg && alg.value[0] === '"' && jwtReadString(alg.value, api) === 'none') {
            warnings.push('The header says alg: none, so this token has no signature.');
        }
        const now = api.now / 1000;
        const dates = new Map();
        const expiry = {id:'expiry', label:'Expiry', value:'No expiry claim', isCopyable:false, isMonospaced:false};
        const fields = [expiry, {id:'header', label:'Header', value:header.formatted}];
        for (const [index, claim] of payload.members.entries()) {
            const field = {id:'claim-' + index, label:claim.name, value:claim.value};
            if (['exp','iat','nbf'].includes(claim.name)) {
                const date = jwtDate(claim.value, now);
                dates.set(claim.name, date);
                field.note = date?.instant || 'Not a NumericDate (seconds since 1970)';
                if (!date) field.tone = 'warning';
            }
            fields.push(field);
        }
        if (dates.has('exp')) {
            const date = dates.get('exp');
            expiry.value = date?.instant || 'exp isn’t a number';
            if (date?.relative !== undefined) expiry.note = date.relative;
            if (!date || date.seconds <= now) expiry.tone = 'warning';
            if (date && date.seconds <= now) warnings.push('Expiry is in the past.');
        }
        if (dates.get('nbf')?.seconds > now) warnings.push('This token is not valid yet (nbf is in the future).');
        return {primaryText:payload.formatted, status:'Signature unverified', syntax:'json', statusTone:'warning', fields, warnings};
    } catch (error) {
        if (error.error) return error;
        throw error;
    }
}
