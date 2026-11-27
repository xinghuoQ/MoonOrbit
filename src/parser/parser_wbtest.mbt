///|
test "parser smoke" {
  assert_eq(parser_status(), "parser: ready")
}

// ---------------------------------------------------------------------------
// Empty and boundary inputs
// ---------------------------------------------------------------------------

///|
test "empty input produces empty result" {
  let result = parse_markdown("")
  assert_eq(result.html, "")
  assert_eq(result.links.length(), 0)
  assert_eq(result.tags.length(), 0)
}

///|
test "whitespace-only input produces empty html" {
  let result = parse_markdown("   \n\t\n  ")
  assert_eq(result.html, "")
  assert_eq(result.links.length(), 0)
  assert_eq(result.tags.length(), 0)
}

// ---------------------------------------------------------------------------
// Headings
// ---------------------------------------------------------------------------

///|
test "renders h1" {
  let result = parse_markdown("# Title")
  assert_eq(result.html, "<h1>Title</h1>")
}

///|
test "renders h2 through h6" {
  let result = parse_markdown("## Two\n### Three\n#### Four\n##### Five\n###### Six")
  assert_eq(
    result.html,
    "<h2>Two</h2>\n<h3>Three</h3>\n<h4>Four</h4>\n<h5>Five</h5>\n<h6>Six</h6>",
  )
}

///|
test "heading supports bold and collects tags" {
  let result = parse_markdown("# **Bold** #work")
  assert_eq(result.html, "<h1><strong>Bold</strong> #work</h1>")
  assert_eq(result.tags.length(), 1)
  assert_eq(result.tags[0], "work")
}

///|
test "heading level marker is not a tag" {
  let result = parse_markdown("# Title")
  assert_eq(result.tags.length(), 0)
}

// ---------------------------------------------------------------------------
// Paragraphs and inline formatting
// ---------------------------------------------------------------------------

///|
test "renders paragraph" {
  let result = parse_markdown("Hello world")
  assert_eq(result.html, "<p>Hello world</p>")
}

///|
test "joins paragraph soft line breaks with a space" {
  let result = parse_markdown("line one\nline two")
  assert_eq(result.html, "<p>line one line two</p>")
}

///|
test "renders bold" {
  let result = parse_markdown("**bold**")
  assert_eq(result.html, "<p><strong>bold</strong></p>")
}

///|
test "renders italic" {
  let result = parse_markdown("*italic*")
  assert_eq(result.html, "<p><em>italic</em></p>")
}

///|
test "renders italic nested inside bold" {
  let result = parse_markdown("**a *b* c**")
  assert_eq(result.html, "<p><strong>a <em>b</em> c</strong></p>")
}

///|
test "renders bold nested inside italic" {
  let result = parse_markdown("*a **b** c*")
  assert_eq(result.html, "<p><em>a <strong>b</strong> c</em></p>")
}

///|
test "escapes plain html special characters" {
  let result = parse_markdown("a < b & c > d")
  assert_eq(result.html, "<p>a &lt; b &amp; c &gt; d</p>")
}

// ---------------------------------------------------------------------------
// Lists and blockquotes
// ---------------------------------------------------------------------------

///|
test "renders unordered list with dash markers" {
  let result = parse_markdown("- one\n- two")
  assert_eq(result.html, "<ul><li>one</li><li>two</li></ul>")
}

///|
test "renders unordered list with star markers" {
  let result = parse_markdown("* a\n* b")
  assert_eq(result.html, "<ul><li>a</li><li>b</li></ul>")
}

///|
test "renders ordered list" {
  let result = parse_markdown("1. one\n2. two")
  assert_eq(result.html, "<ol><li>one</li><li>two</li></ol>")
}

///|
test "renders inline formatting inside list items" {
  let result = parse_markdown("- **bold** item")
  assert_eq(result.html, "<ul><li><strong>bold</strong> item</li></ul>")
}

///|
test "renders blockquote" {
  let result = parse_markdown("> quoted")
  assert_eq(result.html, "<blockquote>quoted</blockquote>")
}

///|
test "merges consecutive blockquote lines" {
  let result = parse_markdown("> first\n> second")
  assert_eq(result.html, "<blockquote>first second</blockquote>")
}

// ---------------------------------------------------------------------------
// Ordinary Markdown links
// ---------------------------------------------------------------------------

///|
test "renders markdown link" {
  let result = parse_markdown("[Example](https://example.com)")
  assert_eq(result.html, "<p><a href=\"https://example.com\">Example</a></p>")
}

///|
test "renders bold text inside markdown link label" {
  let result = parse_markdown("[**Bold**](https://example.com)")
  assert_eq(
    result.html,
    "<p><a href=\"https://example.com\"><strong>Bold</strong></a></p>",
  )
}

///|
test "does not extract tags from markdown link urls" {
  let result = parse_markdown("[x](https://example.com/#fragment)")
  assert_eq(result.tags.length(), 0)
  assert_eq(result.html, "<p><a href=\"https://example.com/#fragment\">x</a></p>")
}

// ---------------------------------------------------------------------------
// Inline code
// ---------------------------------------------------------------------------

///|
test "inline code escapes html special characters" {
  let result = parse_markdown("`<b> & x`")
  assert_eq(result.html, "<p><code>&lt;b&gt; &amp; x</code></p>")
}

///|
test "inline code does not extract wikilinks" {
  let result = parse_markdown("`[[Nope]]`")
  assert_eq(result.links.length(), 0)
  assert_eq(result.html, "<p><code>[[Nope]]</code></p>")
}

///|
test "inline code does not extract tags" {
  let result = parse_markdown("`#code`")
  assert_eq(result.tags.length(), 0)
  assert_eq(result.html, "<p><code>#code</code></p>")
}

///|
test "inline code marker does not close surrounding bold" {
  let result = parse_markdown("**a `x**y` b**")
  assert_eq(result.html, "<p><strong>a <code>x**y</code> b</strong></p>")
}

// ---------------------------------------------------------------------------
// Fenced code blocks
// ---------------------------------------------------------------------------

///|
test "fenced code block escapes html special characters" {
  let result = parse_markdown("```\n<a> & b\n```")
  assert_eq(result.html, "<pre><code>&lt;a&gt; &amp; b</code></pre>")
}

///|
test "fenced code block does not extract wikilinks or tags" {
  let result = parse_markdown("```\n[[Nope]] #nope\n```")
  assert_eq(result.links.length(), 0)
  assert_eq(result.tags.length(), 0)
  assert_eq(result.html, "<pre><code>[[Nope]] #nope</code></pre>")
}

///|
test "fenced code block ignores language info" {
  let result = parse_markdown("```moonbit\nlet x = 1\n```")
  assert_eq(result.html, "<pre><code>let x = 1</code></pre>")
}

///|
test "fenced code block keeps internal newlines" {
  let result = parse_markdown("```\nline 1\nline 2\n```")
  assert_eq(result.html, "<pre><code>line 1\nline 2</code></pre>")
}

// ---------------------------------------------------------------------------
// Obsidian wikilinks
// ---------------------------------------------------------------------------

///|
test "renders simple wikilink" {
  let result = parse_markdown("See [[Note A]].")
  assert_eq(
    result.html,
    "<p>See <a class=\"wiki-link\" data-target=\"Note A\" href=\"#note/Note A\">Note A</a>.</p>",
  )
  assert_eq(result.links.length(), 1)
  assert_eq(result.links[0].target, "Note A")
  assert_true(result.links[0].alias_text is None)
}

///|
test "renders wikilink with alias" {
  let result = parse_markdown("[[Target|Alias]]")
  assert_eq(
    result.html,
    "<p><a class=\"wiki-link\" data-target=\"Target\" href=\"#note/Target\">Alias</a></p>",
  )
  assert_eq(result.links.length(), 1)
  assert_eq(result.links[0].target, "Target")
  assert_eq(result.links[0].alias_text, Some("Alias"))
}

///|
test "renders chinese wikilink" {
  let result = parse_markdown("[[中文笔记]]")
  assert_eq(
    result.html,
    "<p><a class=\"wiki-link\" data-target=\"中文笔记\" href=\"#note/中文笔记\">中文笔记</a></p>",
  )
  assert_eq(result.links[0].target, "中文笔记")
}

///|
test "trims spaces in chinese wikilink targets and aliases" {
  let result = parse_markdown("[[ 目标 笔记 | 显示 别名 ]]")
  assert_eq(result.links.length(), 1)
  assert_eq(result.links[0].target, "目标 笔记")
  assert_eq(result.links[0].alias_text, Some("显示 别名"))
  assert_true(result.html.contains(">显示 别名</a>"))
}

///|
test "records wikilinks in document order" {
  let result = parse_markdown("[[Alpha]] then [[Beta]]")
  assert_eq(result.links.length(), 2)
  assert_eq(result.links[0].target, "Alpha")
  assert_eq(result.links[1].target, "Beta")
  assert_true(result.html.contains(">Alpha</a>"))
  assert_true(result.html.contains(">Beta</a>"))
}

///|
test "deduplicates repeated identical wikilinks" {
  let result = parse_markdown("[[Alpha]] and [[Alpha]]")
  assert_eq(result.links.length(), 1)
  assert_true(result.html.contains(">Alpha</a>"))
}

///|
test "keeps same target with different aliases" {
  let result = parse_markdown("[[Alpha|x]] [[Alpha|y]]")
  assert_eq(result.links.length(), 2)
}

///|
test "empty wikilink stays literal text" {
  let result = parse_markdown("[[]]")
  assert_eq(result.links.length(), 0)
  assert_eq(result.html, "<p>[[]]</p>")
}

///|
test "unclosed wikilink stays literal text" {
  let result = parse_markdown("[[oops")
  assert_eq(result.links.length(), 0)
  assert_eq(result.html, "<p>[[oops</p>")
}

///|
test "wikilink in list and blockquote is extracted" {
  let result = parse_markdown("- [[Alpha]]\n\n> [[Beta|B]]")
  assert_eq(result.links.length(), 2)
  assert_eq(result.links[0].target, "Alpha")
  assert_eq(result.links[1].target, "Beta")
  assert_true(result.html.contains("<ul><li>"))
  assert_true(result.html.contains("<blockquote>"))
}

// ---------------------------------------------------------------------------
// Obsidian tags
// ---------------------------------------------------------------------------

///|
test "extracts simple tag" {
  let result = parse_markdown("Hello #moonbit world")
  assert_eq(result.tags.length(), 1)
  assert_eq(result.tags[0], "moonbit")
  assert_eq(result.html, "<p>Hello #moonbit world</p>")
}

///|
test "extracts nested tag" {
  let result = parse_markdown("#work/plan")
  assert_eq(result.tags.length(), 1)
  assert_eq(result.tags[0], "work/plan")
}

///|
test "extracts chinese nested tag" {
  let result = parse_markdown("今天 #工作/计划 完成")
  assert_eq(result.tags.length(), 1)
  assert_eq(result.tags[0], "工作/计划")
}

///|
test "deduplicates repeated tags" {
  let result = parse_markdown("#alpha #beta #alpha")
  assert_eq(result.tags.length(), 2)
  assert_eq(result.tags[0], "alpha")
  assert_eq(result.tags[1], "beta")
}

///|
test "csharp token is not a tag" {
  let result = parse_markdown("C# is a language")
  assert_eq(result.tags.length(), 0)
}

///|
test "bare hash is not a tag" {
  let result = parse_markdown("text #")
  assert_eq(result.tags.length(), 0)
}

///|
test "tag after punctuation is extracted" {
  let result = parse_markdown("文字：#标签。")
  assert_eq(result.tags.length(), 1)
  assert_eq(result.tags[0], "标签")
  assert_eq(result.html, "<p>文字：#标签。</p>")
}

///|
test "tag inside wikilink is not extracted separately" {
  let result = parse_markdown("[[Note#Section]]")
  assert_eq(result.links.length(), 1)
  assert_eq(result.links[0].target, "Note#Section")
  assert_eq(result.tags.length(), 0)
}

// ---------------------------------------------------------------------------
// Integration
// ---------------------------------------------------------------------------

///|
test "parses a mixed document end to end" {
  let markdown =
    "# MoonOrbit\n\n" +
    "See [[Alpha]] and #moonbit.\n\n" +
    "- item **one**\n" +
    "- item `code`\n\n" +
    "> quote [[Beta|B]]\n\n" +
    "```\n[[Ignored]] #ignored\n```"
  let result = parse_markdown(markdown)
  assert_true(result.html.contains("<h1>MoonOrbit</h1>"))
  assert_true(
    result.html.contains(
      "<ul><li>item <strong>one</strong></li><li>item <code>code</code></li></ul>",
    ),
  )
  assert_true(result.html.contains("data-target=\"Beta\""))
  assert_true(result.html.contains("<pre><code>[[Ignored]] #ignored</code></pre>"))
  assert_eq(result.links.length(), 2)
  assert_eq(result.links[0].target, "Alpha")
  assert_eq(result.links[1].target, "Beta")
  assert_eq(result.tags.length(), 1)
  assert_eq(result.tags[0], "moonbit")
}
