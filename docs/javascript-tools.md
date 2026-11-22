# JavaScript tools

Open the palette, search for **Make Custom Tool**, and press Return. Describe the operation, choose **Generate on This Mac**, and try the draft with sample input. Inspect the preview and any action outputs before saving. The saved title becomes searchable immediately. Reopen the editor and select the existing tool to revise it under the same ID. You can also edit its JavaScript directly.

Prompt generation uses Apple’s on-device Foundation Models framework on an eligible Mac running macOS 26 or later with Apple Intelligence enabled and the model ready. Hand editing, testing, saving, and running tools work on macOS 14 or later. Generated code can misunderstand a request. Try representative input, including an empty value or an unusual character that matters to the operation.

## API version 1

A saved JSON document has these fields:

| Field | Meaning |
| --- | --- |
| `apiVersion` | The integer `1`. |
| `id`, `title`, `summary` | The editor assigns a stable `custom.` identifier. Title and summary appear in the palette. |
| `source` | Synchronous JavaScript containing a global `function preview(input, options, api)`. |
| `options` | Optional settings. A toggle has `id`, `label`, and a string `defaultValue` of `"true"` or `"false"`. A choice also has `choices: [{id, label}, …]`. The default must be one of its IDs. |
| `regenerateTitle` | Optional button label for a generator. A generator gets `null` input and a stable `api.seed`. |
| `actions` | An array of `{id, title}` entries for explicit action buttons. |
| `capabilities` | An array. Declare `"clipboard.write"` when an action writes text. |

**Preview** runs when input, options, or selection change. An attached empty string is a valid input. Options are an object of resolved string values keyed by ID. Return text directly or return an object with the following properties:

| Property | Meaning |
| --- | --- |
| `primaryText`, `status` | The exact text for Copy & Close, plus a short status label. Empty output can be copied. |
| `fields` | Optional labeled outputs with unique `id`, `label`, `value`, optional `note`, `tone`, `isCopyable`, and `isMonospaced`. |
| `presentation`, `syntax` | Use `"fields"` for an inspector or `"text"` for text. Syntax can be `"plain"`, `"json"`, or `"xml"`. |
| `warnings`, `statusTone` | An array of messages and an optional `"warning"` status tone. |
| `swatch`, `sensitivity` | An optional `{red, green, blue, alpha}` color in 0…1 and `"normal"` or `"secret"` for copied output. |

A custom preview can show up to 256 fields and 128 warnings. Individual status and diagnostic messages can contain up to 4 KiB of UTF-8 text.

Throw an Error for an invalid input, or return `{error, message, location?}`. Error kinds are `invalid`, `needsInput`, `unsupported`, and `tooLarge`. A location has one-based `line` and `column`.

**Actions** run through `function perform(action, input, options, api)`. Use `api.clipboard.writeText(text)` once, optionally passing `"secret"` as its second argument. Toolchord commits the write after the action succeeds and the originating selection and input are still current. Trying an action in the editor shows the requested text in memory. A script receives pasted text only through its input. Clipboard reads belong to the app’s explicit Paste command.

Here is the source of a tool with an action whose ID is `copyAdded`. Given two lists separated by a blank line, it previews the additions and removals and lets you copy just the additions.

```javascript
function compare(input) {
    const lists = input.replace(/\r\n?/g, "\n").split("\n\n");
    if (lists.length !== 2) throw Error("Separate two lists with a blank line.");
    const [before, after] = lists.map(list => new Set(list.split("\n").filter(Boolean)));
    return {
        added: [...after].filter(id => !before.has(id)),
        removed: [...before].filter(id => !after.has(id))
    };
}

function preview(input) {
    const {added, removed} = compare(input);
    return {
        primaryText: JSON.stringify({added, removed}, null, 2),
        status: added.length + " added, " + removed.length + " removed",
        syntax: "json"
    };
}

function perform(action, input, options, api) {
    if (action === "copyAdded") api.clipboard.writeText(compare(input).added.join("\n"));
}
```

**Generators** may define `function makeSeed(options, api)` returning a string. Here `api.entropy` contains 512 system-generated random bytes, `api.now` is the captured Unix time in milliseconds, and `api.id` identifies the command. The host captures fresh entropy on selection or regeneration. Given the same captured arguments, return the same seed. Omitting this function gives the tool a stable hexadecimal seed. Use `api.seed` in preview and actions.

**The runtime** provides language built-ins such as arrays, maps, BigInt, regular expressions and Date, plus `api.id`, `api.seed`, `api.now` (Unix milliseconds), `api.timeZone` (an identifier), `api.cancelled()`, and `api.limits`. It runs synchronous functions in fresh JavaScriptCore contexts. Browser DOM, Node modules, file access, and network requests are outside this API. A saved or generated tool executes in a disposable worker with a three-second wall-clock budget. The app clears its sample and results when the editor closes. Only tool definitions are saved in the app container under Application Support/Toolchord/Custom Tools.

### Native operations

Call `api.native(name, ...args)` from a preview or action. These operations run on the supplied values.

| Name | Arguments | Result |
| --- | --- | --- |
| `crypto.digest` | Algorithm (`sha256`, `sha512`, `sha1`, or `md5`), text | Lowercase hexadecimal digest of the UTF-8 bytes. |
| `crypto.hkdfHex` | Lowercase hexadecimal key, UTF-8 context, output length in bytes (1–4096) | Lowercase hexadecimal HKDF-SHA256 output. |
| `clock.offsetSeconds` | Unix milliseconds | Seconds east of UTC in the evaluation’s time zone at that instant. |
| `text.transliterate` | Text | Latin transliteration followed by conversion to ASCII where available. |
| `text.byteCountLabel` | Text | Display label for its UTF-8 byte count. |
| `text.compare` | Two strings, case-sensitive boolean | `-1`, `0`, or `1` using numeric ordering. |
| `text.numericType` | Text | Unicode numeric type of the first scalar as `decimal`, `digit`, `numeric`, or an empty string. |
| `text.graphemeClasses` | Text | One ASCII marker per extended grapheme, `W` for whitespace and `O` otherwise. |
| `markdown.parse` | Markdown text | A document tree or an error object with `error` and `message`. |

A Markdown tree has a `nodes` array in breadth-first order. Read the root at index zero. Each node contains its block `kind`, child indices in `children`, and inline `runs`. A run contains `text` and can include a link, image, or formatting flags such as `strong` and `emphasis`. The bundled Markdown tool illustrates how to render every block and run.

## Bundled tools and verification

The catalog in `Sources/ToolchordCore/Scripts/catalog.json` stores command IDs, display order, search terms, suggestion rules and option definitions. Its script names select JavaScript resources in the same directory. For a family with shared JavaScript libraries, list their basenames in the manifest’s `libraries` object in load order. The runtime runs the bundled preview or generator function with the same argument and result conventions as a local tool. The app runs its signed bundled code directly and isolates editable code in a separate process.

Run `make test` for tool fixtures, session behavior, the worker and editor/store tests. To exercise prompt generation with a real installed model, run `TOOLCHORD_TEST_LOCAL_MODEL=1 swift test --filter LiveAuthoringTests` on a compatible Mac. That check generates a tool, tries it on a sample, saves it, asks the model to revise it, and runs the reloaded definition.
