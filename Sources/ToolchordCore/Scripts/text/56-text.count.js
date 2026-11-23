/* @toolchord
{
  "apiVersion": 1,
  "id": "text.count",
  "title": "Count Characters",
  "summary": "Characters, words, lines, and bytes",
  "palette": {
    "group": "inspect", "groupTitle": "Text",
    "aliases": ["count", "word count", "character count", "char count", "length",
                "string length", "text statistics", "count words"],
    "symbol": "textformat.123", "copyNoun": "character count",
    "suggestions": [
      {"when": ["plain", "multiline"], "score": 45},
      {"when": ["plain"], "score": 25}
    ]
  }
}
*/
function preview(input, options, api) {
    if (input == null) return {error: "needsInput", message: "Paste text to count."};
    // The platform supplies Unicode segmentation and Character.isWhitespace;
    // count aggregation and result construction remain in this script.
    const classes = api.native("text.graphemeClasses", input);
    const characters = classes.length;
    let words = 0, inWord = false;
    for (let i = 0; i < classes.length; i++) {
        if ((i & 4095) === 0 && api.cancelled()) return {error: "cancelled", message: ""};
        if (classes[i] === "W") inWord = false;
        else if (!inWord) { words++; inWord = true; }
    }
    const breaks = input.match(/\r\n|\r|\n/g);
    const lines = !input.length ? 0 : (breaks ? breaks.length : 0) + (/[\r\n]$/.test(input) ? 0 : 1);
    let bytes = 0, scalars = 0;
    for (const c of input) { const cp = c.codePointAt(0); bytes += cp < 128 ? 1 : cp < 2048 ? 2 : cp < 65536 ? 3 : 4; scalars++; }
    const field = (id, label, value, note) => Object.assign({id, label, value: String(value)}, note ? {note} : {});
    return {
        primaryText: String(characters),
        status: characters + (characters === 1 ? " character" : " characters"),
        presentation: "fields",
        fields: [field("characters", "Characters", characters), field("words", "Words", words), field("lines", "Lines", lines), field("utf8", "UTF-8 bytes", bytes), field("utf16", "UTF-16 code units", input.length, "JavaScript string length"), field("scalars", "Unicode scalars", scalars)]
    };
}
