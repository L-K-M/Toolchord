import Foundation
import Testing
@testable import ToolchordCore

@Suite struct XMLToolsTests {
    func run(_ text: String, format: Bool = false, indent: String = "2", limits: ToolLimits = .standard, cancellation: CancellationCheck = .never) throws -> ToolResult {
        let command = try #require(XMLTools.commands.first { $0.id == (format ? "xml.format" : "xml.validate") })
        return command.run(ToolRequest(input: .text(text), options: ToolOptions(["indent": indent]), limits: limits, cancellation: cancellation))
    }

    func invalid(_ text: String, message: String? = nil, line: Int? = nil, column: Int? = nil) throws {
        // Formatting must have the same validation outcome.
        let validation = try run(text)
        #expect(try run(text, format: true) == validation)
        guard case .invalid(let diagnostic) = validation else {
            Issue.record("Expected invalid XML, got \(validation)")
            return
        }
        if let message { #expect(diagnostic.message == message) }
        #expect(diagnostic.message.last == ".")
        let location = try #require(diagnostic.location)
        if let line { #expect(location.line == line) }
        if let column { #expect(location.column == column) }
    }

    @Test func formattedFixturesAndIdempotence() throws {
        let fixtures: [(String, String, String)] = [
            ("<r xmlns:p=\"urn:example\"><p:a id=\"1\"/><p:b/></r>", "<r xmlns:p=\"urn:example\">\n  <p:a id=\"1\"/>\n  <p:b/>\n</r>", "2"),
            ("<p>Hello <b>world</b> !</p>", "<p>Hello <b>world</b> !</p>", "2"),
            ("<r xml:space=\"preserve\"><x><a/>  <b/><!--keep--><![CDATA[ < ]]><?keep x?></x></r>", "<r xml:space=\"preserve\"><x><a/>  <b/><!--keep--><![CDATA[ < ]]><?keep x?></x></r>", "2"),
            ("<a><b>text</b><c/></a>", "<a>\n  <b>text</b>\n  <c/>\n</a>", "2"),
            ("<?xml version=\"1.0\"?><!--c--><r><x/></r>", "<?xml version=\"1.0\"?>\n<!--c-->\n<r>\n  <x/>\n</r>", "2"),
            ("<a>\n  <b/>\n</a>", "<a>\n    <b/>\n</a>", "4"),
            ("<a><b><c/></b></a>", "<a>\n\t<b>\n\t\t<c/>\n\t</b>\n</a>", "tab"),
            ("<a>   </a>", "<a>   </a>", "2"),
            ("<a><b>x</b><c xml:space=\"preserve\"> <d/> </c></a>", "<a>\n  <b>x</b>\n  <c xml:space=\"preserve\"> <d/> </c>\n</a>", "2"),
            ("<a xml:space=\"preserve\"><b xml:space=\"default\"><c/><d/></b></a>", "<a xml:space=\"preserve\"><b xml:space=\"default\"><c/><d/></b></a>", "2"),
            ("\u{FEFF}<a><b/></a>", "\u{FEFF}<a>\n  <b/>\n</a>", "2"),
        ]
        for (input, expected, indent) in fixtures {
            let output = try #require(run(input, format: true, indent: indent).output)
            #expect(output.primaryText == expected)
            #expect(output.status == "Well-formed XML")
            #expect(output.syntax == .xml)
            #expect(try run(expected, format: true, indent: indent).output?.primaryText == expected)
        }
    }

    @Test func validatesOriginalText() throws {
        let fixtures = [
            "<r xmlns:p=\"urn:example\"><p:x>&amp;&#x20;</p:x></r>",
            "\u{FEFF}<?xml version='1.0' encoding='UTF-8' standalone='yes'?>\r\n<r/>\r\n",
            "<?xml version = '1.123' standalone = 'no' ?><a/>",
            "<a xmlns='u'><b xmlns=''/><c xml:lang='en'/></a>",
            "<a xmlns:p='u'><p:b xmlns:p='v'/><p:c/></a>",
            "<a xmlns:xml='http://www.w3.org/XML/1998/namespace'/>",
            "<a xmlns='u' x='1' xmlns:p='u' p:x='2'/>",
            "<a>&lt;&gt;&amp;&apos;&quot;&#9;&#10;&#13;&#x10FFFF;</a>",
            "<é:根 xmlns:é='u' 属性='✓'><\u{10000}/></é:根>",
            "<!--before--><?p?><a><![CDATA[ & < > ]]><!--after--><?target data?></a><?after?>",
            "<a x='&#xD;\r\n&#x9;&lt;&amp;&quot;&apos;'/>"
        ]
        for text in fixtures {
            let output = try #require(run(text).output, "Expected valid XML: \(text)")
            #expect(output.primaryText == text)
            #expect(output.status == "Well-formed XML")
            #expect(output.syntax == .xml)
        }
    }

    @Test func requiredInvalidFixtures() throws {
        try invalid("<r>\n  </wrong>", message: "Expected “</r>”, found “</wrong>”.", line: 2, column: 3)
        try invalid("<p:x/>", message: "Undeclared namespace prefix “p”.", line: 1, column: 1)
        try invalid("<a b=\"1\" b=\"2\"/>", message: "Duplicate attribute “b”.", line: 1, column: 10)
        try invalid("<a xmlns:p=\"u\" xmlns:q=\"u\" p:x=\"1\" q:x=\"2\"/>", message: "Duplicate expanded attribute name “q:x”.")
        try invalid("<a>&nbsp;</a>", message: "Undefined entity “&nbsp;”. XML only predefines &lt;, &gt;, &amp;, &apos;, and &quot;.", line: 1, column: 4)
        try invalid("<a>", message: "Expected “</a>” before the end of the input.", line: 1, column: 1)
        try invalid("<a/><b/>", message: "Only one root element is allowed.", line: 1, column: 5)
        try invalid("", message: "Expected a root element.", line: 1, column: 1)
        try invalid("hello<a/>", message: "Text isn’t allowed outside the root element.", line: 1, column: 1)
        try invalid("<a x=1/>", message: "Attribute values must be quoted.")
        try invalid("<a><!-- a -- b --></a>")
        try invalid(" <?xml version=\"1.0\"?><a/>", message: "The XML declaration must be at the very start of the document.", line: 1, column: 2)
        try invalid("<a>]]></a>", message: "Character data must not contain “]]>”.", line: 1, column: 4)
        try invalid("<a>\u{1}</a>", message: "Illegal XML character.", line: 1, column: 4)
        try invalid("<a xmlns:p=\"\"/>")
        try invalid("<a>&#xD800;</a>", message: "Character reference refers to an illegal XML character.", line: 1, column: 4)
    }

    @Test func doctypeIsAlwaysUnsupported() throws {
        for text in [
            "<!DOCTYPE r SYSTEM \"https://example.test/r.dtd\"><r/>",
            "<!DOCTYPE r SYSTEM \"file:///example.dtd\"><r/>",
            "<!DOCTYPE r [<!ENTITY x \"text\">]><r>&x;</r>",
            "<?xml version='1.0'?><!--c-->\n<!DOCTYPE totally unfinished\u{1}",
        ] {
            for format in [false, true] {
                #expect(try run(text, format: format) == .unsupported("Document type declarations (DOCTYPE) aren’t supported. Toolchord checks well-formedness without loading DTDs or entities."))
            }
        }
    }

    @Test func malformedMarkupAndReferences() throws {
        for text in [
            "<a x='<'/>", "<a x='&oops;'/>", "<a x='x' y/>", "<a x='1'y='2'/>",
            "<a x='unfinished", "<a", "<a/ >", "<a></a x>", "</a>",
            "<a><!--x---></a>", "<a><!--x</a>", "<a><![CDATA[x</a>",
            "<a><?target data</a>", "<?p!?><a/>", "<![CDATA[x]]><a/>",
            "<a/><!DOCTYPE a>", "<a><!ENTITY x 'y'></a>",
            "<a>&</a>", "<a>&amp</a>", "<a>&#;</a>", "<a>&#x;</a>",
            "<a>&#X20;</a>", "<a>&#0;</a>", "<a>&#xFFFE;</a>", "<a>&#1114112;</a>",
            "<a>&#9999999999999999999999999999999999999999999;</a>",
            "<a>\u{FFFE}</a>", "<a>\u{FFFF}</a>", "<a/>text", "<a/>&amp;",
            "\u{FEFF}\u{FEFF}<a/>", "<!--only-->", " \r\n\t", "<a><b></a></b>",
        ] { try invalid(text) }
    }

    @Test func namesAndNamespaces() throws {
        for text in [
            "<1a/>", "<:a/>", "<a:/>", "<a:b:c/>", "<a xmlns:a='u' a:1x='1'/>",
            "<a xmlns:1p='u'/>", "<\u{F0000}/>", "<\u{37E}/>",
            "<a p:x='1'/>", "<a xmlns:p='u'><b xmlns:p=''/></a>",
            "<a><p:b/></a>", "<a xmlns:p='u'/><p:b/>",
            "<a xmlns:xml='u'/>", "<a xmlns='http://www.w3.org/XML/1998/namespace'/>",
            "<a xmlns:p='http://www.w3.org/XML/1998/namespace'/>",
            "<a xmlns:xmlns='u'/>", "<a xmlns='http://www.w3.org/2000/xmlns/'/>",
            "<a xmlns:p='http://www.w3.org/2000/xmlns/'/>", "<xmlns:a/>",
            "<a xmlns:p='u' xmlns:q='&#117;' p:x='1' q:x='2'/>",
            "<a xmlns:p='u\r\nv' xmlns:q='u v' p:x='1' q:x='2'/>",
        ] { try invalid(text) }
    }

    @Test func unicodeNamesAndURIsCompareExactly() throws {
        // Canonically equivalent Unicode spellings remain distinct XML names.
        for text in [
            "<a é='1' e\u{301}='2'/>",
            "<a xmlns:K='u' xmlns:K='v' K:x='1' K:x='2'/>",
            "<a xmlns:p='urn:é' xmlns:q='urn:e\u{301}' p:x='1' q:x='2'/>",
        ] {
            #expect(try run(text).output?.primaryText == text)
        }
        try invalid("<é></e\u{301}>", message: "Expected “</é>”, found “</e\u{301}>”.", line: 1, column: 4)
        try invalid("<a xmlns:K='u'><K:b/></a>", message: "Undeclared namespace prefix “K”.", line: 1, column: 16)
    }

    @Test func declarationRules() throws {
        for text in [
            "<?xml?><a/>", "<?xml encoding='UTF-8'?><a/>", "<?xml version='2.0'?><a/>",
            "<?xml version='1.'?><a/>", "<?xml version='1.0'encoding='UTF-8'?><a/>",
            "<?xml version='1.0' encoding='8UTF'?><a/>", "<?xml version='1.0' encoding='UTF 8'?><a/>",
            "<?xml version='1.0' standalone='true'?><a/>",
            "<?xml version='1.0' standalone='yes' encoding='UTF-8'?><a/>",
            "<?xml version='1.0' version='1.0'?><a/>",
            "<?xml version='1.0' encoding='UTF-8' encoding='UTF-8'?><a/>",
            "<?xml version='1.0' standalone='no' standalone='no'?><a/>",
            "<?xml version='1.0' weird='x'?><a/>", "<?xml version=1.0?><a/>",
            "<?xml version='1.0'", "<?XML version='1.0'?><a/>", "<a><?xml version='1.0'?></a>",
            "<!--c--><?xml version='1.0'?><a/>",
        ] { try invalid(text) }
    }

    @Test func preservesLiteralRegionsAndDocumentLayout() throws {
        let fixtures: [(String, String)] = [
            (" \r\n<!--before-->\t<?p data?>\r<a x = '1'  ><b \n x=\"&amp;\" />\r\n<!--c--><?keep\n x?></a >\r\n<!--after-->\n", "<!--before-->\n<?p data?>\n<a x = '1'  >\n  <b \n x=\"&amp;\" />\n  <!--c-->\n  <?keep\n x?>\n</a >\n<!--after-->"),
            ("<a><b/> &#x20;<c><d/></c></a>", "<a><b/> &#x20;<c><d/></c></a>"),
            ("<a><b/><![CDATA[ ]]><c/></a>", "<a><b/><![CDATA[ ]]><c/></a>"),
            ("<a><b/>\u{A0}<c/></a>", "<a><b/>\u{A0}<c/></a>"),
            ("<a>\r\ntext<b><c/></b></a>", "<a>\r\ntext<b><c/></b></a>"),
            ("<a><!--c--><?p?></a>", "<a>\n  <!--c-->\n  <?p?>\n</a>"),
            ("<a/>", "<a/>"),
            ("\u{FEFF} \r\n<a/>\r", "\u{FEFF}<a/>"),
            ("<a><b xml:space='preserve'><c xml:space='default'><d/></c></b></a>", "<a>\n  <b xml:space='preserve'><c xml:space='default'><d/></c></b>\n</a>"),
        ]
        for (input, expected) in fixtures {
            #expect(try run(input, format: true).output?.primaryText == expected)
            #expect(try run(expected, format: true).output?.primaryText == expected)
        }
    }

    @Test func correctOriginalLocations() throws {
        try invalid("<r>\r\n  </wrong>", line: 2, column: 3)
        try invalid("<r>\r  </wrong>", line: 2, column: 3)
        try invalid("<r>é🙂&nbsp;</r>", line: 1, column: 6)
        try invalid("<r>\r\n<a>\r\n", message: "Expected “</a>” before the end of the input.", line: 2, column: 1)
        try invalid("\u{FEFF}<p:x/>", line: 1, column: 2)
    }

    @Test func nestingLimits() throws {
        let atLimit = String(repeating: "<a>", count: 128) + String(repeating: "</a>", count: 128)
        #expect(try run(atLimit).isSuccess)
        let tooDeep = String(repeating: "<a>", count: 129) + String(repeating: "</a>", count: 129)
        for format in [false, true] {
            #expect(try run(tooDeep, format: format) == .tooLarge(ToolLimits.standard.nestingLimitMessage))
        }
        #expect(try run("<a><b/></a>", limits: ToolLimits(maxNestingDepth: 1)) == .tooLarge("Nesting is deeper than 1 levels."))
    }

    @Test func outputLimitsCancellationAndMissingInput() throws {
        let limits = ToolLimits(maxOutputBytes: 9)
        #expect(try run("<a><b/></a>", format: true, limits: limits) == .tooLarge(limits.outputLimitMessage))
        #expect(try run("<a>text</a>", limits: limits) == .tooLarge(limits.outputLimitMessage))
        #expect(try run("<a/>", format: true, limits: ToolLimits(maxOutputBytes: 4)).output?.primaryText == "<a/>")
        #expect(try run("<a/>", cancellation: CancellationCheck { true }) == .cancelled)
        #expect(try run("", cancellation: CancellationCheck { true }) == .cancelled)
        for command in XMLTools.commands {
            guard case .needsInput = command.run(ToolRequest(input: .none)) else {
                Issue.record("Expected needsInput"); continue
            }
        }
    }

    @Test func processingInstructionTargetsAreNCNames() throws {
        let fixtures: [(String, Int, Int)] = [
            ("<?p:q?><r/>", 1, 4),
            ("<?bad:target data?><r/>", 1, 6),
            ("<r><?p:q x?></r>", 1, 7),
            ("<r/>\n<?p:q?>", 2, 4),
            ("<?:p?><r/>", 1, 3),
            ("<?p:?><r/>", 1, 4),
            ("<r>é🙂<?根:p?></r>", 1, 9),
            ("<r/>\r\n<?p:q?>", 2, 4),
            ("<r/>\r<?p:q?>", 2, 4),
        ]
        for (text, line, column) in fixtures {
            try invalid(text, message: "Processing instruction targets can’t contain “:”.", line: line, column: column)
        }
        #expect(try run("<r><?ok data?></r>").output?.primaryText == "<r><?ok data?></r>")
        #expect(try run("<r><?ok data?></r>", format: true).output?.primaryText == "<r>\n  <?ok data?>\n</r>")
    }

    @Test func namespaceScopesAreRestored() throws {
        let input = "<r xmlns:p=\"urn:a\"><c xmlns:p=\"urn:b\"><p:x/></c><p:y/></r>"
        #expect(try run(input).output?.primaryText == input)
        #expect(try run(input, format: true).output?.primaryText == "<r xmlns:p=\"urn:a\">\n  <c xmlns:p=\"urn:b\">\n    <p:x/>\n  </c>\n  <p:y/>\n</r>")
        try invalid("<r><c xmlns:p=\"urn:u\"/><p:x/></r>", message: "Undeclared namespace prefix “p”.", line: 1, column: 24)
        try invalid("<r xmlns:p=\"urn:a\"><c xmlns:p=\"urn:b\" p:k=\"1\"/><d p:k=\"1\" xmlns:q=\"urn:a\" q:k=\"2\"/></r>", message: "Duplicate expanded attribute name “q:k”.")
        // A non-empty child must also remove bindings that did not exist before it.
        try invalid("<r><c xmlns:p='u'></c><p:x/></r>", message: "Undeclared namespace prefix “p”.", line: 1, column: 23)
        // Multiple nested overrides must restore the original URI for attributes.
        #expect(try run("<r xmlns:p='a'><c xmlns:p='b'><d xmlns:p='c'/></c><e xmlns:q='b' p:k='1' q:k='2'/></r>").isSuccess)
    }

    @Test func namespaceDeclarationScale() throws {
        var root = "<r"
        for index in 0..<20_000 { root += " xmlns:p\(index)=\"urn:\(index)\"" }
        root += ">"
        let child = "<c xmlns:p1=\"urn:x\"/>"
        let input = root + String(repeating: child, count: 10_000) + "</r>"
        let expected = root + String(repeating: "\n  " + child, count: 10_000) + "\n</r>"
        for format in [false, true] {
            let start = ContinuousClock.now
            let result = try run(input, format: format)
            let elapsed = start.duration(to: .now)
            print("XML namespace scale (\(format ? "Format" : "Validate")): \(elapsed)")
            #expect(elapsed < .seconds(2))
            #expect(result.output?.primaryText == (format ? expected : input))
        }
    }

    @Test func oneMiBDocument() throws {
        // Exactly 1 MiB including markup. Its text is verbatim by definition.
        let input = "<a>" + String(repeating: "x", count: (1 << 20) - 7) + "</a>"
        #expect(input.utf8.count == 1 << 20)
        #expect(try run(input, format: true).output?.primaryText == input)
        // Many structural siblings exercise tokenization and output construction.
        let count = ((1 << 20) - 7) / 4
        let structural = "<a>" + String(repeating: "<b/>", count: count) + "</a>"
        let expected = "<a>" + String(repeating: "\n  <b/>", count: count) + "\n</a>"
        #expect(try run(structural, format: true).output?.primaryText == expected)
    }
}
