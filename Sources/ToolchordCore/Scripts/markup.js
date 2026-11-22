function preview(input, options, api) {
  try {
    if (api.cancelled()) return {error: 'cancelled'};
    if (api.id === 'html.plaintext') {
      return {primaryText: htmlToText(input, options.links === 'true', api), status: 'Plain text'};
    }
    const parsed = api.native('markdown.parse', input);
    if (parsed.error) return parsed;
    const asText = api.id === 'markdown.plaintext';
    const limit = asText
      ? Math.max(api.limits.maxOutputBytes * 4, api.limits.maxInputBytes * 8)
      : api.limits.maxOutputBytes;
    const nodes = parsed.nodes;
    for (const node of nodes) node.children = node.children.map(index => nodes[index]);
    const html = renderMarkdown(nodes[0], limit, asText, api);
    return asText
      ? {primaryText: htmlToText(html, options.links === 'true', api), status: 'Plain text'}
      : {primaryText: html, status: 'Rendered HTML', syntax: 'xml'};
  } catch (error) {
    if (error.error) return error;
    throw error;
  }
}

// Nodes: { kind, children:[], runs:[], task?:bool, loose?:bool, value?:number, alignments?:[string|null] }
// Inline keys: text, link, image, emphasis, strong, strike, code, soft, hard, html,
//              linkEmphasis, linkStrong, linkStrike

function renderMarkdown(root, limit, taskMarkersAsText, api) {
  var bytes = [];
  var pendingLF = false;

  function endsInLF() { return pendingLF || (bytes.length > 0 && bytes[bytes.length - 1] === 10); }

  function flushLF() {
    if (pendingLF) {
      if (bytes.length >= limit) throw { error: "tooLarge", message: api.limits.outputLimitMessage };
      bytes.push(10);
      pendingLF = false;
    }
  }

  function append(text) {
    if (api.cancelled()) throw { error: "cancelled", message: "" };
    if (text.length === 0) return;
    flushLF();
    var encoded = utf8.encode(text);
    var finalLF = (encoded.length > 0 && encoded[encoded.length - 1] === 10);
    var count = encoded.length - (finalLF ? 1 : 0);
    if (count > limit - bytes.length) throw { error: "tooLarge", message: api.limits.outputLimitMessage };
    for (var i = 0; i < count; i++) {
      bytes.push(encoded[i]);
    }
    pendingLF = finalLF;
  }

  function cr() {
    if ((bytes.length > 0 || pendingLF) && !endsInLF()) {
      append("\n");
    }
  }

  function escaped(text) {
    var encoded = utf8.encode(text);
    for (var i = 0; i < encoded.length; i++) {
      if (i % 4096 === 0 && api.cancelled()) throw { error: "cancelled", message: "" };
      var b = encoded[i];
      switch (b) {
        case 38: append("&amp;"); break;
        case 60: append("&lt;"); break;
        case 62: append("&gt;"); break;
        case 34: append("&quot;"); break;
        default:
          flushLF();
          if (bytes.length >= limit) throw { error: "tooLarge", message: api.limits.outputLimitMessage };
          bytes.push(b);
      }
    }
  }

  function inline(runs, drop) {
    var stack = [];
    var remaining = drop || 0;

    function closeElement(element) {
      append("</" + element.tag + ">");
    }

    for (var ri = 0; ri < runs.length; ri++) {
      var run = runs[ri];
      if (remaining > 0) {
        // Swift: run.text.utf8.count and dropFirst(count) on UTF-8 bytes
        var utf8Bytes = utf8.encode(run.text);
        var byteCount = Math.min(remaining, utf8Bytes.length);
        var restBytes = utf8Bytes.slice(byteCount);
        run = Object.create(run);
        run.text = utf8.decode(restBytes);
        remaining -= byteCount;
        if (run.text.length === 0) continue;
      }

      // Build wanted elements
      var wanted = [];
      if (run.strike) wanted.push({ tag: "del", url: null, inner: false });
      if (run.emphasis) wanted.push({ tag: "em", url: null, inner: false });
      if (run.strong) wanted.push({ tag: "strong", url: null, inner: false });
      if (run.link != null) wanted.push({ tag: "a", url: run.link, inner: false });
      if (run.linkStrike) wanted.push({ tag: "del", url: null, inner: true });
      if (run.linkEmphasis) wanted.push({ tag: "em", url: null, inner: true });
      if (run.linkStrong) wanted.push({ tag: "strong", url: null, inner: true });

      // Find how many stack elements to keep
      var keep = stack.length;
      for (var ki = 0; ki < stack.length; ki++) {
        var found = false;
        for (var wi = 0; wi < wanted.length; wi++) {
          if (elementsEqual(stack[ki], wanted[wi])) { found = true; break; }
        }
        if (!found) { keep = ki; break; }
      }

      // Outer formatting opens outside the link
      var hasOuterMissing = false;
      for (var wo = 0; wo < wanted.length; wo++) {
        if (wanted[wo].tag !== "a" && !wanted[wo].inner) {
          var inStack = false;
          for (var sk = 0; sk < keep; sk++) {
            if (elementsEqual(stack[sk], wanted[wo])) { inStack = true; break; }
          }
          if (!inStack) { hasOuterMissing = true; break; }
        }
      }
      if (hasOuterMissing) {
        for (var li = 0; li < keep; li++) {
          if (stack[li].tag === "a") { keep = li; break; }
        }
      }

      // Close elements from keep onwards (reversed)
      for (var ci = stack.length - 1; ci >= keep; ci--) {
        closeElement(stack[ci]);
      }
      stack.length = keep;

      // Open wanted elements not already in stack
      for (var wo2 = 0; wo2 < wanted.length; wo2++) {
        var e = wanted[wo2];
        var inStack2 = false;
        for (var sk2 = 0; sk2 < stack.length; sk2++) {
          if (elementsEqual(stack[sk2], e)) { inStack2 = true; break; }
        }
        if (!inStack2) {
          if (e.url !== null && e.url !== undefined) {
            append("<a href=\"");
            escaped(e.url);
            append("\">");
          } else {
            append("<" + e.tag + ">");
          }
          stack.push(e);
        }
      }

      // Render the run content
      if (run.image != null) {
        append("<img src=\"");
        escaped(run.image);
        append("\" alt=\"");
        var altText = run.text;
        if (altText.length === 1 && altText.codePointAt(0) === 0xFFFC) altText = "";
        escaped(altText);
        append("\" />");
      } else if (run.soft) {
        append("\n");
      } else if (run.hard) {
        append("<br />\n");
      } else if (run.html) {
        append(run.text);
      } else if (run.code) {
        append("<code>");
        escaped(run.text);
        append("</code>");
      } else {
        escaped(run.text);
      }
    }

    // Close remaining stack elements (reversed)
    for (var ri2 = stack.length - 1; ri2 >= 0; ri2--) {
      closeElement(stack[ri2]);
    }
  }

  function checkbox(item) {
    if (taskMarkersAsText) return null;
    if (item.task === null || item.task === undefined) return null;
    return item.task;
  }

  function openNode(node, tight, taskDrop) {
    var kind = node.kind;

    if (kind === "root" || kind === "cell" || kind === "row" || kind === "headerRow") {
      // No open tag
    } else if (kind === "paragraph") {
      if (!tight) { cr(); append("<p>"); }
      inline(node.runs, taskDrop);
      if (!tight) { append("</p>\n"); }
    } else if (kind === "header") {
      cr();
      append("<h" + node.value + ">");
      inline(node.runs, 0);
      append("</h" + node.value + ">\n");
    } else if (kind === "quote") {
      cr(); append("<blockquote>\n");
    } else if (kind === "orderedList") {
      var start = 1;
      if (node.children.length > 0) {
        var firstChild = node.children[0];
        if (firstChild.kind === "item") start = firstChild.value;
      }
      cr();
      if (start !== 1) {
        append("<ol start=\"" + start + "\">\n");
      } else {
        append("<ol>\n");
      }
    } else if (kind === "unorderedList") {
      cr(); append("<ul>\n");
    } else if (kind === "item") {
      cr(); append("<li>");
      var checked = checkbox(node);
      if (checked !== null) {
        if (checked) {
          append("<input type=\"checkbox\" checked=\"\" disabled=\"\" /> ");
        } else {
          append("<input type=\"checkbox\" disabled=\"\" /> ");
        }
      }
    } else if (kind === "code") {
      cr(); append("<pre><code");
      // Extract first word of language hint
      var lang = node.value;
      if (lang) {
        var parts = lang.split(/\s+/);
        var hint = parts[0];
        if (hint.length > 0) {
          append(" class=\"language-");
          escaped(hint);
          append("\"");
        }
      }
      append(">");
      for (var cri = 0; cri < node.runs.length; cri++) {
        escaped(node.runs[cri].text);
      }
      append("</code></pre>\n");
    } else if (kind === "thematic") {
      cr(); append("<hr />\n");
    } else if (kind === "html") {
      cr();
      for (var hri = 0; hri < node.runs.length; hri++) {
        append(node.runs[hri].text);
      }
      cr();
    } else if (kind === "table") {
      cr(); append("<table>");
      var columns = node.value;
      var body = false;
      for (var tci = 0; tci < node.children.length; tci++) {
        var row = node.children[tci];
        var isHeader = (row.kind === "headerRow");
        if (isHeader) {
          cr(); append("<thead>");
        } else if (!body) {
          cr(); append("<tbody>"); cr();
          body = true;
        }
        cr(); append("<tr>");
        var cells = {};
        for (var cci = 0; cci < row.children.length; cci++) {
          var cell = row.children[cci];
          if (cell.kind === "cell") {
            cells[cell.value] = cell;
          }
        }
        for (var ci2 = 0; ci2 < columns; ci2++) {
          var tag = isHeader ? "th" : "td";
          cr();
          append("<" + tag);
          if (ci2 < node.alignments.length && node.alignments[ci2] !== null) {
            append(" align=\"" + node.alignments[ci2] + "\"");
          }
          append(">");
          if (cells[ci2] !== undefined) {
            inline(cells[ci2].runs, 0);
          }
          append("</" + tag + ">");
        }
        cr(); append("</tr>");
        if (isHeader) { cr(); append("</thead>"); }
      }
      if (body) { cr(); append("</tbody>"); cr(); }
      cr(); append("</table>"); cr();
    }
  }

  function closeNode(node) {
    var kind = node.kind;
    if (kind === "quote") { cr(); append("</blockquote>\n"); }
    else if (kind === "orderedList") { append("</ol>\n"); }
    else if (kind === "unorderedList") { append("</ul>\n"); }
    else if (kind === "item") { append("</li>\n"); }
  }

  function isContainer(node) {
    var kind = node.kind;
    return kind === "root" || kind === "quote" || kind === "orderedList" || kind === "unorderedList" || kind === "item";
  }

  var stack = [{ node: root, tight: false, nextChild: 0 }];
  while (stack.length > 0) {
    if (api.cancelled()) throw { error: "cancelled", message: "" };
    var top = stack[stack.length - 1];
    if (top.nextChild >= top.node.children.length) {
      closeNode(top.node);
      stack.pop();
      continue;
    }
    var index = top.nextChild;
    stack[stack.length - 1].nextChild += 1;
    var child = top.node.children[index];
    var tight;
    var taskDrop = 0;
    var parentKind = top.node.kind;
    if (parentKind === "orderedList" || parentKind === "unorderedList") {
      tight = !top.node.loose;
    } else if (parentKind === "item") {
      tight = top.tight;
      if (index === 0 && checkbox(top.node) !== null) {
        taskDrop = 4;
      }
    } else {
      tight = false;
    }
    openNode(child, tight, taskDrop);
    if (isContainer(child)) {
      stack.push({ node: child, tight: tight, nextChild: 0 });
    }
  }

  return utf8.decode(bytes);
}

function elementsEqual(a, b) {
  return a.tag === b.tag && a.url === b.url && a.inner === b.inner;
}
