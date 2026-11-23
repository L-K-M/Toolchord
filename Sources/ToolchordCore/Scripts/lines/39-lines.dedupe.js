/* @toolchord
{
  "apiVersion": 1,
  "id": "lines.dedupe",
  "title": "Remove Duplicate Lines",
  "summary": "Keep the first occurrence of each line",
  "options": [
    {"id": "caseSensitive", "label": "Case-sensitive", "defaultValue": "true"},
    {"id": "trim", "label": "Ignore surrounding spaces", "defaultValue": "false"}
  ],
  "palette": {
    "group": "lines", "groupTitle": "Lines",
    "aliases": ["dedupe", "deduplicate", "unique lines", "uniq", "remove duplicates"],
    "symbol": "line.3.horizontal.decrease", "copyNoun": "lines",
    "suggestions": [{"when": ["multiline"], "score": 35}]
  }
}
*/
function preview(input, options, api) {
    return transformLines(input, options, api, "dedupe");
}

// @shared lines.sort/lines
function transformLines(input, options, api, operation) {
    const verbs = {sort: "sort", dedupe: "deduplicate", reverse: "reverse"};
    if (input == null) return {error: "needsInput", message: "Paste text to " + verbs[operation] + "."};
    if (api.cancelled()) return {error: "cancelled", message: ""};
    if (!input.length) return {primaryText: "", status: operation === "dedupe" ? "No duplicates" : (operation === "sort" ? "Sorted" : "Reversed") + " 0 lines"};
    const firstBreak = input.match(/\r\n|\r|\n/);
    const lineBreak = firstBreak ? firstBreak[0] : "\n";
    const trailing = /[\r\n]$/.test(input);
    const lines = input.split(/\r\n|\r|\n/);
    if (trailing) lines.pop();
    let kept = lines, status;
    if (operation === "sort") {
        const sensitive = options.caseSensitive === "true", descending = options.order === "desc";
        const indices = lines.map((_, i) => i);
        indices.sort((a, b) => {
            const comparison = api.native("text.compare", lines[a], lines[b], sensitive);
            return comparison === 0 ? a - b : descending ? -comparison : comparison;
        });
        kept = indices.map(i => lines[i]);
        status = "Sorted " + kept.length + (kept.length === 1 ? " line" : " lines");
    } else if (operation === "dedupe") {
        const sensitive = options.caseSensitive !== "false", trim = options.trim === "true";
        const seen = new Set();
        kept = [];
        for (let i = 0; i < lines.length; i++) {
            if ((i & 4095) === 0 && api.cancelled()) return {error: "cancelled", message: ""};
            // Foundation's .whitespaces excludes line breaks, which were
            // already split above. Strings stay byte-distinct: do not normalize.
            let key = trim ? lines[i].replace(/^[\p{Zs}\t\u200B]+|[\p{Zs}\t\u200B]+$/gu, "") : lines[i];
            if (!sensitive) key = key.toLowerCase();
            if (!seen.has(key)) { seen.add(key); kept.push(lines[i]); }
        }
        const removed = lines.length - kept.length;
        status = removed ? "Removed " + removed + (removed === 1 ? " duplicate" : " duplicates") : "No duplicates";
    } else {
        kept = lines.reverse();
        status = "Reversed " + kept.length + (kept.length === 1 ? " line" : " lines");
    }
    if (api.cancelled()) return {error: "cancelled", message: ""};
    return {primaryText: kept.join(lineBreak) + (trailing ? lineBreak : ""), status};
}
// @endshared
