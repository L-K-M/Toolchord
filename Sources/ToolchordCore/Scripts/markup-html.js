function htmlToText(input, showLinks, api) {

    var raw = {"script":1,"style":1,"title":1,"iframe":1,"noscript":1,"noembed":1,"noframes":1};
    var hidden = {"template":1,"object":1,"svg":1,"math":1,"canvas":1,"audio":1,"video":1,"datalist":1};
    var paragraphs = {"p":1,"h1":1,"h2":1,"h3":1,"h4":1,"h5":1,"h6":1,"pre":1,"listing":1,"blockquote":1,
        "ul":1,"ol":1,"menu":1,"dl":1,"table":1,"hr":1,"figure":1,"address":1,"fieldset":1,"details":1};
    var lines = {"article":1,"aside":1,"body":1,"caption":1,"center":1,"dd":1,"dialog":1,"div":1,"dt":1,
        "figcaption":1,"footer":1,"form":1,"header":1,"hgroup":1,"html":1,"legend":1,"li":1,"main":1,
        "nav":1,"option":1,"search":1,"section":1,"summary":1,"tbody":1,"textarea":1,"tfoot":1,"thead":1,"tr":1};
    var lists = {"ul":1,"ol":1,"menu":1,"dl":1};
    var enclosingEnds = {};
    var _k;
    for (_k in paragraphs) enclosingEnds[_k] = 1;
    for (_k in lines) enclosingEnds[_k] = 1;
    enclosingEnds["td"] = 1;
    enclosingEnds["th"] = 1;
    var closesParagraph = {"address":1,"article":1,"aside":1,"blockquote":1,"center":1,"details":1,"dialog":1,
        "div":1,"dl":1,"fieldset":1,"figcaption":1,"figure":1,"footer":1,"form":1,"h1":1,"h2":1,"h3":1,
        "h4":1,"h5":1,"h6":1,"header":1,"hgroup":1,"hr":1,"listing":1,"main":1,"menu":1,"nav":1,"ol":1,
        "p":1,"pre":1,"search":1,"section":1,"summary":1,"table":1,"ul":1};
    var voidEls = {"area":1,"base":1,"br":1,"col":1,"embed":1,"hr":1,"img":1,"input":1,"link":1,"meta":1,"source":1,"track":1,"wbr":1};
    var foreignRoots = {"svg":1,"math":1};
    var maxHiddenInner = 256;

    function has(obj, key) { return Object.hasOwn(obj, key); }

    function arrContains(arr, val) { return arr.indexOf(val) >= 0; }

    function startTagEnds(h, start, inner) {
        switch (h) {
            case "p":
                if (!has(closesParagraph, start)) return false;
                for (var i = 0; i < inner.length; i++) {
                    if (inner[i] === "button" || inner[i] === "table" || inner[i] === "td" ||
                        inner[i] === "th" || inner[i] === "caption" || inner[i] === "template" ||
                        inner[i] === "object") return false;
                }
                return true;
            case "li": return start === "li" && !arrContains(inner, "ul") && !arrContains(inner, "ol") && !arrContains(inner, "menu") && !arrContains(inner, "dl");
            case "dt":
            case "dd":
                return (start === "dt" || start === "dd") && !arrContains(inner, "dl");
            case "option": return start === "option" || start === "optgroup";
            case "tr": return start === "tr" && !arrContains(inner, "table");
            case "td":
            case "th":
                return (start === "td" || start === "th" || start === "tr") && !arrContains(inner, "table");
            default: return false;
        }
    }

    function isHiddenByAttribute(tag) {
        if (tag.attributes["hidden"] !== undefined) return true;
        var style = tag.attributes["style"];
        if (!style) return false;
        var display;
        var decls = style.split(";");
        for (var d = 0; d < decls.length; d++) {
            var decl = decls[d];
            var colonIdx = decl.indexOf(":");
            if (colonIdx < 0) continue;
            var prop = decl.substring(0, colonIdx).trim().toLowerCase();
            if (prop !== "display") continue;
            var val = decl.substring(colonIdx + 1).trim().toLowerCase();
            if (val.length > 10 && val.substring(val.length - 10) === "!important") {
                val = val.substring(0, val.length - 10).trim();
            }
            display = val;
        }
        return display === "none";
    }

    function opensHiddenContent(tag) {
        if (tag.end) return false;
        if (has(raw, tag.name) || (tag.name === "textarea" && isHiddenByAttribute(tag))) return true;
        if (has(voidEls, tag.name)) return false;
        if (tag.selfClosing && has(foreignRoots, tag.name)) return false;
        return has(hidden, tag.name) || isHiddenByAttribute(tag);
    }

    // HTML list markers in the original tools accept signed 64-bit integers.
    // Bound the source before constructing a BigInt, including leading zeros.
    function ordinal(text, fallback) {
        if (text === undefined || !/^[+-]?\d+$/.test(text)) return fallback;
        const digits = text.replace(/^[+-]?0*/, '') || '0';
        if (digits.length > 19) return fallback;
        const n = BigInt((text[0] === '-' ? '-' : '') + digits);
        return n >= -9223372036854775808n && n <= 9223372036854775807n ? n : fallback;
    }

    function markupLinkSuffix(text, url) {
        var trimmed = text.trim();
        if (!url || url.charAt(0) === "#" || url.toLowerCase().indexOf("javascript:") === 0) return "";
        var short = url;
        var lowerUrl = url.toLowerCase();
        if (lowerUrl.indexOf("mailto:") === 0) short = url.substring(7);
        else if (lowerUrl.indexOf("http://") === 0) short = url.substring(7);
        else if (lowerUrl.indexOf("https://") === 0) short = url.substring(8);
        return (trimmed === url || trimmed === short) ? "" : " (" + url + ")";
    }

    function PlainTextWriter() {
        this.bytes = [];
        this.prefixes = [];
        this.emittedPrefixes = 0;
        this.pendingBoundary = 0;
        this.pendingEndings = [];
        this.preserveLeadingBreaks = false;
        this.pendingSpace = false;
        this.markerGap = false;
        this.lineContent = false;
        this.lineVerbatim = false;
        this.trailingBreaks = 0;
        this.ticks = 0;
        this.meaningfulEnd = 0;
        this.lastContentVerbatim = false;
        this.boundaryPrefixFloor = Infinity;
    }

    PlainTextWriter.prototype.check = function () {
        this.ticks++;
        if (this.ticks % 2048 === 0 && api.cancelled()) throw { error: "cancelled", message: "Evaluation was cancelled." };
        if (this.bytes.length > api.limits.maxOutputBytes) throw { error: "tooLarge", message: api.limits.outputLimitMessage };
    };

    PlainTextWriter.prototype.append = function (text) {
        var encoded = utf8.encode(text);
        if (encoded.length > api.limits.maxOutputBytes - this.bytes.length)
            throw { error: "tooLarge", message: api.limits.outputLimitMessage };
        for (const byte of encoded) this.bytes.push(byte);
        this.check();
    };

    PlainTextWriter.prototype.trimLine = function () {
        if (!this.lineVerbatim) {
            while (this.bytes.length > 0 && this.bytes[this.bytes.length - 1] === 32) {
                this.bytes.pop();
            }
        }
        if (this.bytes.length < this.meaningfulEnd) this.meaningfulEnd = this.bytes.length;
    };

    PlainTextWriter.prototype.boundary = function (count) {
        this.pendingSpace = false;
        if (!this.lineContent && this.trailingBreaks === 0 && this.pendingEndings.length === 0 && this.bytes.length > 0) return;
        if (count > this.pendingBoundary) this.pendingBoundary = count;
        if (this.prefixes.length < this.boundaryPrefixFloor) this.boundaryPrefixFloor = this.prefixes.length;
    };

    PlainTextWriter.prototype.newline = function (blank, ending, prefixLimit) {
        if (blank === undefined) blank = false;
        if (ending === undefined) ending = "\n";
        if (prefixLimit === undefined) prefixLimit = Infinity;
        this.trimLine();
        if (blank) {
            var lim = prefixLimit < this.prefixes.length ? prefixLimit : this.prefixes.length;
            for (var i = 0; i < lim; i++) {
                if (this.prefixes[i].quote) this.append(this.prefixes[i].text);
            }
            while (this.bytes.length > 0 && this.bytes[this.bytes.length - 1] === 32) this.bytes.pop();
        }
        this.append(ending);
        this.trailingBreaks++;
        this.pendingSpace = false;
        this.markerGap = false;
        this.lineContent = false;
        this.lineVerbatim = false;
        this.emittedPrefixes = 0;
    };

    PlainTextWriter.prototype.prepare = function (flushMarkerGap) {
        if (flushMarkerGap === undefined) flushMarkerGap = true;
        var needed = this.pendingBoundary > this.trailingBreaks + this.pendingEndings.length
            ? this.pendingBoundary : this.trailingBreaks + this.pendingEndings.length;
        if (needed > 0) {
            if (this.bytes.length > 0 || this.preserveLeadingBreaks) {
                while (this.trailingBreaks + this.pendingEndings.length < needed) {
                    this.pendingEndings.push("\n");
                }
                var floor = this.boundaryPrefixFloor < this.prefixes.length ? this.boundaryPrefixFloor : this.prefixes.length;
                for (var i = 0; i < this.pendingEndings.length; i++) {
                    this.newline(this.trailingBreaks > 0, this.pendingEndings[i], floor);
                }
            }
            this.pendingBoundary = 0;
            this.pendingEndings = [];
            this.preserveLeadingBreaks = false;
            this.boundaryPrefixFloor = Infinity;
        }
        if (this.markerGap && flushMarkerGap) {
            this.append(" ");
            this.markerGap = false;
        }
        while (this.emittedPrefixes < this.prefixes.length) {
            this.append(this.prefixes[this.emittedPrefixes].text);
            this.emittedPrefixes++;
        }
    };

    PlainTextWriter.prototype.pushQuote = function () {
        this.prefixes.push({ text: "> ", quote: true, item: false });
    };

    PlainTextWriter.prototype.pushIndent = function (width) {
        var s = "";
        for (var i = 0; i < width; i++) s += " ";
        this.prefixes.push({ text: s, quote: false, item: false });
    };

    PlainTextWriter.prototype.popPrefix = function () {
        if (this.prefixes.length > 0) {
            var last = this.prefixes.pop();
            if (last.item) this.lineContent = true;
        }
        if (this.emittedPrefixes > this.prefixes.length) this.emittedPrefixes = this.prefixes.length;
    };

    PlainTextWriter.prototype.beginItem = function (marker) {
        this.prepare();
        if (this.pendingSpace && this.lineContent) this.append(" ");
        this.pendingSpace = false;
        // marker without trailing space
        this.append(marker.substring(0, marker.length - 1));
        this.markerGap = true;
        var pad = "";
        for (var i = 0; i < marker.length; i++) pad += " ";
        this.prefixes.push({ text: pad, quote: false, item: true });
        this.emittedPrefixes = this.prefixes.length;
        this.trailingBreaks = 0;
        this.meaningfulEnd = this.bytes.length;
        this.lastContentVerbatim = false;
    };

    PlainTextWriter.prototype.deferBreak = function (ending, verbatim) {
        if (verbatim === undefined) verbatim = false;
        while (this.trailingBreaks + this.pendingEndings.length < this.pendingBoundary) {
            this.pendingEndings.push("\n");
        }
        this.pendingEndings.push(ending);
        this.pendingBoundary = 0;
        this.pendingSpace = false;
        this.markerGap = false;
        this.lineContent = false;
        if (verbatim) this.preserveLeadingBreaks = true;
        this.check();
    };

    PlainTextWriter.prototype.hardBreak = function () {
        this.deferBreak("\n");
    };

    PlainTextWriter.prototype.write = function (text, verbatim, collapse) {
        if (verbatim === undefined) verbatim = false;
        if (collapse === undefined) collapse = true;
        var previousCR = false;
        for (var i = 0; i < text.length; i++) {
            var cp = text.charCodeAt(i);
            // Handle surrogate pairs
            if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < text.length) {
                var lo = text.charCodeAt(i + 1);
                if (lo >= 0xDC00 && lo <= 0xDFFF) {
                    cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                    i++;
                }
            }
            this.check();
            if (verbatim) {
                if (cp === 0x0A && previousCR) {
                    this.pendingEndings[this.pendingEndings.length - 1] = "\r\n";
                    previousCR = false;
                    continue;
                }
                if (cp === 0x0D || cp === 0x0A) {
                    this.lineVerbatim = true;
                    this.deferBreak(cp === 0x0D ? "\r" : "\n", true);
                    previousCR = cp === 0x0D;
                    continue;
                }
                previousCR = false;
                this.prepare();
                this.lineVerbatim = true;
                var ch = cp === 0x00A0 ? " " : String.fromCodePoint(cp);
                this.append(ch);
                this.lineContent = true;
                this.trailingBreaks = 0;
                this.meaningfulEnd = this.bytes.length;
                this.lastContentVerbatim = true;
            } else if (collapse && (cp === 0x20 || cp === 0x09 || cp === 0x0D || cp === 0x0A || cp === 0x0C)) {
                if (this.lineContent) this.pendingSpace = true;
            } else {
                this.prepare();
                if (this.pendingSpace && this.lineContent) this.append(" ");
                this.pendingSpace = false;
                var ch2 = cp === 0x00A0 ? " " : String.fromCodePoint(cp);
                this.append(ch2);
                this.lineContent = true;
                this.trailingBreaks = 0;
                this.meaningfulEnd = this.bytes.length;
                this.lastContentVerbatim = false;
            }
        }
    };

    PlainTextWriter.prototype.row = function (cells) {
        this.prepare();
        for (var i = 0; i < cells.length; i++) {
            if (i > 0) this.append("\t");
            this.append(cells[i]);
        }
        this.lineContent = true;
        this.trailingBreaks = 0;
        this.meaningfulEnd = this.bytes.length;
        this.lastContentVerbatim = false;
    };

    PlainTextWriter.prototype.finish = function () {
        if (this.meaningfulEnd < this.bytes.length) {
            this.bytes = this.bytes.slice(0, this.meaningfulEnd);
        }
        if (!this.lastContentVerbatim) {
            while (this.bytes.length > 0 && this.bytes[this.bytes.length - 1] === 32) this.bytes.pop();
        }
        while (this.bytes.length > 0 && (this.bytes[this.bytes.length - 1] === 10 || this.bytes[this.bytes.length - 1] === 13)) {
            this.bytes.pop();
        }
        return utf8.decode(this.bytes);
    };

    function decodeEntities(text) {
        return text.replace(/&(?:#([0-9]{1,32})|#[xX]([0-9a-fA-F]{1,32})|([a-zA-Z0-9]{1,32}));/g,
            (raw, decimal, hex, name) => {
                if (name) return Object.hasOwn(HTMLENTITIES, name) ? String.fromCodePoint(HTMLENTITIES[name]) : raw;
                const point = parseInt(decimal || hex, decimal ? 10 : 16);
                return point > 0 && point <= 0x10ffff && !(point >= 0xd800 && point <= 0xdfff)
                    ? String.fromCodePoint(point) : '\uFFFD';
            });
    }

    function isSpace(b) { return b === 32 || b === 9 || b === 10 || b === 13 || b === 12; }
    function isLetter(b) { return (b >= 65 && b <= 90) || (b >= 97 && b <= 122); }
    function toLower(b) { return (b >= 65 && b <= 90) ? b + 32 : b; }

    function parseTag(bytes, start) {
        var i = start + 1;
        var end = false;
        if (i < bytes.length && bytes[i] === 47) { end = true; i++; }
        if (i >= bytes.length || !isLetter(bytes[i])) return null;
        var nameStart = i;
        while (i < bytes.length && (isLetter(bytes[i]) || (bytes[i] >= 48 && bytes[i] <= 57) || bytes[i] === 45 || bytes[i] === 58 || bytes[i] === 46)) i++;
        var nameBytes = [];
        for (var j = nameStart; j < i; j++) nameBytes.push(toLower(bytes[j]));
        var name = utf8.decode(nameBytes);
        var attrs = Object.create(null);
        var selfClosing = false;
        while (i < bytes.length) {
            if (i % 4096 === 0 && api.cancelled()) throw { error: "cancelled", message: "Evaluation was cancelled." };
            while (i < bytes.length && isSpace(bytes[i])) i++;
            if (i >= bytes.length) return null;
            if (bytes[i] === 62) return { tag: { name: name, end: end, attributes: attrs, selfClosing: selfClosing }, next: i + 1 };
            if (bytes[i] === 47) { selfClosing = true; i++; continue; }
            selfClosing = false;
            var a = i;
            while (i < bytes.length && !isSpace(bytes[i]) && bytes[i] !== 61 && bytes[i] !== 62 && bytes[i] !== 47) i++;
            if (a === i) { i++; continue; }
            var keyBytes = [];
            for (var k = a; k < i; k++) keyBytes.push(toLower(bytes[k]));
            var key = utf8.decode(keyBytes);
            while (i < bytes.length && isSpace(bytes[i])) i++;
            var value = "";
            if (i < bytes.length && bytes[i] === 61) {
                i++;
                while (i < bytes.length && isSpace(bytes[i])) i++;
                if (i < bytes.length && (bytes[i] === 34 || bytes[i] === 39)) {
                    var quote = bytes[i]; i++;
                    var va = i;
                    while (i < bytes.length && bytes[i] !== quote) {
                        if (i % 4096 === 0 && api.cancelled()) throw { error: "cancelled", message: "Evaluation was cancelled." };
                        i++;
                    }
                    if (i >= bytes.length) return null;
                    var valBytes = [];
                    for (var v = va; v < i; v++) valBytes.push(bytes[v]);
                    value = utf8.decode(valBytes);
                    i++;
                } else {
                    var va2 = i;
                    while (i < bytes.length && !isSpace(bytes[i]) && bytes[i] !== 62) i++;
                    var valBytes2 = [];
                    for (var v2 = va2; v2 < i; v2++) valBytes2.push(bytes[v2]);
                    value = utf8.decode(valBytes2);
                }
            }
            if (!Object.hasOwn(attrs, key)) {
                attrs[key] = decodeEntities(value);
            }
        }
        return null;
    }

    var b = utf8.encode(input);
    var frames = [];
    var depth = 0;
    var hiddenName = null;
    var hiddenInner = [];
    var rawName = null;
    var hiddenOverflow = false;
    var hiddenSameDepth = 0;
    var hiddenByAttribute = false;
    var rawKeepsText = false;
    var preDepth = 0;
    var dropFirstBreak = false;
    var anchor = null; // { url, text }
    var cell = null; // PlainTextWriter or null
    var cells = [];
    var rowOpen = false;
    var tableDepth = 0;
    var rowBytes = 0;
    var work = 0;

    var writer = new PlainTextWriter();

    function current() { return cell !== null ? cell : writer; }

    function textOut(s, verbatim) {
        if (verbatim === undefined) verbatim = false;
        if (anchor !== null) anchor.text += s;
        if (cell !== null) {
            cell.write(s, verbatim);
        } else {
            writer.write(s, verbatim);
        }
    }

    function boundary(n) {
        if (cell !== null) {
            cell.pendingSpace = cell.lineContent;
        } else {
            writer.boundary(n);
        }
    }

    function endCell() {
        if (cell !== null) {
            var text = cell.finish().trim();
            rowBytes += utf8.size(text) + (cells.length === 0 ? 0 : 1);
            if (rowBytes > api.limits.maxOutputBytes - writer.bytes.length)
                throw { error: "tooLarge", message: api.limits.outputLimitMessage };
            cells.push(text);
            cell = null;
        }
    }

    function endRow() {
        endCell();
        if (rowOpen || cells.length > 0) {
            writer.boundary(1);
            writer.row(cells);
            writer.boundary(1);
        }
        cells = [];
        rowOpen = false;
        rowBytes = 0;
    }

    function close(name) {
        var index = -1;
        for (var i = frames.length - 1; i >= 0; i--) {
            if (frames[i].name === name) { index = i; break; }
        }
        if (index < 0) return;
        for (var j = frames.length - 1; j >= index; j--) {
            var frame = frames[j];
            if (frame.prefix) current().popPrefix();
            if (frame.name === "blockquote" || has(lists, frame.name) || frame.name === "dd") depth--;
        }
        frames.length = index;
    }

    function open(name, prefix, next) {
        if (next === undefined) next = 1;
        if (name === "blockquote" || has(lists, name) || name === "dd") {
            depth++;
            if (depth > api.limits.maxNestingDepth)
                throw { error: "tooLarge", message: api.limits.nestingLimitMessage };
        }
        frames.push({ name: name, prefix: prefix, next: next });
    }

    var i = 0;
    while (i < b.length) {
        work++;
        if (work % 2048 === 1 && api.cancelled())
            throw { error: "cancelled", message: "Evaluation was cancelled." };

        // Raw text mode
        if (rawName !== null) {
            var target = utf8.encode("</" + rawName);
            var rawStart = i;
            var found = false;
            while (i < b.length) {
                if (i % 4096 === 0 && api.cancelled())
                    throw { error: "cancelled", message: "Evaluation was cancelled." };
                if (b[i] === 60 && i + target.length < b.length) {
                    var matches = true;
                    for (var tj = 0; tj < target.length; tj++) {
                        if (toLower(b[i + tj]) !== target[tj]) { matches = false; break; }
                    }
                    if (matches && (isSpace(b[i + target.length]) || b[i + target.length] === 47 || b[i + target.length] === 62)) {
                        found = true;
                        break;
                    }
                }
                i++;
            }
            rawName = null;
            if (rawKeepsText) {
                rawKeepsText = false;
                var s = decodeEntities(utf8.decode(b.slice(rawStart, i)));
                // Drop first break after opening tag
                if (s.length >= 2 && s.charCodeAt(0) === 0x0D && s.charCodeAt(1) === 0x0A) s = s.substring(2);
                else if (s.length > 0 && (s.charCodeAt(0) === 0x0A || s.charCodeAt(0) === 0x0D)) s = s.substring(1);
                textOut(s, true);
            }
            if (!found) break;
        }

        // Text node
        if (b[i] !== 60) {
            var start = i;
            while (i < b.length && b[i] !== 60) {
                if (i % 4096 === 0 && api.cancelled())
                    throw { error: "cancelled", message: "Evaluation was cancelled." };
                i++;
            }
            if (hiddenName === null) {
                var s2 = decodeEntities(utf8.decode(b.slice(start, i)));
                if (dropFirstBreak) {
                    if (s2.length >= 2 && s2.charCodeAt(0) === 0x0D && s2.charCodeAt(1) === 0x0A) s2 = s2.substring(2);
                    else if (s2.length > 0 && (s2.charCodeAt(0) === 0x0A || s2.charCodeAt(0) === 0x0D)) s2 = s2.substring(1);
                    dropFirstBreak = false;
                }
                textOut(s2, preDepth > 0);
            }
            continue;
        }

        dropFirstBreak = false;

        // Comments, CDATA, processing instructions, DOCTYPE
        if (i + 1 < b.length && (b[i + 1] === 33 || b[i + 1] === 63)) {
            var comment = (i + 3 < b.length && b[i + 1] === 33 && b[i + 2] === 45 && b[i + 3] === 45);
            var cdata = false;
            if (i + 8 < b.length) {
                var cdataTarget = [60, 33, 91, 67, 68, 65, 84, 65, 91];
                cdata = true;
                for (var ci = 0; ci < 9; ci++) {
                    if (b[i + ci] !== cdataTarget[ci]) { cdata = false; break; }
                }
            }
            i += comment ? 4 : (cdata ? 9 : 2);
            while (i < b.length) {
                if (i % 4096 === 0 && api.cancelled())
                    throw { error: "cancelled", message: "Evaluation was cancelled." };
                if (comment && i + 2 < b.length && b[i] === 45 && b[i + 1] === 45 && b[i + 2] === 62) { i += 3; break; }
                if (cdata && i + 2 < b.length && b[i] === 93 && b[i + 1] === 93 && b[i + 2] === 62) { i += 3; break; }
                if (!comment && !cdata && b[i] === 62) { i += 1; break; }
                i++;
            }
            continue;
        }

        // Check valid tag start
        var validStart = false;
        if (i + 1 < b.length) {
            if (isLetter(b[i + 1])) validStart = true;
            else if (b[i + 1] === 47 && i + 2 < b.length && isLetter(b[i + 2])) validStart = true;
        }
        if (!validStart) {
            if (hiddenName === null) textOut("<", preDepth > 0);
            i++;
            continue;
        }

        var result = parseTag(b, i);
        if (!result) break;
        var t = result.tag;
        i = result.next;

        // Inside hidden element
        if (hiddenName !== null) {
            var impliedEnds = hiddenByAttribute && !hiddenOverflow && !arrContains(hiddenInner, "template") && !arrContains(hiddenInner, "svg") && !arrContains(hiddenInner, "math");
            if (t.end) {
                if (!hiddenOverflow) {
                    var openIdx = hiddenInner.lastIndexOf(t.name);
                    if (openIdx >= 0) {
                        // Decrement hiddenSameDepth for matching elements
                        for (var si = openIdx; si < hiddenInner.length; si++) {
                            if (hiddenInner[si] === hiddenName) hiddenSameDepth--;
                        }
                        hiddenInner = hiddenInner.slice(0, openIdx);
                        continue;
                    }
                }
                if (t.name === hiddenName) {
                    if (hiddenSameDepth > 0) {
                        hiddenSameDepth--;
                    } else {
                        hiddenName = null;
                        hiddenInner = [];
                        hiddenOverflow = false;
                    }
                    continue;
                }
                if (impliedEnds && has(enclosingEnds, t.name)) {
                    // Fall through: enclosing end closes hidden
                } else {
                    continue;
                }
            } else if (!(impliedEnds && startTagEnds(hiddenName, t.name, hiddenInner))) {
                if (has(raw, t.name) || t.name === "textarea") { rawName = t.name; rawKeepsText = false; }
                var inForeignContent = has(foreignRoots, hiddenName);
                if (!inForeignContent) {
                    for (var fi = 0; fi < hiddenInner.length; fi++) {
                        if (has(foreignRoots, hiddenInner[fi])) { inForeignContent = true; break; }
                    }
                }
                var selfClosingForeign = t.selfClosing && (inForeignContent || has(foreignRoots, t.name));
                if (!selfClosingForeign && !has(voidEls, t.name)) {
                    if (t.name === hiddenName) hiddenSameDepth++;
                    if (hiddenInner.length < maxHiddenInner) hiddenInner.push(t.name);
                    else hiddenOverflow = true;
                }
                continue;
            }
            hiddenName = null;
            hiddenInner = [];
            hiddenOverflow = false;
            hiddenSameDepth = 0;
        }

        // Raw text elements
        if (!t.end && has(raw, t.name)) { rawName = t.name; continue; }
        if (!t.end && t.name === "textarea" && isHiddenByAttribute(t)) { rawName = t.name; rawKeepsText = false; continue; }
        if (!t.end && (has(hidden, t.name) || isHiddenByAttribute(t))) {
            if (opensHiddenContent(t)) {
                hiddenName = t.name;
                hiddenInner = [];
                hiddenOverflow = false;
                hiddenSameDepth = 0;
                hiddenByAttribute = !has(hidden, t.name);
            }
            continue;
        }

        // Process visible tags
        var nestedList = has(lists, t.name) && (function () {
            for (var ni = 0; ni < frames.length; ni++) {
                if (frames[ni].name === "li" || frames[ni].name === "dd" || frames[ni].name === "dt") return true;
            }
            return false;
        })();
        var amount = has(paragraphs, t.name) ? (nestedList ? 1 : 2) : (has(lines, t.name) ? 1 : 0);

        if (t.end) {
            switch (t.name) {
                case "a":
                    if (anchor !== null && showLinks) textOut(markupLinkSuffix(anchor.text, anchor.url));
                    anchor = null;
                    break;
                case "pre":
                case "listing":
                    if (preDepth > 0) preDepth--;
                    break;
                case "td":
                case "th":
                case "tr":
                    if (tableDepth > 1) {
                        boundary(1);
                    } else if (t.name === "tr") {
                        endRow();
                    } else {
                        endCell();
                    }
                    break;
                case "table":
                    if (tableDepth > 1) {
                        tableDepth--;
                        boundary(1);
                    } else {
                        tableDepth = 0;
                        endRow();
                    }
                    break;
            }
            close(t.name);
            if (amount > 0) boundary(amount);
            continue;
        }

        // Start tags
        if (t.name === "li") {
            var liIdx = -1;
            var listIdx = -1;
            for (var li2 = frames.length - 1; li2 >= 0; li2--) {
                if (frames[li2].name === "li" && liIdx < 0) liIdx = li2;
                if (has(lists, frames[li2].name) && listIdx < 0) listIdx = li2;
            }
            if (liIdx >= 0 && liIdx > listIdx) close("li");
        }

        if (amount > 0) boundary(amount);

        switch (t.name) {
            case "br":
                if (cell !== null) { cell.pendingSpace = cell.lineContent; }
                else writer.hardBreak();
                break;
            case "blockquote":
                current().pushQuote();
                open(t.name, true);
                break;
            case "ul":
            case "ol":
            case "menu":
            case "dl":
                var startAttr = t.attributes["start"];
                const nextVal = ordinal(startAttr, 1n);
                open(t.name, false, nextVal);
                break;
            case "li":
                var marker = "\u2022 ";
                var olIdx = -1;
                for (var oi = frames.length - 1; oi >= 0; oi--) {
                    if (has(lists, frames[oi].name)) { olIdx = oi; break; }
                }
                if (olIdx >= 0 && frames[olIdx].name === "ol") {
                    const n = ordinal(t.attributes["value"], frames[olIdx].next);
                    marker = n + ". ";
                    frames[olIdx].next = n === 9223372036854775807n ? n : n + 1n;
                }
                current().beginItem(marker);
                open("li", true);
                break;
            case "dd":
                current().pushIndent(2);
                open("dd", true);
                break;
            case "dt":
                close("dt");
                open("dt", false);
                break;
            case "pre":
            case "listing":
                preDepth++;
                dropFirstBreak = true;
                break;
            case "textarea":
                rawName = "textarea";
                rawKeepsText = true;
                break;
            case "img":
                var alt = (t.attributes["alt"] || "").trim();
                if (alt.length > 0) textOut("[" + alt + "]");
                break;
            case "a":
                anchor = { url: t.attributes["href"] || "", text: "" };
                break;
            case "table":
                tableDepth++;
                break;
            case "tr":
                if (tableDepth > 1) { boundary(1); }
                else { endRow(); rowOpen = true; }
                break;
            case "td":
            case "th":
                if (tableDepth > 1) { boundary(1); }
                else { endCell(); cell = new PlainTextWriter(); rowOpen = true; }
                break;
        }
    }

    // End of input
    if (anchor !== null && showLinks) {
        textOut(markupLinkSuffix(anchor.text, anchor.url));
        anchor = null;
    }
    endRow();

    return writer.finish();
}
