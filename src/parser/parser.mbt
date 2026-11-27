///|
/// A wikilink occurrence found in the Markdown source.
///
/// `target` is the note name inside `[[...]]`; `alias_text` is the optional
/// display text after `|` in `[[target|alias]]`.
pub struct WikiLink {
  target : String
  alias_text : String?
}

///|
/// Result of parsing one Markdown document.
///
/// `html` is the rendered HTML, `links` holds wikilinks in document order
/// (deduplicated by target + alias), and `tags` holds tags in document order
/// (deduplicated).
pub struct ParseResult {
  html : String
  links : Array[WikiLink]
  tags : Array[String]
}

///|
/// Placeholder status kept for the Stage 1 bridge smoke test.
pub fn parser_status() -> String {
  "parser: ready"
}

///|
/// Parse Markdown with Obsidian-style `[[wikilinks]]` and `#tags` into HTML,
/// while collecting wikilinks and tags as structured data.
pub fn parse_markdown(input : String) -> ParseResult {
  let links : Array[WikiLink] = []
  let tags : Array[String] = []
  let html = render_document(input, links, tags)
  { html: html, links: links, tags: tags }
}

// ---------------------------------------------------------------------------
// Character helpers
// ---------------------------------------------------------------------------

///|
/// Read the character at `i`, or NUL when `i` is out of range or lands on a
/// lone surrogate. Markers used by this parser are all ASCII, so guard reads
/// are enough for correctness.
fn char_at(s : String, i : Int32) -> Char {
  s.get_char(i).unwrap_or('\u{0}')
}

///|
fn is_space_char(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r' || c == '\n'
}

///|
fn trim_space(s : String) -> String {
  let mut start = 0
  let mut end = s.length()
  while start < end && is_space_char(char_at(s, start)) {
    start += 1
  }
  while end > start && is_space_char(char_at(s, end - 1)) {
    end -= 1
  }
  s[start:end].to_owned()
}

///|
fn is_cjk(c : Char) -> Bool {
  let n = c.to_int()
  (n >= 0x4E00 && n <= 0x9FFF) ||
  (n >= 0x3400 && n <= 0x4DBF) ||
  (n >= 0xF900 && n <= 0xFAFF)
}

///|
fn is_tag_start(c : Char) -> Bool {
  c.is_ascii_alphabetic() || c == '_' || is_cjk(c)
}

///|
fn is_tag_char(c : Char) -> Bool {
  c.is_ascii_alphabetic() ||
  c.is_ascii_digit() ||
  c == '_' ||
  c == '-' ||
  c == '/' ||
  is_cjk(c)
}

///|
/// A `#` only starts a tag at the beginning of inline text or after a
/// non-word character. `C#` and `foo#bar` are therefore not tags.
fn is_tag_boundary(s : String, i : Int32) -> Bool {
  if i == 0 {
    true
  } else {
    let prev = char_at(s, i - 1)
    !is_tag_char(prev) &&
    prev != '/' &&
    prev != ':' &&
    prev != '?' &&
    prev != '&' &&
    prev != '='
  }
}

// ---------------------------------------------------------------------------
// Escaping
// ---------------------------------------------------------------------------

///|
fn write_escaped(sb : StringBuilder, c : Char) -> Unit {
  if c == '&' {
    sb.write_string("&amp;")
  } else if c == '<' {
    sb.write_string("&lt;")
  } else if c == '>' {
    sb.write_string("&gt;")
  } else {
    sb.write_char(c)
  }
}

///|
fn escape_html(s : String) -> String {
  let sb = StringBuilder()
  let n = s.length()
  let mut i = 0
  while i < n {
    write_escaped(sb, char_at(s, i))
    i += 1
  }
  sb.to_string()
}

///|
fn escape_attr(s : String) -> String {
  let sb = StringBuilder()
  let n = s.length()
  let mut i = 0
  while i < n {
    let c = char_at(s, i)
    if c == '"' {
      sb.write_string("&quot;")
    } else {
      write_escaped(sb, c)
    }
    i += 1
  }
  sb.to_string()
}

// ---------------------------------------------------------------------------
// Inline scanning helpers
// ---------------------------------------------------------------------------

///|
fn find_char_from(s : String, from : Int32, target : Char) -> Int32? {
  let n = s.length()
  let mut i = from
  while i < n {
    if char_at(s, i) == target {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
fn find_wiki_close(s : String, from : Int32) -> Int32? {
  let n = s.length()
  let mut i = from
  while i + 1 < n {
    if char_at(s, i) == ']' && char_at(s, i + 1) == ']' {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
/// Find the closing `**` of a bold span, skipping inline code and wikilinks so
/// markers inside them cannot close the span.
fn find_bold_close(s : String, from : Int32) -> Int32? {
  let n = s.length()
  let mut i = from
  while i + 1 < n {
    let c = char_at(s, i)
    if c == '`' {
      match find_char_from(s, i + 1, '`') {
        Some(close) => i = close + 1
        None => return None
      }
    } else if c == '[' && char_at(s, i + 1) == '[' {
      match find_wiki_close(s, i + 2) {
        Some(close) => i = close + 2
        None => i += 1
      }
    } else if c == '*' && char_at(s, i + 1) == '*' {
      return Some(i)
    } else {
      i += 1
    }
  }
  None
}

///|
/// Find the closing single `*` of an italic span. Entire `**bold**` spans,
/// inline code and wikilinks are skipped so their markers are not consumed.
fn find_italic_close(s : String, from : Int32) -> Int32? {
  let n = s.length()
  let mut i = from
  while i < n {
    let c = char_at(s, i)
    if c == '`' {
      match find_char_from(s, i + 1, '`') {
        Some(close) => i = close + 1
        None => return None
      }
    } else if c == '[' && char_at(s, i + 1) == '[' {
      match find_wiki_close(s, i + 2) {
        Some(close) => i = close + 2
        None => i += 1
      }
    } else if c == '*' {
      if char_at(s, i + 1) == '*' {
        match find_bold_close(s, i + 2) {
          Some(close) => i = close + 2
          None => i += 1
        }
      } else {
        return Some(i)
      }
    } else {
      i += 1
    }
  }
  None
}

// ---------------------------------------------------------------------------
// Wikilinks
// ---------------------------------------------------------------------------

///|
/// Parse `[[target]]` or `[[target|alias]]` starting at `start`.
/// Returns `(target, alias, next_index)` on success.
fn parse_wiki_link(s : String, start : Int32) -> (String, String?, Int32)? {
  match find_wiki_close(s, start + 2) {
    None => None
    Some(close) => {
      let inner = s[start + 2:close].to_owned()
      let mut target_raw = inner
      let mut alias_raw = ""
      let mut has_alias = false
      match inner.find("|") {
        Some(pipe) => {
          has_alias = true
          target_raw = inner[0:pipe].to_owned()
          alias_raw = inner[pipe + 1:inner.length()].to_owned()
        }
        None => ()
      }
      let target = trim_space(target_raw)
      if target.length() == 0 {
        None
      } else {
        let alias_trimmed = trim_space(alias_raw)
        let alias_opt : String? = if has_alias && alias_trimmed.length() > 0 {
          Some(alias_trimmed)
        } else {
          None
        }
        Some((target, alias_opt, close + 2))
      }
    }
  }
}

///|
fn contains_link(
  links : Array[WikiLink],
  target : String,
  alias_opt : String?,
) -> Bool {
  let mut i = 0
  while i < links.length() {
    let link = links[i]
    if link.target == target {
      let same_alias = match (link.alias_text, alias_opt) {
        (None, None) => true
        (Some(a), Some(b)) => a == b
        _ => false
      }
      if same_alias {
        return true
      }
    }
    i += 1
  }
  false
}

///|
fn record_link(
  links : Array[WikiLink],
  target : String,
  alias_opt : String?,
) -> Unit {
  if !contains_link(links, target, alias_opt) {
    links.push({ target: target, alias_text: alias_opt })
  }
}

///|
fn wiki_link_html(target : String, alias_opt : String?) -> String {
  let display = match alias_opt {
    Some(text) => text
    None => target
  }
  "<a class=\"wiki-link\" data-target=\"" +
  escape_attr(target) +
  "\" href=\"#note/" +
  escape_attr(target) +
  "\">" +
  escape_html(display) +
  "</a>"
}

// ---------------------------------------------------------------------------
// Markdown links
// ---------------------------------------------------------------------------

///|
/// Parse `[label](url)` starting at `start`. Returns `(label, url, next_index)`.
fn parse_markdown_link(s : String, start : Int32) -> (String, String, Int32)? {
  match find_char_from(s, start + 1, ']') {
    None => None
    Some(bracket) => {
      if bracket + 1 < s.length() && char_at(s, bracket + 1) == '(' {
        match find_char_from(s, bracket + 2, ')') {
          None => None
          Some(paren) => {
            Some((
              s[start + 1:bracket].to_owned(),
              s[bracket + 2:paren].to_owned(),
              paren + 1,
            ))
          }
        }
      } else {
        None
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Tags
// ---------------------------------------------------------------------------

///|
/// Scan a tag starting at the `#` at `start`. Returns `(tag_without_hash,
/// next_index)`. Trailing `/` characters are not part of the tag.
fn scan_tag(s : String, start : Int32) -> (String, Int32)? {
  let n = s.length()
  let mut j = start + 1
  if j >= n || !is_tag_start(char_at(s, j)) {
    return None
  }
  while j < n && is_tag_char(char_at(s, j)) {
    j += 1
  }
  let mut end = j
  while end > start + 1 && char_at(s, end - 1) == '/' {
    end -= 1
  }
  let tag = s[start + 1:end].to_owned()
  if tag.length() == 0 {
    None
  } else {
    Some((tag, end))
  }
}

///|
fn contains_tag(tags : Array[String], tag : String) -> Bool {
  let mut i = 0
  while i < tags.length() {
    if tags[i] == tag {
      return true
    }
    i += 1
  }
  false
}

// ---------------------------------------------------------------------------
// Inline rendering
// ---------------------------------------------------------------------------

///|
/// Render one line of inline Markdown, collecting wikilinks and tags as a side
/// effect. Inline code is handled first so its contents are neither formatted
/// nor scanned for links/tags.
fn render_inline(
  text : String,
  links : Array[WikiLink],
  tags : Array[String],
) -> String {
  let sb = StringBuilder()
  let n = text.length()
  let mut i = 0
  while i < n {
    let c = char_at(text, i)
    if c == '`' {
      match find_char_from(text, i + 1, '`') {
        Some(close) => {
          sb.write_string("<code>")
          sb.write_string(escape_html(text[i + 1:close].to_owned()))
          sb.write_string("</code>")
          i = close + 1
        }
        None => {
          write_escaped(sb, c)
          i += 1
        }
      }
    } else if c == '[' && char_at(text, i + 1) == '[' {
      match parse_wiki_link(text, i) {
        Some((target, alias_opt, next)) => {
          record_link(links, target, alias_opt)
          sb.write_string(wiki_link_html(target, alias_opt))
          i = next
        }
        None => {
          write_escaped(sb, c)
          i += 1
        }
      }
    } else if c == '[' {
      match parse_markdown_link(text, i) {
        Some((label, url, next)) => {
          sb.write_string("<a href=\"")
          sb.write_string(escape_attr(url))
          sb.write_string("\">")
          sb.write_string(render_inline(label, links, tags))
          sb.write_string("</a>")
          i = next
        }
        None => {
          write_escaped(sb, c)
          i += 1
        }
      }
    } else if c == '*' && char_at(text, i + 1) == '*' {
      match find_bold_close(text, i + 2) {
        Some(close) => {
          if close > i + 2 {
            sb.write_string("<strong>")
            sb.write_string(
              render_inline(text[i + 2:close].to_owned(), links, tags),
            )
            sb.write_string("</strong>")
            i = close + 2
          } else {
            write_escaped(sb, c)
            i += 1
          }
        }
        None => {
          write_escaped(sb, c)
          i += 1
        }
      }
    } else if c == '*' {
      match find_italic_close(text, i + 1) {
        Some(close) => {
          if close > i + 1 {
            sb.write_string("<em>")
            sb.write_string(
              render_inline(text[i + 1:close].to_owned(), links, tags),
            )
            sb.write_string("</em>")
            i = close + 1
          } else {
            write_escaped(sb, c)
            i += 1
          }
        }
        None => {
          write_escaped(sb, c)
          i += 1
        }
      }
    } else if c == '#' && is_tag_boundary(text, i) {
      match scan_tag(text, i) {
        Some((tag, next)) => {
          sb.write_char('#')
          sb.write_string(escape_html(tag))
          if !contains_tag(tags, tag) {
            tags.push(tag)
          }
          i = next
        }
        None => {
          write_escaped(sb, c)
          i += 1
        }
      }
    } else {
      write_escaped(sb, c)
      i += 1
    }
  }
  sb.to_string()
}

// ---------------------------------------------------------------------------
// Block helpers
// ---------------------------------------------------------------------------

///|
fn split_lines(input : String) -> Array[String] {
  let lines : Array[String] = []
  let n = input.length()
  let mut start = 0
  let mut i = 0
  while i < n {
    if char_at(input, i) == '\n' {
      let mut end = i
      if end > start && char_at(input, end - 1) == '\r' {
        end -= 1
      }
      lines.push(input[start:end].to_owned())
      start = i + 1
    }
    i += 1
  }
  let mut end = n
  if end > start && char_at(input, end - 1) == '\r' {
    end -= 1
  }
  lines.push(input[start:end].to_owned())
  lines
}

///|
fn join_parts(parts : Array[String], sep : String) -> String {
  let sb = StringBuilder()
  let mut i = 0
  while i < parts.length() {
    if i > 0 {
      sb.write_string(sep)
    }
    sb.write_string(parts[i])
    i += 1
  }
  sb.to_string()
}

///|
fn fence_marker_len(s : String) -> Int32 {
  let mut count = 0
  while count < s.length() && count < 3 && char_at(s, count) == '`' {
    count += 1
  }
  if count == 3 {
    3
  } else {
    0
  }
}

///|
fn is_closing_fence(s : String) -> Bool {
  if fence_marker_len(s) < 3 {
    return false
  }
  let mut i = 3
  while i < s.length() {
    if char_at(s, i) != '`' {
      return false
    }
    i += 1
  }
  true
}

///|
fn heading_hash_count(s : String) -> Int32 {
  let mut count = 0
  while count < s.length() && count < 7 && char_at(s, count) == '#' {
    count += 1
  }
  count
}

///|
/// Length of a valid heading prefix (`#`..`######` plus one space), or 0.
fn heading_prefix_len(s : String) -> Int32 {
  let count = heading_hash_count(s)
  if count == 0 || count > 6 {
    return 0
  }
  if count == s.length() {
    return count
  }
  if char_at(s, count) == ' ' {
    return count + 1
  }
  0
}

///|
fn unordered_marker_len(s : String) -> Int32 {
  if s.length() >= 2 &&
    (char_at(s, 0) == '-' || char_at(s, 0) == '*') &&
    char_at(s, 1) == ' ' {
    2
  } else {
    0
  }
}

///|
fn ordered_marker_len(s : String) -> Int32 {
  let mut i = 0
  while i < s.length() && char_at(s, i).is_ascii_digit() {
    i += 1
  }
  if i > 0 &&
    i + 1 < s.length() &&
    char_at(s, i) == '.' &&
    char_at(s, i + 1) == ' ' {
    i + 2
  } else {
    0
  }
}

///|
fn is_block_start(s : String) -> Bool {
  if s.length() == 0 {
    return true
  }
  if fence_marker_len(s) >= 3 {
    return true
  }
  if heading_prefix_len(s) > 0 {
    return true
  }
  if s.has_prefix(">") {
    return true
  }
  if unordered_marker_len(s) > 0 {
    return true
  }
  if ordered_marker_len(s) > 0 {
    return true
  }
  false
}

///|
fn strip_quote_prefix(s : String) -> String {
  let rest = s[1:s.length()].to_owned()
  if rest.length() > 0 && char_at(rest, 0) == ' ' {
    trim_space(rest[1:rest.length()].to_owned())
  } else {
    trim_space(rest)
  }
}

// ---------------------------------------------------------------------------
// Block rendering
// ---------------------------------------------------------------------------

///|
fn render_blocks(
  lines : Array[String],
  links : Array[WikiLink],
  tags : Array[String],
) -> Array[String] {
  let blocks : Array[String] = []
  let n = lines.length()
  let mut i = 0
  while i < n {
    let current = trim_space(lines[i])
    if current.length() == 0 {
      i += 1
    } else if fence_marker_len(current) >= 3 {
      let content : Array[String] = []
      let mut j = i + 1
      while j < n {
        let candidate = trim_space(lines[j])
        if is_closing_fence(candidate) {
          j += 1
          break
        }
        content.push(lines[j])
        j += 1
      }
      blocks.push("<pre><code>" + escape_html(join_parts(content, "\n")) + "</code></pre>")
      i = j
    } else if heading_prefix_len(current) > 0 {
      let prefix = heading_prefix_len(current)
      let level = heading_hash_count(current)
      let text = trim_space(current[prefix:current.length()].to_owned())
      let level_text = level.to_string()
      blocks.push(
        "<h" +
        level_text +
        ">" +
        render_inline(text, links, tags) +
        "</h" +
        level_text +
        ">",
      )
      i += 1
    } else if current.has_prefix(">") {
      let quoted : Array[String] = []
      let mut j = i
      while j < n {
        let candidate = trim_space(lines[j])
        if candidate.has_prefix(">") {
          quoted.push(strip_quote_prefix(candidate))
          j += 1
        } else {
          break
        }
      }
      blocks.push("<blockquote>" + render_inline(join_parts(quoted, " "), links, tags) + "</blockquote>")
      i = j
    } else if unordered_marker_len(current) > 0 {
      let items : Array[String] = []
      let mut j = i
      while j < n {
        let candidate = trim_space(lines[j])
        let marker = unordered_marker_len(candidate)
        if marker > 0 {
          let item_text = trim_space(candidate[marker:candidate.length()].to_owned())
          items.push("<li>" + render_inline(item_text, links, tags) + "</li>")
          j += 1
        } else {
          break
        }
      }
      blocks.push("<ul>" + join_parts(items, "") + "</ul>")
      i = j
    } else if ordered_marker_len(current) > 0 {
      let items : Array[String] = []
      let mut j = i
      while j < n {
        let candidate = trim_space(lines[j])
        let marker = ordered_marker_len(candidate)
        if marker > 0 {
          let item_text = trim_space(candidate[marker:candidate.length()].to_owned())
          items.push("<li>" + render_inline(item_text, links, tags) + "</li>")
          j += 1
        } else {
          break
        }
      }
      blocks.push("<ol>" + join_parts(items, "") + "</ol>")
      i = j
    } else {
      let paragraph : Array[String] = []
      let mut j = i
      while j < n {
        let candidate = trim_space(lines[j])
        if candidate.length() == 0 || is_block_start(candidate) {
          break
        }
        paragraph.push(candidate)
        j += 1
      }
      blocks.push("<p>" + render_inline(join_parts(paragraph, " "), links, tags) + "</p>")
      i = j
    }
  }
  blocks
}

///|
fn render_document(
  input : String,
  links : Array[WikiLink],
  tags : Array[String],
) -> String {
  join_parts(render_blocks(split_lines(input), links, tags), "\n")
}
