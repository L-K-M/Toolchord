/* @toolchord
{
  "apiVersion": 1,
  "id": "case.kebab",
  "title": "Convert to kebab-case",
  "summary": "Lowercase words joined by hyphens",
  "palette": {
    "group": "case", "groupTitle": "Case",
    "aliases": ["kebab case", "dash case", "hyphen case", "param case"],
    "glyph": "Aa", "copyNoun": "text",
    "suggestions": [{"when": ["plain", "words"], "score": 40}]
  }
}
*/
function preview(input, options, api) {
    return convertCase(input, options, api, "kebab");
}

// @shared case.camel/case
// Unicode boundaries and casing are evaluated here; ICU transliteration is
// the one platform service needed to preserve the existing slug contract.
function convertCase(input, options, api, style) {
    if (input == null) return {error: "needsInput", message: "Paste text to convert."};
    const statuses = {camel: "camelCase", pascal: "PascalCase", snake: "snake_case", kebab: "kebab-case", constant: "CONSTANT_CASE", title: "Title Case", sentence: "Sentence case", lower: "lowercase", upper: "UPPERCASE", slug: "Slug"};
    const alphabetic = /\p{Alphabetic}/u, numeric = /\p{N}/u, mark = /\p{M}/u;
    const letter = /\p{L}/u, decimal = /\p{Nd}/u;
    const lower = /\p{Lowercase}/u, upper = /\p{Uppercase}/u, whitespace = /\p{White_Space}/u;
    const numericTypes = new Map();
    function numericType(c) {
        if (decimal.test(c)) return "decimal";
        if (c.codePointAt(0) < 128) return "";
        if (!numericTypes.has(c)) numericTypes.set(c, api.native("text.numericType", c));
        return numericTypes.get(c);
    }
    const isNumeric = c => numeric.test(c) || numericType(c) !== "";
    const isProseContent = c => letter.test(c) || mark.test(c) || ["decimal", "digit"].includes(numericType(c));
    const cancelled = () => api.cancelled();
    const failed = () => ({error: "cancelled", message: ""});
    function capitalize(word) {
        const chars = Array.from(word);
        return chars.length ? chars[0].toUpperCase() + chars.slice(1).map(c => c.toLowerCase()).join("") : word;
    }
    function splitWords(content) {
        const chars = Array.from(content), words = [];
        let word = [];
        for (let i = 0; i < chars.length; i++) {
            const c = chars[i];
            if (!(alphabetic.test(c) || isNumeric(c) || mark.test(c))) {
                if (word.length) { words.push(word.join("")); word = []; }
                continue;
            }
            if (word.length) {
                const prev = word[word.length - 1];
                if (((isNumeric(prev) || lower.test(prev)) && upper.test(c)) ||
                    (upper.test(prev) && upper.test(c) && i + 1 < chars.length && lower.test(chars[i + 1]))) {
                    words.push(word.join("")); word = [];
                }
            }
            word.push(c);
        }
        if (word.length) words.push(word.join(""));
        return words;
    }
    function identifierLine(chars) {
        let boundary = false;
        for (let i = 0; i < chars.length; i++) {
            const c = chars[i];
            if (c === "_" || c === "-") { boundary = true; continue; }
            if (whitespace.test(c) || !isProseContent(c)) return false;
            if (i && lower.test(chars[i - 1]) && upper.test(c)) boundary = true;
        }
        return boundary;
    }
    function prose(chars) {
        const hasLowercase = chars.some(c => lower.test(c));
        const result = [];
        let sentenceStart = true, i = 0;
        function inWord(index) {
            const c = chars[index];
            return isProseContent(c) || ((c === "'" || c === "’") && index > 0 && index + 1 < chars.length && letter.test(chars[index - 1]) && letter.test(chars[index + 1]));
        }
        while (i < chars.length) {
            if (!inWord(i)) {
                if (".!?".includes(chars[i])) {
                    let next = i + 1;
                    while (next < chars.length && ["'", '"', "’", "”", ")", "]"].includes(chars[next])) next++;
                    if (next < chars.length && whitespace.test(chars[next])) sentenceStart = true;
                }
                result.push(chars[i++]);
                continue;
            }
            const start = i++;
            while (i < chars.length && inWord(i)) i++;
            const word = chars.slice(start, i), letters = word.filter(c => letter.test(c));
            if (!letters.length) { result.push(word.join("")); continue; }
            const allUpper = letters.every(c => upper.test(c));
            const preserve = allUpper ? letters.length >= 2 && hasLowercase : letters.slice(1).some(c => upper.test(c));
            if (preserve) result.push(word.join(""));
            else {
                const pronounI = (word[0] === "i" || word[0] === "I") && (word.length === 1 || word[1] === "'" || word[1] === "’");
                const uppercaseFirst = style === "title" || sentenceStart || pronounI;
                let first = true;
                for (const c of word) {
                    if (!letter.test(c)) { result.push(c); continue; }
                    result.push(uppercaseFirst && first ? c.toUpperCase() : c.toLowerCase());
                    first = false;
                }
            }
            sentenceStart = false;
        }
        return result.join("");
    }
    function transform(content) {
        if (style === "lower") return content.toLowerCase();
        if (style === "upper") return content.toUpperCase();
        if (style === "slug") return (api.native("text.transliterate", content).toLowerCase().match(/[a-z0-9]+/g) || []).join("-");
        if ((style === "title" || style === "sentence") && !identifierLine(Array.from(content))) return prose(Array.from(content));
        const words = splitWords(content);
        switch (style) {
        case "camel": return words.map((w, i) => i ? capitalize(w) : w.toLowerCase()).join("");
        case "pascal": return words.map(capitalize).join("");
        case "snake": return words.map(w => w.toLowerCase()).join("_");
        case "kebab": return words.map(w => w.toLowerCase()).join("-");
        case "constant": return words.map(w => w.toUpperCase()).join("_");
        case "title": return words.map(capitalize).join(" ");
        case "sentence": return words.map((w, i) => i ? w.toLowerCase() : capitalize(w)).join(" ");
        default: return content;
        }
    }
    let result = [], start = 0, iterations = 0;
    const breaks = /\r\n|\r|\n/g;
    let match;
    while ((match = breaks.exec(input)) !== null) {
        if ((iterations++ & 255) === 0 && cancelled()) return failed();
        result.push(transform(input.slice(start, match.index)), match[0]);
        start = breaks.lastIndex;
    }
    if (cancelled()) return failed();
    result.push(transform(input.slice(start)));
    const primaryText = result.join("");
    let bytes = 0;
    for (const c of primaryText) { const cp = c.codePointAt(0); bytes += cp < 128 ? 1 : cp < 2048 ? 2 : cp < 65536 ? 3 : 4; }
    if (bytes > api.limits.maxOutputBytes) return {error: "tooLarge", message: api.limits.outputLimitMessage};
    return {primaryText, status: statuses[style]};
}
// @endshared
