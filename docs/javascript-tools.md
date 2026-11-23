# JavaScript tools

Search for **Make Custom Tool** in the palette. Describe the tool, choose its generation provider, and run the draft on sample input. Inspect the preview and any action outputs before saving. The saved title becomes searchable immediately. Select an existing tool and choose **Update** to describe the changes you want. You can also edit its JavaScript directly.

| Provider | Setup and model choice |
| --- | --- |
| Apple Intelligence | Available offline on eligible Macs with Apple Intelligence enabled on macOS 26 or later. |
| Codex CLI or Claude Code | Install and sign in to the CLI, then use the refresh button in the editor. Choose **List Models**, enter a model ID, or leave the field empty for the harness default. The CLI must support noninteractive text generation with its tools disabled. |
| Ollama | Start the Ollama server on this Mac, choose **List Models**, and select a model. Toolchord connects over loopback. Ollama may forward requests for a cloud-backed model. |
| Custom endpoint | Enter the OpenAI-compatible base URL, such as `https://example.com/v1` or `http://127.0.0.1:11434/v1`. Choose **Use Address**. Save an optional bearer key, then list models or enter one. Toolchord uses `GET /models` and `POST /chat/completions` relative to that base. |

The editor remembers model choices by provider and endpoint. The native authoring service stores each endpoint’s key in macOS Keychain. Generating with an external provider sends your description and the current definition when revising. Sample inputs, trial results, and palette contents stay on the Mac. CLI and endpoint generation, hand editing, testing and saving work on macOS 14 or later.

## API version 1

A tool is one UTF-8 `.js` file. Its first line is `/* @toolchord`, followed by a JSON object and a closing `*/` on its own line. The JavaScript below the comment defines `preview(input, options, api)` and any helpers. Toolchord reads the header to build controls before the script runs. For example, **Format JSON** declares its **Indent** picker there and reads the chosen string through `options.indent`.

The required fields are `apiVersion`, `id`, and `title`. To include a literal `*/` inside a header string, write `*\/` in its JSON.

| Field | Meaning |
| --- | --- |
| `apiVersion` | The integer `1`. |
| `id`, `title`, `summary` | New tools get a stable `custom.` identifier. A customized built-in keeps its catalog ID. Title and summary appear in the palette. |
| `options` | Optional settings. A toggle has `id`, `label`, and a string `defaultValue` of `"true"` or `"false"`. A choice also has `choices: [{id, label}, …]`. The default must be one of its IDs. |
| `regenerateTitle` | Optional button label for a generator. A generator gets `null` input and a stable `api.seed`. |
| `actions` | An array of `{id, title}` entries for explicit action buttons. |
| `capabilities` | An array. Declare `"clipboard.write"` when an action writes text. |
| `palette` | Optional display and discovery metadata, including aliases, group, icon, copy labels, and suggestion rules. |

The optional `palette` object accepts `group` (group ID), `groupTitle`, `aliases` (search terms), and either `glyph` (text) or `symbol` (an SF Symbol name). Set `copyNoun` to label the copy command, or use `copyLabels` to select the noun by option ID and value. For example, `"copyLabels": {"format": {"hex": "hex value"}}` labels the command **Copy hex value & Close** when `format` is `"hex"`.

To suggest the tool for matching input, add `"suggestions": [{"when": ["json"], "score": 80}]` inside `palette`. Each rule matches all its conditions. Use an input kind from [InputKind](../Sources/ToolchordCore/Detection/InputProfile.swift) or `plain`, and prefix a condition with `!` to exclude it. The first matching rule supplies the score from 0 to 100.

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

Save this example as `compare-lists.js` and open it in Toolchord. Give it two lists separated by a blank line. The **Pretty JSON** toggle changes the preview, and **Copy Additions** copies the added lines.

```javascript
/* @toolchord
{
  "apiVersion": 1,
  "id": "custom.compareLists",
  "title": "Compare Lists",
  "options": [{"id": "pretty", "label": "Pretty JSON", "defaultValue": "true"}],
  "actions": [{"id": "copyAdded", "title": "Copy Additions"}],
  "capabilities": ["clipboard.write"]
}
*/
function compare(input) {
    const lists = input.replace(/\r\n?/g, "\n").split("\n\n");
    if (lists.length !== 2) throw Error("Separate two lists with a blank line.");
    const [before, after] = lists.map(list => new Set(list.split("\n").filter(Boolean)));
    return {
        added: [...after].filter(id => !before.has(id)),
        removed: [...before].filter(id => !after.has(id))
    };
}

function preview(input, options) {
    const {added, removed} = compare(input);
    return {
        primaryText: JSON.stringify({added, removed}, null, options.pretty === "true" ? 2 : 0),
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

Each bundled command ships as a self-contained JavaScript file under `Sources/ToolchordCore/Scripts/`. The app runs the signed built-in directly. Samples and local edits run in a separate, bounded process.

Some built-ins contain the same helper. A `// @shared tool.id/helper` marker identifies its source. After editing the helper in that tool, run `python3 scripts/sync-tool-helpers.py` to refresh its copies. Run it with `--check` to verify they match. Exported files include the helpers they use.

### Working with bundled tools in the editor

Open **Make Custom Tool** and select a command under **Built-In Tools**, or choose **Edit Tool…** from the palette’s Actions menu. **Script** shows the complete file, including its metadata, functions, and helpers.

Edit the header or a function, run a sample with **⌘↵**, then save with **⌘S**. The library stores the customization on this Mac under the command’s original ID. Only the selected command changes. Samples and saved customizations run in the same bounded worker as other authored tools. **Revert Changes** discards unsaved edits. **Restore Built-In Version** removes the saved customization and returns the palette to the version bundled with the current app.

Run `make test` for tool fixtures, session behavior, the worker and editor/store tests. To exercise prompt generation with a real installed Apple Intelligence model, run `TOOLCHORD_TEST_LOCAL_MODEL=1 swift test --filter LiveAuthoringTests` on a compatible Mac. That check generates a tool, tries it on a sample, saves it, asks the model to revise it, and runs the reloaded definition.
