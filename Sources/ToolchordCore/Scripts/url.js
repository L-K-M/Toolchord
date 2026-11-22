function preview(input, options, api) {
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
        if (api.id === 'url.encode') {
            const text = encodeURIComponent(input).replace(/[!'()*]/g,c => '%' + c.charCodeAt(0).toString(16).toUpperCase());
            return {primaryText:text, status:'Encoded'};
        }
        if (api.id === 'url.decode') return {primaryText:decode(input,0,false), status:'Decoded'};

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
