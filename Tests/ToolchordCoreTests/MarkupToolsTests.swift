import Foundation
import Testing
@testable import ToolchordCore

@Suite struct MarkupToolsTests {
    struct Fixture: Sendable { let command: String; let input: String; let expected: String; var links = false }
    static let fixtures: [Fixture] = [
        Fixture(command: "markdown.html", input: "# Hello *world*", expected: "<h1>Hello <em>world</em></h1>", links: false),
        Fixture(command: "markdown.html", input: "Para one\nsoft line  \nhard line", expected: "<p>Para one\nsoft line<br />\nhard line</p>", links: false),
        Fixture(command: "markdown.html", input: "line\\\nbreak", expected: "<p>line<br />\nbreak</p>", links: false),
        Fixture(command: "markdown.html", input: "- a\n- b\n  - c", expected: "<ul>\n<li>a</li>\n<li>b\n<ul>\n<li>c</li>\n</ul>\n</li>\n</ul>", links: false),
        Fixture(command: "markdown.html", input: "1. x\n2. y", expected: "<ol>\n<li>x</li>\n<li>y</li>\n</ol>", links: false),
        Fixture(command: "markdown.html", input: "3. three\n4. four", expected: "<ol start=\"3\">\n<li>three</li>\n<li>four</li>\n</ol>", links: false),
        Fixture(command: "markdown.html", input: "- loose\n\n- list", expected: "<ul>\n<li>\n<p>loose</p>\n</li>\n<li>\n<p>list</p>\n</li>\n</ul>", links: false),
        Fixture(command: "markdown.html", input: "* a\n\n  b\n* c", expected: "<ul>\n<li>\n<p>a</p>\n<p>b</p>\n</li>\n<li>\n<p>c</p>\n</li>\n</ul>", links: false),
        Fixture(command: "markdown.html", input: "- a\n  - b\n\n- c", expected: "<ul>\n<li>\n<p>a</p>\n<ul>\n<li>b</li>\n</ul>\n</li>\n<li>\n<p>c</p>\n</li>\n</ul>", links: false),
        Fixture(command: "markdown.html", input: "- item\n\n  ```js\n  code <b>\n  ```", expected: "<ul>\n<li>\n<p>item</p>\n<pre><code class=\"language-js\">code &lt;b&gt;\n</code></pre>\n</li>\n</ul>", links: false),
        Fixture(command: "markdown.html", input: "- a\n  <div>\n  html in item\n  </div>", expected: "<ul>\n<li>a\n<div>\nhtml in item\n</div>\n</li>\n</ul>", links: false),
        Fixture(command: "markdown.html", input: "> quote\n> more", expected: "<blockquote>\n<p>quote\nmore</p>\n</blockquote>", links: false),
        Fixture(command: "markdown.html", input: "> > nested\n>\n> back", expected: "<blockquote>\n<blockquote>\n<p>nested</p>\n</blockquote>\n<p>back</p>\n</blockquote>", links: false),
        Fixture(command: "markdown.html", input: "> <div>x</div>\n> para", expected: "<blockquote>\n<div>x</div>\npara\n</blockquote>", links: false),
        Fixture(command: "markdown.html", input: "---", expected: "<hr />", links: false),
        Fixture(command: "markdown.html", input: "a\n\n---\n\nb", expected: "<p>a</p>\n<hr />\n<p>b</p>", links: false),
        Fixture(command: "markdown.html", input: "```swift\nlet x = 1 < 2\n```", expected: "<pre><code class=\"language-swift\">let x = 1 &lt; 2\n</code></pre>", links: false),
        Fixture(command: "markdown.html", input: "    indented", expected: "<pre><code>indented\n</code></pre>", links: false),
        Fixture(command: "markdown.html", input: "| a | b |\n|:-:|--:|\n| 1 | 2 |", expected: "<table>\n<thead>\n<tr>\n<th align=\"center\">a</th>\n<th align=\"right\">b</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td align=\"center\">1</td>\n<td align=\"right\">2</td>\n</tr>\n</tbody>\n</table>", links: false),
        Fixture(command: "markdown.html", input: "| a | |\n|---|---|\n| | 2 |", expected: "<table>\n<thead>\n<tr>\n<th>a</th>\n<th></th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td></td>\n<td>2</td>\n</tr>\n</tbody>\n</table>", links: false),
        Fixture(command: "markdown.html", input: "~~strike~~ `code` **bold** [link](https://example.com \"title\")", expected: "<p><del>strike</del> <code>code</code> <strong>bold</strong> <a href=\"https://example.com\">link</a></p>", links: false),
        Fixture(command: "markdown.html", input: "***both*** **bold *both* bold**", expected: "<p><em><strong>both</strong></em> <strong>bold <em>both</em> bold</strong></p>", links: false),
        // Foundation flattens formatting inside link text; it is restored
        // from the link text's source.
        Fixture(command: "markdown.html", input: "[a *b*](x)", expected: "<p><a href=\"x\">a <em>b</em></a></p>", links: false),
        // Foundation drops line endings from link labels; restoring the source
        // must preserve word boundaries as well as inline formatting.
        Fixture(command: "markdown.html", input: "[read\nmore](https://example.test)", expected: "<p><a href=\"https://example.test\">read\nmore</a></p>", links: false),
        Fixture(command: "markdown.plaintext", input: "[read\nmore](https://example.test)", expected: "read more", links: false),
        Fixture(command: "markdown.html", input: "[a *b*\nc](x)", expected: "<p><a href=\"x\">a <em>b</em>\nc</a></p>", links: false),
        Fixture(command: "markdown.plaintext", input: "[a *b*\nc](x)", expected: "a b c", links: false),
        Fixture(command: "markdown.html", input: "[read\r\nmore](https://example.test)", expected: "<p><a href=\"https://example.test\">read\nmore</a></p>", links: false),
        Fixture(command: "markdown.plaintext", input: "[read\r\nmore](https://example.test)", expected: "read more", links: false),
        Fixture(command: "markdown.html", input: "[α\nβ\nγ](x)", expected: "<p><a href=\"x\">α\nβ\nγ</a></p>", links: false),
        Fixture(command: "markdown.plaintext", input: "[α\nβ\nγ](x)", expected: "α β γ", links: false),
        Fixture(command: "markdown.html", input: "> [read\n> more](x)", expected: "<blockquote>\n<p><a href=\"x\">read\nmore</a></p>\n</blockquote>", links: false),
        Fixture(command: "markdown.plaintext", input: "> [read\n> more](x)", expected: "> read more", links: false),
        Fixture(command: "markdown.html", input: "- [read\n  more](x)", expected: "<ul>\n<li><a href=\"x\">read\nmore</a></li>\n</ul>", links: false),
        Fixture(command: "markdown.plaintext", input: "- [read\n  more](x)", expected: "• read more", links: false),
        Fixture(command: "markdown.html", input: "> - [a *b*\n>   c](x)", expected: "<blockquote>\n<ul>\n<li><a href=\"x\">a <em>b</em>\nc</a></li>\n</ul>\n</blockquote>", links: false),
        Fixture(command: "markdown.plaintext", input: "> - [a *b*\n>   c](x)", expected: "> • a b c", links: false),
        Fixture(command: "markdown.html", input: "**[a](x)** and [`c` d](y)", expected: "<p><strong><a href=\"x\">a</a></strong> and <a href=\"y\"><code>c</code> d</a></p>", links: false),
        Fixture(command: "markdown.html", input: "[![Build](b.svg)](https://ci) [![B](i.png) text](u)", expected: "<p><a href=\"https://ci\"><img src=\"b.svg\" alt=\"Build\" /></a> <a href=\"u\"><img src=\"i.png\" alt=\"B\" /> text</a></p>", links: false),
        Fixture(command: "markdown.html", input: "**[*a* b](x)** [a &amp; \\*b\\*](y) [see https://e.com](z)", expected: "<p><strong><a href=\"x\"><em>a</em> b</a></strong> <a href=\"y\">a &amp; *b*</a> <a href=\"z\">see https://e.com</a></p>", links: false),
        // Outer formatting starting mid-link reopens the link inside it.
        Fixture(command: "markdown.html", input: "[a](x)**[b](x)**", expected: "<p><a href=\"x\">a</a><strong><a href=\"x\">b</a></strong></p>", links: false),
        // Task markers must be written literally.
        Fixture(command: "markdown.html", input: "- \\[x\\] escaped\n- `[x]` code\n- `[x] task`", expected: "<ul>\n<li>[x] escaped</li>\n<li><code>[x]</code> code</li>\n<li><code>[x] task</code></li>\n</ul>", links: false),
        Fixture(command: "markdown.plaintext", input: "a<img alt=\"One\"><br><img alt=\"Two\"><!-- <img alt=\"Hidden\"> -->b", expected: "a[One]\n[Two]b", links: false),
        // Inline HTML in Markdown converts like HTML.
        Fixture(command: "markdown.plaintext", input: "before <img alt=\"Logo\" src=\"x\"> after", expected: "before [Logo] after", links: false),
        Fixture(command: "markdown.plaintext", input: "see <a href=\"https://e.com\">docs</a> now", expected: "see docs (https://e.com) now", links: true),
        Fixture(command: "html.plaintext", input: "<template><textarea></template>hidden</textarea></template>shown", expected: "shown", links: false),
        // Follow-up review: content the page doesn't render stays out.
        Fixture(command: "html.plaintext", input: "<p>visible <span hidden>secret</span> text</p>", expected: "visible text", links: false),
        Fixture(command: "html.plaintext", input: "<div style=\"DISPLAY : None; max-height: 0\">Preheader</div><p>Body</p>", expected: "Body", links: false),
        Fixture(command: "html.plaintext", input: "<p>a <img hidden alt=\"x\">b <img alt=\"y\"></p>", expected: "a b [y]", links: false),
        Fixture(command: "html.plaintext", input: "<span hidden>a<span>b</span>c</span>d<p hidden=\"until-found\">e</p>f", expected: "df", links: false),
        Fixture(command: "html.plaintext", input: "<textarea hidden>secret</textarea>shown", expected: "shown", links: false),
        // Hidden elements end where a browser closes them.
        Fixture(command: "html.plaintext", input: "<p>a <span hidden>x</p><p>y</span> b</p>", expected: "a\n\ny b", links: false),
        Fixture(command: "html.plaintext", input: "<p hidden>secret<p>visible", expected: "visible", links: false),
        Fixture(command: "html.plaintext", input: "<ul><li hidden>a<li>b</ul>", expected: "• b", links: false),
        Fixture(command: "html.plaintext", input: "<div hidden><p>x</div>y", expected: "y", links: false),
        Fixture(command: "html.plaintext", input: "<span hidden><div>a</div>b</span>c", expected: "c", links: false),
        Fixture(command: "html.plaintext", input: "<span hidden>a</b>b</span>c", expected: "c", links: false),
        // Template content can't close an outer element.
        Fixture(command: "html.plaintext", input: "<template></p>secret</template>visible", expected: "visible", links: false),
        Fixture(command: "html.plaintext", input: "<p><span hidden><template></p></template>x</span>y", expected: "y", links: false),
        // Past the tracking limit, same-name nesting still decides where hiding ends.
        Fixture(command: "html.plaintext", input: "<template>" + String(repeating: "<template>", count: 257) + String(repeating: "</template>", count: 257) + "secret</template>visible", expected: "visible", links: false),
        Fixture(command: "html.plaintext", input: "<span hidden>" + String(repeating: "<span>", count: 300) + String(repeating: "</span>", count: 300) + "secret</span>visible", expected: "visible", links: false),
        // A table start closes an open `p`, hidden or not, so the table and what follows are visible.
        Fixture(command: "html.plaintext", input: "<p hidden>a<span>b<table><tr><td>c</td></tr></table>d</span></p>e", expected: "c\n\nd\n\ne", links: false),
        Fixture(command: "html.plaintext", input: "<span style=\"display:none&#10;!important\">secret</span>visible", expected: "visible", links: false),
        Fixture(command: "html.plaintext", input: "<span style=\"--display:none\">a</span> <span style=\"display:none; display: block\">b</span> <span style=\"display:block;DISPLAY:none !important\">c</span>", expected: "a b", links: false),
        Fixture(command: "markdown.plaintext", input: "safe <script>secret</script> end", expected: "safe end", links: false),
        Fixture(command: "markdown.plaintext", input: "a <span hidden>b <em>c</em> <span>d</span></span> e <style>p { color: red }</style> f", expected: "a e f", links: false),
        Fixture(command: "markdown.plaintext", input: "safe <script>[x](https://e.com)</script> end <img hidden alt=\"Logo\">", expected: "safe end", links: true),
        // Tags in raw text don't end or nest skipped elements.
        Fixture(command: "markdown.plaintext", input: "a <span hidden><script>\"</span>\"</script>secret</span> b", expected: "a b", links: false),
        Fixture(command: "markdown.plaintext", input: "a <script>x<script>y</script> c", expected: "a c", links: false),
        Fixture(command: "markdown.plaintext", input: "a <span hidden><textarea><!-- </textarea> --></span> b", expected: "a b", links: false),
        Fixture(command: "markdown.plaintext", input: "a <SCRIPT>x</Script > c", expected: "a c", links: false),
        // Raw text opened inline runs through block boundaries to its end tag,
        // as in the equivalent HTML; a non-raw hidden element ends with its block.
        Fixture(command: "markdown.plaintext", input: "safe <script>one\n\n# secret\n\ntwo</script> end", expected: "safe end", links: false),
        Fixture(command: "markdown.plaintext", input: "a <style>p {\n\n}\n\n- item\n\n> quote\n\n```\ncode\n```\n\n| t |\n|---|\n| c |\n\n</style> b\n\nnext", expected: "a b\n\nnext", links: false),
        Fixture(command: "markdown.plaintext", input: "a <span hidden><script>x\n\ny</script>z</span> b", expected: "a b", links: false),
        Fixture(command: "markdown.plaintext", input: "a <span hidden>x\n\ny</span> b", expected: "a\n\ny b", links: false),
        Fixture(command: "markdown.plaintext", input: "- a <script>b\n- c</script> d\n- e", expected: "• a d\n• e", links: false),
        Fixture(command: "markdown.plaintext", input: "x <script>y\n\n<div>\n</script>tail\n</div>", expected: "x tail", links: false),
        Fixture(command: "markdown.plaintext", input: "never <script>closed\n\n# heading\n\ntext", expected: "never", links: false),
        // Structure swallowed by raw text behaves as in the equivalent HTML.
        Fixture(command: "markdown.plaintext", input: "> a<script>x\n\nb</script> c\n\nnext", expected: "> a c\n>\n> next", links: false),
        Fixture(command: "markdown.plaintext", input: "1. a<script>x\n2. b</script>c\n3. d", expected: "1. ac\n2. d", links: false),
        Fixture(command: "markdown.plaintext", input: "a <script>x\n\n| h |\n|---|\n| </script>shown |\n\nnext", expected: "a shown\n\nnext", links: false),
        Fixture(command: "markdown.plaintext", input: "| a<script> | </script>b |\n|---|---|", expected: "ab", links: false),
        Fixture(command: "markdown.plaintext", input: "a <script>x\n\n[</script>shown](u)", expected: "a shown", links: true),
        // Follow-up review: list items and nested tables inside table cells.
        Fixture(command: "html.plaintext", input: "<table><tr><td><ol><li>a</li><li>b</li></ol></td><td>c</td></tr></table>", expected: "1. a 2. b\tc", links: false),
        Fixture(command: "html.plaintext", input: "<table><tr><td>a<table><tr><td>x</td><td>y</td></tr><tr><td>z</td></tr></table></td><td>b</td></tr></table>", expected: "a x y z\tb", links: false),
        Fixture(command: "html.plaintext", input: "<table><tr><td><table><tr><td>in</td></tr></table>after</td><td>b</td></tr><tr><td>2</td><td>3</td></tr></table><table><tr><td>next</td></tr></table>", expected: "in after\tb\n2\t3\n\nnext", links: false),
        // Inline HTML in link text passes through, as in cmark.
        Fixture(command: "markdown.html", input: "[<b>x</b> y](u)", expected: "<p><a href=\"u\"><b>x</b> y</a></p>", links: false),
        // A reference image inside a link can't be re-parsed alone: keep the flat text.
        Fixture(command: "markdown.html", input: "x [![a][r]](u)\n\n[r]: i.png", expected: "<p>x <a href=\"u\">a</a></p>", links: false),
        Fixture(command: "markdown.html", input: "[![Build](b.svg)](https://ci)", expected: "<p><a href=\"https://ci\"><img src=\"b.svg\" alt=\"Build\" /></a></p>", links: false),
        Fixture(command: "markdown.plaintext", input: "[![Build](b.svg)](https://ci)", expected: "[Build]", links: false),
        Fixture(command: "markdown.plaintext", input: "[![Build](b.svg)](https://ci)", expected: "[Build] (https://ci)", links: true),
        Fixture(command: "markdown.html", input: "[amp](https://x.y/?a=1&b=2)", expected: "<p><a href=\"https://x.y/?a=1&amp;b=2\">amp</a></p>", links: false),
        Fixture(command: "markdown.html", input: "![alt](img.png) ![](empty.png)", expected: "<p><img src=\"img.png\" alt=\"alt\" /> <img src=\"empty.png\" alt=\"\" /></p>", links: false),
        Fixture(command: "markdown.html", input: "<https://auto.link>", expected: "<p><a href=\"https://auto.link\">https://auto.link</a></p>", links: false),
        Fixture(command: "markdown.html", input: "<div>\nblock html\n</div>\n\nInline <kbd>Cmd</kbd> &amp; &copy;", expected: "<div>\nblock html\n</div>\n<p>Inline <kbd>Cmd</kbd> &amp; ©</p>", links: false),
        Fixture(command: "markdown.html", input: "- [ ] task\n- [x] done", expected: "<ul>\n<li><input type=\"checkbox\" disabled=\"\" /> task</li>\n<li><input type=\"checkbox\" checked=\"\" disabled=\"\" /> done</li>\n</ul>", links: false),
        Fixture(command: "markdown.html", input: "a < b & \"c\"", expected: "<p>a &lt; b &amp; &quot;c&quot;</p>", links: false),
        Fixture(command: "markdown.html", input: "", expected: "", links: false),
        Fixture(command: "markdown.plaintext", input: "# Title\n\nSome *emphasis* and **bold** text with `code`.", expected: "Title\n\nSome emphasis and bold text with code.", links: false),
        Fixture(command: "markdown.plaintext", input: "- a\n- b\n  - c\n\n1. x\n2. y", expected: "• a\n• b\n  • c\n\n1. x\n2. y", links: false),
        Fixture(command: "markdown.plaintext", input: "- loose\n\n- list", expected: "• loose\n\n• list", links: false),
        Fixture(command: "markdown.plaintext", input: "1. a\n\n   para", expected: "1. a\n\n   para", links: false),
        Fixture(command: "markdown.plaintext", input: "10. ten\n11. eleven\n    more", expected: "10. ten\n11. eleven more", links: false),
        Fixture(command: "markdown.plaintext", input: "[link](https://example.com) and <https://auto.link>", expected: "link and https://auto.link", links: false),
        Fixture(command: "markdown.plaintext", input: "[link](https://example.com) and <https://auto.link>", expected: "link (https://example.com) and https://auto.link", links: true),
        Fixture(command: "markdown.plaintext", input: "[site](https://www.example.com)", expected: "site (https://www.example.com)", links: true),
        Fixture(command: "markdown.plaintext", input: "Visit www.example.com", expected: "Visit www.example.com", links: true),
        Fixture(command: "markdown.plaintext", input: "> quote\n> more\n\nafter", expected: "> quote more\n\nafter", links: false),
        Fixture(command: "markdown.plaintext", input: "> one\n>\n> two", expected: "> one\n>\n> two", links: false),
        Fixture(command: "markdown.plaintext", input: "```swift\nlet x = 1\n```", expected: "let x = 1", links: false),
        Fixture(command: "markdown.plaintext", input: "| a | b |\n|---|---|\n| 1 | 2 |", expected: "a\tb\n1\t2", links: false),
        Fixture(command: "markdown.plaintext", input: "Para one\nsoft\\\nhard", expected: "Para one soft\nhard", links: false),
        Fixture(command: "markdown.plaintext", input: "![Logo](logo.png) text", expected: "[Logo] text", links: false),
        Fixture(command: "markdown.plaintext", input: "a\n\n---\n\nb", expected: "a\n\nb", links: false),
        Fixture(command: "markdown.plaintext", input: "- [x] done", expected: "• [x] done", links: false),
        Fixture(command: "markdown.plaintext", input: "a <br> b", expected: "a\nb", links: false),
        Fixture(command: "markdown.plaintext", input: "<div>\n<p>Hello <b>World</b></p>\n</div>", expected: "Hello World", links: false),
        Fixture(command: "markdown.plaintext", input: "", expected: "", links: false),
        Fixture(command: "html.plaintext", input: "<h1>Title</h1><p>Hello <b>world</b> &amp; you.</p><p>Second   paragraph\nwith newline.</p>", expected: "Title\n\nHello world & you.\n\nSecond paragraph with newline.", links: false),
        Fixture(command: "html.plaintext", input: "<ul><li>One</li><li>Two<ul><li>Nested</li></ul></li></ul><ol start=\"3\"><li>Three</li><li>Four</li></ol>", expected: "• One\n• Two\n  • Nested\n\n3. Three\n4. Four", links: false),
        Fixture(command: "html.plaintext", input: "<ol><li>a</li><li value=\"10\">b</li><li>c</li></ol>", expected: "1. a\n10. b\n11. c", links: false),
        Fixture(command: "html.plaintext", input: "<ul><li><p>Para one</p><p>Para two</p></li></ul>", expected: "• Para one\n\n  Para two", links: false),
        Fixture(command: "html.plaintext", input: "<p>Line one<br>Line two</p>", expected: "Line one\nLine two", links: false),
        Fixture(command: "html.plaintext", input: "<p>text<br></p><p>next</p>", expected: "text\n\nnext", links: false),
        Fixture(command: "html.plaintext", input: "<pre>  code\n    indented</pre>", expected: "  code\n    indented", links: false),
        Fixture(command: "html.plaintext", input: "<pre>\nfirst</pre>", expected: "first", links: false),
        Fixture(command: "html.plaintext", input: "<table><tr><th>Name</th><th>Age</th></tr><tr><td>Ann</td><td>30</td></tr></table>", expected: "Name\tAge\nAnn\t30", links: false),
        Fixture(command: "html.plaintext", input: "<table><tr><td>a<br>b</td><td>c</td></tr></table>", expected: "a b\tc", links: false),
        Fixture(command: "html.plaintext", input: "<p>See <a href=\"https://example.com\">the docs</a>.</p>", expected: "See the docs.", links: false),
        Fixture(command: "html.plaintext", input: "<p>See <a href=\"https://example.com\">the docs</a>.</p>", expected: "See the docs (https://example.com).", links: true),
        Fixture(command: "html.plaintext", input: "<a href=\"https://example.com\">https://example.com</a>", expected: "https://example.com", links: true),
        Fixture(command: "html.plaintext", input: "<a href=\"mailto:x@y.z\">x@y.z</a>", expected: "x@y.z", links: true),
        Fixture(command: "html.plaintext", input: "<p>A <a href=\"#top\">top</a> link</p>", expected: "A top link", links: true),
        Fixture(command: "html.plaintext", input: "<script>var x = \"<p>\";</script><style>p{}</style><p>Visible</p><!-- hidden -->", expected: "Visible", links: false),
        Fixture(command: "html.plaintext", input: "<!DOCTYPE html><html><head><title>T</title><meta charset=\"utf-8\"></head><body><p>Body</p></body></html>", expected: "Body", links: false),
        Fixture(command: "html.plaintext", input: "<blockquote><p>Quoted</p><p>Two</p></blockquote><p>After</p>", expected: "> Quoted\n>\n> Two\n\nAfter", links: false),
        Fixture(command: "html.plaintext", input: "<img src=\"a.png\" alt=\"Logo\"> text", expected: "[Logo] text", links: false),
        Fixture(command: "html.plaintext", input: "a < b and c > d", expected: "a < b and c > d", links: false),
        Fixture(command: "html.plaintext", input: "caf&eacute; &#x1F600; &unknown;", expected: "café 😀 &unknown;", links: false),
        Fixture(command: "html.plaintext", input: "<p>a&nbsp;&nbsp;b</p>", expected: "a  b", links: false),
        Fixture(command: "html.plaintext", input: "<div>One</div><div>Two</div>", expected: "One\nTwo", links: false),
        Fixture(command: "html.plaintext", input: "<div>  A  </div>  <div> B </div>", expected: "A\nB", links: false),
        Fixture(command: "html.plaintext", input: "<p>Unclosed <b>bold", expected: "Unclosed bold", links: false),
        Fixture(command: "html.plaintext", input: "<dl><dt>Term</dt><dd>Definition</dd></dl>", expected: "Term\n  Definition", links: false),
        Fixture(command: "html.plaintext", input: "<p>  leading and trailing  </p>", expected: "leading and trailing", links: false),
        Fixture(command: "html.plaintext", input: "&lt;p&gt;", expected: "<p>", links: false),
        Fixture(command: "html.plaintext", input: "<svg><text>hidden</text></svg>shown", expected: "shown", links: false),
        Fixture(command: "html.plaintext", input: "", expected: "", links: false),
        // Blank lines between blocks repeat only the quote prefixes that
        // surround both blocks.
        Fixture(command: "markdown.plaintext", input: "# Title\n\n> quote\n> > nested", expected: "Title\n\n> quote\n>\n> > nested", links: false),
        Fixture(command: "markdown.plaintext", input: "> a\n\n> b", expected: "> a\n\n> b", links: false),
        Fixture(command: "html.plaintext", input: "<blockquote>a<blockquote>b</blockquote>c</blockquote>", expected: "> a\n>\n> > b\n>\n> c", links: false),
        Fixture(command: "html.plaintext", input: "<ul><li>a<blockquote>q</blockquote></li><li>b</li></ul>", expected: "• a\n\n  > q\n\n• b", links: false),
        Fixture(command: "html.plaintext", input: "<p>Intro</p><blockquote><ul><li>x</li></ul></blockquote>", expected: "Intro\n\n> • x", links: false),
        // `textarea` shows its content as text, tags included.
        Fixture(command: "html.plaintext", input: "<textarea>\n  <b>not tags</b> &amp;\n x</textarea>after", expected: "  <b>not tags</b> &\n x\nafter", links: false),
        Fixture(command: "html.plaintext", input: "<textarea>never closed <p>x", expected: "never closed <p>x", links: false),
    ]

    @Test(arguments: fixtures) func requiredFixtures(_ fixture: Fixture) throws {
        let command = try #require(MarkupTools.commands.first { $0.id == fixture.command })
        let result = command.run(ToolRequest(input: .text(fixture.input), options: ToolOptions(["links": fixture.links ? "true" : "false"])))
        let output = try #require(result.output)
        #expect(output.primaryText == fixture.expected)
        #expect(output.presentation == .text)
        #expect(output.status == (fixture.command == "markdown.html" ? "Rendered HTML" : "Plain text"))
        #expect(output.syntax == (fixture.command == "markdown.html" ? .xml : .plain))
    }
}

@Suite struct MarkdownWithoutPositionsTests {
    /// Above the autolink threshold the renderer loses source positions but
    /// keeps its structure: loose lists with two paragraphs in an item, center
    /// and right table alignment, and plain link text.
    @Test func manyAutolinksFallBackGracefully() throws {
        let links = String(repeating: "https://example.test/ ", count: MarkdownDocument.maxAutolinkCandidatesWithPositions + 1)
        let command = try #require(MarkupTools.commands.first { $0.id == "markdown.html" })
        let markdown = "- a\n\n  b\n- c\n\n| l | c | r |\n|:--|:-:|--:|\n| 1 | 2 | 3 |\n\n[x *y*](z)\n\n" + links
        let html = try #require(command.run(ToolRequest(input: .text(markdown))).output).primaryText
        #expect(html.hasPrefix("<ul>\n<li>\n<p>a</p>\n<p>b</p>\n</li>\n<li>\n<p>c</p>\n</li>\n</ul>\n<table>"))
        #expect(html.contains("<th>l</th>\n<th align=\"center\">c</th>\n<th align=\"right\">r</th>"))
        #expect(html.contains("<p><a href=\"z\">x y</a></p>"))
        #expect(MarkdownDocument.autolinkCandidates(in: "a://b c@d e:/f", upTo: 10) == 2)

        // Without positions, adjacent inline HTML tags arrive as one run.
        let text = try #require(MarkupTools.commands.first { $0.id == "markdown.plaintext" })
        let plain = try #require(text.run(ToolRequest(input: .text("x<br><img alt=\"Logo\">y\n\n" + links))).output).primaryText
        #expect(plain.hasPrefix("x\n[Logo]y\n\n"))
    }
}

/// Adversarial input stays linear and bounded. Realistic 1 MiB documents are
/// timed by `make benchmark` in a release build instead: Foundation's
/// Markdown parser alone needs about 0.9 s there, and much more in debug.
@Suite struct MarkupPerformanceTests {
    @Test func adversarialInputFinishesQuickly() throws {
        let cases: [(String, String, Bool)] = [
            // Thousands of bare URLs or email addresses: parsed without source positions.
            ("markdown.html", String(repeating: "see https://example.test/?q=1 or me@example.test\n", count: 4_000), true),
            ("markdown.plaintext", String(repeating: "- https://example.test/a\n", count: 8_000), true),
            ("html.plaintext", String(repeating: "<p>Hello <strong>world</strong> &amp; friends.</p>\n", count: 20_000), true),
            ("html.plaintext", String(repeating: "<", count: 200_000), true),
            ("html.plaintext", String(repeating: "<b>", count: 100_000), true),
            ("html.plaintext", String(repeating: "&#x", count: 100_000), true),
            ("html.plaintext", "<pre>" + String(repeating: "\r\n", count: 100_000), true),
            ("html.plaintext", String(repeating: "<blockquote>", count: 10_000), false),
            ("html.plaintext", String(repeating: "<ul><li>", count: 10_000), false),
            ("markdown.html", String(repeating: "[", count: 100_000), true),
            ("markdown.plaintext", String(repeating: "<a", count: 100_000), true),
            ("markdown.html", String(repeating: "> ", count: 10_000) + "x", false),
            ("markdown.plaintext", String(repeating: "- ", count: 10_000) + "x", false),
            // Nesting just inside the limit renders without exhausting the
            // stack of a background thread.
            ("markdown.html", String(repeating: "> ", count: 127) + "x", true),
            ("markdown.plaintext", String(repeating: "> ", count: 127) + "x", true),
            ("markdown.html", (0..<60).map { String(repeating: "  ", count: $0) + "- x" }.joined(separator: "\n"), true),
            // Deep nesting with a lot of text: prefixes cost O(1) per character.
            ("html.plaintext", String(repeating: "<blockquote><ul><li>", count: 42) + String(repeating: "word ", count: 150_000), true),
            ("markdown.plaintext", String(repeating: "> ", count: 120) + String(repeating: "word ", count: 150_000), true),
        ]
        let clock = ContinuousClock()
        for (id, input, succeeds) in cases {
            let command = try #require(MarkupTools.commands.first { $0.id == id })
            var result = ToolResult.cancelled
            let elapsed = clock.measure { result = command.run(ToolRequest(input: .text(input))) }
            // Generous for parallel debug runs; quadratic behavior takes far longer.
            #expect(elapsed < .seconds(5), "\(id) \(input.prefix(12)) took \(elapsed)")
            if succeeds {
                #expect(result.isSuccess, "\(id) \(input.prefix(12))")
            } else {
                #expect(result == .tooLarge(ToolLimits.standard.nestingLimitMessage), "\(id) \(input.prefix(12))")
            }
        }
    }
}

@Suite struct MarkupEdgeTests {
    func run(_ id: String, _ text: String, links: Bool = false, limits: ToolLimits = .standard, cancellation: CancellationCheck = .never) throws -> ToolResult {
        let command = try #require(MarkupTools.commands.first { $0.id == id })
        return command.run(ToolRequest(input: .text(text), options: ToolOptions(["links": links ? "true" : "false"]), limits: limits, cancellation: cancellation))
    }

    @Test func missingInputAndMetadata() throws {
        #expect(MarkupTools.commands.map(\.id) == ["html.plaintext", "markdown.html", "markdown.plaintext"])
        for command in MarkupTools.commands {
            if case .needsInput = command.run(ToolRequest(input: .none)) {} else { Issue.record("Expected missing input") }
            #expect(command.copyNoun(ToolOptions()) == (command.id == "markdown.html" ? "HTML" : "text"))
            let profile = InputProfile(isAttached: true, kinds: [.html, .markdown], primaryKind: .markdown, byteCount: 4, lineCount: 1, isBlank: false)
            #expect(command.affinity(profile) == (command.id == "html.plaintext" ? 85 : command.id == "markdown.html" ? 90 : 80))
            #expect(command.affinity(.none) == 0)
        }
    }

    @Test func limitsAndCancellation() throws {
        for command in MarkupTools.commands {
            let small = ToolLimits(maxInputBytes: 4, maxOutputBytes: 4, maxNestingDepth: 2)
            #expect(try run(command.id, "12345", limits: small) == .tooLarge(small.inputLimitMessage))
            #expect(try run(command.id, "", cancellation: CancellationCheck { true }) == .cancelled)
            #expect(try run(command.id, "x", cancellation: CancellationCheck { true }) == .cancelled)
            #expect(try run(command.id, "", limits: ToolLimits(maxOutputBytes: 0)).output?.primaryText == "")
        }
        for id in ["html.plaintext", "markdown.plaintext"] {
            #expect(try run(id, "ab", limits: ToolLimits(maxOutputBytes: 1)) == .tooLarge(ToolLimits(maxOutputBytes: 1).outputLimitMessage))
        }
        #expect(try run("html.plaintext", "<pre>a\n</pre>", limits: ToolLimits(maxOutputBytes: 1)).output?.primaryText == "a")
        #expect(try run("html.plaintext", "a<br><br>", limits: ToolLimits(maxOutputBytes: 1)).output?.primaryText == "a")
        #expect(try run("markdown.html", "x", limits: ToolLimits(maxOutputBytes: 8)).output?.primaryText == "<p>x</p>")
        #expect(try run("markdown.html", "x", limits: ToolLimits(maxOutputBytes: 7)) == .tooLarge(ToolLimits(maxOutputBytes: 7).outputLimitMessage))
        #expect(try run("html.plaintext", "<ul><li></li></ul>", limits: ToolLimits(maxOutputBytes: 3)).output?.primaryText == "•")
        let shallow = ToolLimits(maxNestingDepth: 2)
        #expect(try run("html.plaintext", "<ul><li><blockquote><dd>x", limits: shallow) == .tooLarge(shallow.nestingLimitMessage))
        for id in ["markdown.html", "markdown.plaintext"] {
            #expect(try run(id, "> > > x", limits: shallow) == .tooLarge(shallow.nestingLimitMessage))
            #expect(try run(id, "- x", limits: shallow) == .tooLarge(shallow.nestingLimitMessage))
        }
    }

    @Test func htmlTokenizerAndEntities() throws {
        let examples: [(String, String)] = [
            ("<p title='a > b'>x</p>", "x"),
            ("<img alt='first &amp; best' alt=second>", "[first & best]"),
            ("a<!-- unterminated", "a"),
            ("a<![CDATA[<p>invisible</p>]]>b<?skip me?>c<!DOCTYPE x>d", "abcd"),
            ("a <3 </3 <_x", "a <3 </3 <_x"),
            ("before<b title='unterminated > after", "before"),
            ("<script>one</scriptx>two</ScRiPt><p>shown</p>", "shown"),
            ("<style>not closed", ""),
            ("<template><template>x</template>y</template>z", "z"),
            ("<svg />a<canvas/>b<object>hidden", "a"),
            ("<blockquote/>x</blockquote>y", "> x\n\ny"),
            ("&lt;b&gt; &#0; &#xD800; &#1114112; &AMP; &bogus; &amp", "<b> � � � &AMP; &bogus; &amp"),
            ("a&nbsp;&nbsp; b&nbsp;", "a   b"),
            ("<custom-element>a</custom-element><x:y>b</x:y>", "ab"),
        ]
        for (input, expected) in examples {
            let actual = try run("html.plaintext", input).output?.primaryText
            #expect(actual == expected, Comment(rawValue: input))
        }
    }

    @Test(arguments: ["html.plaintext", "markdown.plaintext"])
    func trailingSlashDoesNotCloseHiddenHTML(command: String) throws {
        let examples = [
            "<div hidden/>secret</div><p>visible</p>",
            "<div style='display: none'/>secret</div><p>visible</p>",
            "<template/>secret</template><p>visible</p>",
            "<div hidden><div/>inner</div>secret</div><p>visible</p>",
            "<div hidden><svg/><div/>inner</div>secret</div><p>visible</p>",
        ]
        for input in examples {
            #expect(try run(command, input).output?.primaryText == "visible", Comment(rawValue: input))
        }
    }

    @Test func selfClosingForeignAndVoidElementsKeepFollowingText() throws {
        let examples = [
            "<svg/><p>visible</p>",
            "<math/><p>visible</p>",
            "<img hidden/><p>visible</p>",
            "<svg><svg/>secret</svg><p>visible</p>",
            "<svg><g/><text>secret</text></svg><p>visible</p>",
            "<div hidden><svg><g/></svg>secret</div><p>visible</p>",
        ]
        for input in examples {
            #expect(try run("html.plaintext", input).output?.primaryText == "visible", Comment(rawValue: input))
        }
    }

    @Test func sharedPrefixesHardBreaksAndPreformattedText() throws {
        let examples: [(String, String)] = [
            ("<br><br>a", "a"),
            ("<li>a<li>b", "• a\n• b"),
            ("<ul><li></li><li>x</li><li></li></ul>", "•\n• x\n•"),
            ("<ul><li><ul><li>x</li></ul></li></ul>", "• • x"),
            ("<blockquote><ul><li>x<br>y</li></ul></blockquote>", "> • x\n>   y"),
            ("<ul><li><blockquote>x<br>y</blockquote></li></ul>", "• > x\n  > y"),
            ("<blockquote>a<br><br>b<br><br></blockquote>", "> a\n>\n> b"),
            ("<blockquote><blockquote>a</blockquote><p>b</p></blockquote>", "> > a\n>\n> b"),
            ("<p>a <br> <br> b</p>", "a\n\nb"),
            ("<pre>\r\na  \r\nb\rc\n</pre>", "a  \r\nb\rc"),
            ("<blockquote><pre> a  \n b </pre></blockquote>", ">  a  \n>  b "),
            ("<textarea>\n first\n  second </textarea>", " first\n  second "),
            ("<table><tr><td> a <p>b</p> c </td><td></td></tr></table>", "a b c\t"),
            ("<tr><td>a</td><td>b</td></tr><tr><td>c</td><td></td></tr>", "a\tb\nc\t"),
        ]
        for (input, expected) in examples {
            let actual = try run("html.plaintext", input).output?.primaryText
            #expect(actual == expected, Comment(rawValue: input))
        }
        #expect(try run("markdown.plaintext", "> - x  \n>   y").output?.primaryText == "> • x\n>   y")
        #expect(try run("markdown.plaintext", "- > x  \n  > y").output?.primaryText == "• > x\n  > y")
        #expect(try run("markdown.plaintext", "| a | b |\n|---|---|\n| x<br>y | | ").output?.primaryText == "a\tb\nx y\t")
    }

    @Test func linksAndImages() throws {
        let examples: [(String, String)] = [
            ("<a href='HTTPS://example.com'>example.com</a>", "example.com"),
            ("<a href='JavaScript:alert(1)'>unsafe</a>", "unsafe"),
            ("<a href=''>empty</a><a href='#x'>fragment</a>", "emptyfragment"),
            ("<a href='https://example.com/a?x=1&amp;y=2'>label</a>", "label (https://example.com/a?x=1&y=2)"),
            ("<a href=x>unclosed", "unclosed (x)"),
            ("<img alt='  '><img alt='  logo  '>", "[logo]"),
        ]
        for (input, expected) in examples { #expect(try run("html.plaintext", input, links: true).output?.primaryText == expected) }
        #expect(try run("markdown.plaintext", "[**the** docs](https://example.com)", links: true).output?.primaryText == "the docs (https://example.com)")
        #expect(try run("markdown.html", "[label](<https://x.y/a b>)").output?.primaryText == "<p><a href=\"https://x.y/a%20b\">label</a></p>")
        #expect(try run("markdown.html", "![a & b](x)").output?.primaryText == "<p><img src=\"x\" alt=\"a &amp; b\" /></p>")
    }

    @Test func markdownStructuralEdges() throws {
        #expect(try run("markdown.html", "| a | b |\n|:---|---|\n| c | d |").output?.primaryText == "<table>\n<thead>\n<tr>\n<th align=\"left\">a</th>\n<th>b</th>\n</tr>\n</thead>\n<tbody>\n<tr>\n<td align=\"left\">c</td>\n<td>d</td>\n</tr>\n</tbody>\n</table>")
        #expect(try run("markdown.html", "> - a\r\n>\r\n> - b").output?.primaryText == "<blockquote>\n<ul>\n<li>\n<p>a</p>\n</li>\n<li>\n<p>b</p>\n</li>\n</ul>\n</blockquote>")
        #expect(try run("markdown.html", "- [X] **done**").output?.primaryText == "<ul>\n<li><input type=\"checkbox\" checked=\"\" disabled=\"\" /> <strong>done</strong></li>\n</ul>")
        #expect(try run("markdown.html", "```a&b rest\nx\n```").output?.primaryText == "<pre><code class=\"language-a&amp;b\">x\n</code></pre>")
        #expect(try run("markdown.html", "```\n" + String(repeating: ">", count: 10000) + "\n```").isSuccess)
        #expect(try run("markdown.html", String(repeating: "- ", count: 10000) + "x") == .tooLarge(ToolLimits.standard.nestingLimitMessage))
        #expect(try run("markdown.plaintext", "**a** *b* ~~c~~ `d` ![](x)").output?.primaryText == "a b c d")
    }
}

@Suite struct MarkdownPlainTextLimitTests {
    private func run(_ text: String, limits: ToolLimits) throws -> ToolResult {
        let command = try #require(MarkupTools.commands.first { $0.id == "markdown.plaintext" })
        return command.run(ToolRequest(input: .text(text), limits: limits))
    }

    /// The output limit applies to the plain text, not to the intermediate HTML.
    @Test func outputLimitAppliesToThePlainText() throws {
        #expect(try run("x", limits: ToolLimits(maxOutputBytes: 1)).output?.primaryText == "x")
        let ampersands = String(repeating: "&", count: 1_000)
        #expect(try run(ampersands, limits: ToolLimits(maxOutputBytes: 1_000)).output?.primaryText == ampersands)
        let tooSmall = ToolLimits(maxOutputBytes: 999)
        #expect(try run(ampersands, limits: tooSmall) == .tooLarge(tooSmall.outputLimitMessage))
    }

    /// Deep nesting renders the full structure, not just without crashing.
    @Test func deepNestingKeepsItsStructure() throws {
        let markdown = String(repeating: "> ", count: 127) + "x"
        #expect(try run(markdown, limits: .standard).output?.primaryText == String(repeating: "> ", count: 127) + "x")
        let html = try #require(MarkupTools.commands.first { $0.id == "markdown.html" })
        let expected = String(repeating: "<blockquote>\n", count: 127) + "<p>x</p>\n" + String(repeating: "</blockquote>\n", count: 127)
        #expect(html.run(ToolRequest(input: .text(markdown))).output?.primaryText == String(expected.dropLast()))
    }
}
