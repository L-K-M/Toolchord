# Tool option layout checks

Run `make snapshots` and inspect these images in `build/snapshots`:

- `search-number-options`, `tool-number-options` and
  `tool-number-options-narrow`: Read as and Add prefix stay within the
  panel, with readable labels and a complete command title.
- `search-random-options`, `tool-random-options` and
  `tool-random-options-narrow`: Length and Characters remain usable in the
  preview and the expanded tool. Compact menus replace segmented controls
  when the complete option row cannot fit.
- `search-json`, `search-json-light`, `search-json-invalid` and `tool-json`:
  ordinary results, errors and indentation controls retain their layout.

The fixtures select the command explicitly so search
ranking changes cannot silently turn a layout check into a different tool.

## Interactive checks

1. Open Convert to Hex with input `42`. Toggle Add prefix and choose each
   Read as value in both search and expanded modes. Verify the preview
   changes and Copy remains unavailable until the new result settles.
2. Open Generate Random String. Change Length and Characters using the
   keyboard, including the compact menus in the search preview. Verify the
   selected options and generated value survive opening the expanded tool.
3. Repeat with keyboard navigation and VoiceOver. Each option must retain
   its name and current selection, and the command title must remain readable.

Before the layout fix, the expanded number fixtures clipped the Add prefix
label outside the header. These visual fixtures and interactive steps cover
the SwiftUI layout boundary; ordinary
tool and session tests alone cannot establish that controls are visible.
