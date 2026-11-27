///|
/// Stage 1 smoke test kept alive across the bridge rewrite.
test "bridge smoke" {
  assert_eq(bridge_status(), "parser: ready | graph: ready | layout: ready")
}

// ---------------------------------------------------------------------------
// JSON test helpers
// ---------------------------------------------------------------------------

///|
fn parse_json(text : String) -> Json {
  @json.parse(text) catch {
    (error : @json.ParseError) =>
      abort("expected valid JSON, got: " + error.to_string())
  }
}

///|
fn as_object(json : Json) -> Map[String, Json] {
  match json {
    Object(obj) => obj
    _ => abort("expected a JSON object")
  }
}

///|
fn as_array(json : Json) -> Array[Json] {
  match json {
    Array(items) => items
    _ => abort("expected a JSON array")
  }
}

///|
fn as_string(json : Json) -> String {
  match json {
    String(value) => value
    _ => abort("expected a JSON string")
  }
}

///|
fn as_bool(json : Json) -> Bool {
  match json {
    True => true
    False => false
    _ => abort("expected a JSON boolean")
  }
}

///|
fn as_number(json : Json) -> Double {
  match json {
    Number(value, ..) => value
    _ => abort("expected a JSON number")
  }
}

///|
fn as_int(json : Json) -> Int {
  as_number(json).to_int()
}

///|
fn is_null(json : Json) -> Bool {
  match json {
    Null => true
    _ => false
  }
}

///|
fn field(obj : Map[String, Json], key : String) -> Json {
  match obj.get(key) {
    Some(value) => value
    None => abort("missing JSON field: " + key)
  }
}

///|
fn join_strings(items : Array[String], sep : String) -> String {
  let sb = StringBuilder()
  let mut i = 0
  while i < items.length() {
    if i > 0 {
      sb.write_string(sep)
    }
    sb.write_string(items[i])
    i += 1
  }
  sb.to_string()
}

///|
fn item_ids_text(items : Array[Json]) -> String {
  let ids : Array[String] = []
  let mut i = 0
  while i < items.length() {
    ids.push(as_string(field(as_object(items[i]), "id")))
    i += 1
  }
  join_strings(ids, ",")
}

///|
fn has_node(nodes : Array[Json], id : String) -> Bool {
  let mut i = 0
  while i < nodes.length() {
    if as_string(field(as_object(nodes[i]), "id")) == id {
      return true
    }
    i += 1
  }
  false
}

///|
fn find_node(nodes : Array[Json], id : String) -> Map[String, Json] {
  let mut i = 0
  while i < nodes.length() {
    let node = as_object(nodes[i])
    if as_string(field(node, "id")) == id {
      return node
    }
    i += 1
  }
  abort("node not found: " + id)
}

///|
/// Build a workspace request from the built-in sample vault.
fn sample_workspace_request(extra : String) -> String {
  "{\"notes\":" +
  get_sample_notes_json() +
  ",\"active_id\":\"guide\"" +
  extra +
  "}"
}

///|
/// Assert that the request produces the standard failure envelope and return
/// its error text.
fn expect_failure(request : String) -> String raise {
  let response = as_object(parse_json(compute_workspace_json(request)))
  assert_false(as_bool(field(response, "ok")))
  assert_eq(response.length(), 2)
  let error = field(response, "error")
  assert_false(is_null(error))
  let message = as_string(error)
  assert_true(message.length() > 0)
  message
}

///|
/// Same failure-envelope assertion for the vault query API.
fn expect_query_failure(request : String) -> String raise {
  let response = as_object(parse_json(query_notes_json(request)))
  assert_false(as_bool(field(response, "ok")))
  assert_eq(response.length(), 2)
  let error = field(response, "error")
  assert_false(is_null(error))
  let message = as_string(error)
  assert_true(message.length() > 0)
  message
}

// ---------------------------------------------------------------------------
// render_markdown_json
// ---------------------------------------------------------------------------

///|
test "render_markdown_json returns valid html, links and tags" {
  let response = as_object(
    parse_json(render_markdown_json("# 标题\n\n**粗体** #标签")),
  )
  let html = as_string(field(response, "html"))
  assert_true(html.contains("<h1>标题</h1>"))
  assert_true(html.contains("<strong>粗体</strong>"))
  assert_eq(as_array(field(response, "links")).length(), 0)
  let tags = as_array(field(response, "tags"))
  assert_eq(tags.length(), 1)
  assert_eq(as_string(tags[0]), "标签")
}

///|
test "render_markdown_json keeps alias null for plain wikilinks" {
  let response = as_object(parse_json(render_markdown_json("[[目标笔记]]")))
  let links = as_array(field(response, "links"))
  assert_eq(links.length(), 1)
  let link = as_object(links[0])
  assert_eq(as_string(field(link, "target")), "目标笔记")
  assert_true(is_null(field(link, "alias")))
  assert_true(as_string(field(response, "html")).contains("wiki-link"))
}

///|
test "render_markdown_json reports alias text for aliased wikilinks" {
  let response = as_object(
    parse_json(render_markdown_json("[[目标笔记|显示文本]]")),
  )
  let link = as_object(as_array(field(response, "links"))[0])
  assert_eq(as_string(field(link, "target")), "目标笔记")
  assert_eq(as_string(field(link, "alias")), "显示文本")
}

///|
test "render_markdown_json escapes special characters into valid JSON" {
  let source = "**a < b & \"c\"**\n\n#tag"
  let text = render_markdown_json(source)
  let response = as_object(parse_json(text))
  let html = as_string(field(response, "html"))
  assert_true(html.contains("&lt;"))
  assert_true(html.contains("&amp;"))
  assert_true(html.contains("\"c\""))
  assert_eq(as_string(as_array(field(response, "tags"))[0]), "tag")
}

///|
test "render_markdown_json handles empty input" {
  let response = as_object(parse_json(render_markdown_json("")))
  assert_eq(as_string(field(response, "html")), "")
  assert_eq(as_array(field(response, "links")).length(), 0)
  assert_eq(as_array(field(response, "tags")).length(), 0)
}

///|
test "render_markdown_json deduplicates repeated links and tags" {
  let response = as_object(
    parse_json(render_markdown_json("[[A]] [[A]] #x #x")),
  )
  assert_eq(as_array(field(response, "links")).length(), 1)
  assert_eq(as_array(field(response, "tags")).length(), 1)
}

// ---------------------------------------------------------------------------
// get_sample_notes_json
// ---------------------------------------------------------------------------

///|
test "get_sample_notes_json returns six valid notes" {
  let notes = as_array(parse_json(get_sample_notes_json()))
  assert_eq(notes.length(), 6)
  let mut i = 0
  while i < notes.length() {
    let note = as_object(notes[i])
    assert_true(as_string(field(note, "id")).length() > 0)
    assert_true(as_string(field(note, "title")).length() > 0)
    assert_true(as_string(field(note, "content")).length() > 0)
    i += 1
  }
  assert_eq(
    item_ids_text(notes),
    "guide,markdown-syntax,wikilinks,tags,local-graph,moonbit",
  )
}

///|
test "sample notes cover aliases, tags and a ghost link" {
  let notes = as_array(parse_json(get_sample_notes_json()))
  let all = StringBuilder()
  let mut i = 0
  while i < notes.length() {
    all.write_string(as_string(field(as_object(notes[i]), "content")))
    all.write_string("\n")
    i += 1
  }
  let text = all.to_string()
  assert_true(text.contains("[[路线图规划]]"))
  assert_true(text.contains("[[MoonBit 语言特性|MoonBit 1.0 特性]]"))
  assert_true(text.contains("#moonbit"))
  assert_true(text.contains("#标签"))
}

// ---------------------------------------------------------------------------
// compute_workspace_json: success paths
// ---------------------------------------------------------------------------

///|
test "compute_workspace_json returns the full response envelope" {
  let response = as_object(
    parse_json(compute_workspace_json(sample_workspace_request(",\"depth\":2"))),
  )
  assert_true(as_bool(field(response, "ok")))
  assert_true(is_null(field(response, "error")))
  assert_eq(response.length(), 6)
  let render = as_object(field(response, "active_render"))
  assert_true(as_string(field(render, "html")).length() > 0)
}

///|
test "compute_workspace_json renders the active note" {
  let response = as_object(
    parse_json(compute_workspace_json(sample_workspace_request(",\"depth\":1"))),
  )
  let render = as_object(field(response, "active_render"))
  let html = as_string(field(render, "html"))
  assert_true(html.contains("<h1>MoonOrbit 使用指南</h1>"))
  let tags = as_array(field(render, "tags"))
  assert_eq(as_string(tags[0]), "指南")
  assert_eq(as_string(tags[1]), "moonorbit")
  let links = as_array(field(render, "links"))
  let aliased = as_object(links[3])
  assert_eq(as_string(field(aliased, "target")), "MoonBit 语言特性")
  assert_eq(as_string(field(aliased, "alias")), "MoonBit 1.0 特性")
}

///|
test "compute_workspace_json reports backlinks in insertion order" {
  let response = as_object(
    parse_json(compute_workspace_json(sample_workspace_request(",\"depth\":2"))),
  )
  let backlinks = as_array(field(response, "backlinks"))
  assert_eq(backlinks.length(), 3)
  assert_eq(item_ids_text(backlinks), "wikilinks,local-graph,moonbit")
  let first = as_object(backlinks[0])
  assert_eq(as_string(field(first, "title")), "双链笔记")
}

///|
test "compute_workspace_json lists unresolved links once" {
  let response = as_object(
    parse_json(compute_workspace_json(sample_workspace_request(",\"depth\":2"))),
  )
  let unresolved = as_array(field(response, "unresolved_links"))
  assert_eq(unresolved.length(), 1)
  assert_eq(as_string(unresolved[0]), "路线图规划")
}

///|
test "compute_workspace_json depth 2 includes two hop nodes" {
  let response = as_object(
    parse_json(compute_workspace_json(sample_workspace_request(",\"depth\":2"))),
  )
  let layout = as_object(field(response, "layout"))
  let nodes = as_array(field(layout, "nodes"))
  assert_eq(nodes.length(), 7)
  assert_true(has_node(nodes, "tags"))
  let tags_node = find_node(nodes, "tags")
  assert_eq(as_int(field(tags_node, "hop")), 2)
  let node_tags = as_array(field(tags_node, "tags"))
  assert_eq(node_tags.length(), 3)
  assert_eq(as_string(node_tags[0]), "标签")
  assert_eq(as_string(node_tags[1]), "工作/计划")
  assert_eq(as_string(node_tags[2]), "分类")
}

///|
test "compute_workspace_json depth 1 excludes two hop nodes" {
  let response = as_object(
    parse_json(compute_workspace_json(sample_workspace_request(",\"depth\":1"))),
  )
  let nodes = as_array(field(as_object(field(response, "layout")), "nodes"))
  assert_eq(nodes.length(), 6)
  assert_false(has_node(nodes, "tags"))
  assert_true(has_node(nodes, "markdown-syntax"))
  assert_true(has_node(nodes, "wikilinks"))
  assert_true(has_node(nodes, "local-graph"))
  assert_true(has_node(nodes, "moonbit"))
}

///|
test "compute_workspace_json defaults depth to one hop" {
  let response = as_object(
    parse_json(compute_workspace_json(sample_workspace_request(""))),
  )
  let nodes = as_array(field(as_object(field(response, "layout")), "nodes"))
  assert_eq(nodes.length(), 6)
  assert_false(has_node(nodes, "tags"))
}

///|
test "compute_workspace_json marks unresolved targets as ghost nodes" {
  let response = as_object(
    parse_json(compute_workspace_json(sample_workspace_request(",\"depth\":2"))),
  )
  let nodes = as_array(field(as_object(field(response, "layout")), "nodes"))
  let ghost = find_node(nodes, "ghost:路线图规划")
  assert_false(as_bool(field(ghost, "exists")))
  assert_eq(as_string(field(ghost, "title")), "路线图规划")
  assert_eq(as_int(field(ghost, "hop")), 1)
  assert_eq(as_array(field(ghost, "tags")).length(), 0)
}

///|
test "compute_workspace_json centers the active node at default canvas" {
  let response = as_object(
    parse_json(compute_workspace_json(sample_workspace_request(",\"depth\":1"))),
  )
  let layout = as_object(field(response, "layout"))
  assert_eq(as_string(field(layout, "center_id")), "guide")
  assert_true(as_number(field(layout, "width")) == 600.0)
  assert_true(as_number(field(layout, "height")) == 400.0)
  let center = find_node(as_array(field(layout, "nodes")), "guide")
  assert_eq(as_int(field(center, "hop")), 0)
  assert_true(as_number(field(center, "x")) == 300.0)
  assert_true(as_number(field(center, "y")) == 200.0)
  assert_true(as_number(field(center, "radius")) == 14.0)
}

///|
test "compute_workspace_json honors a custom canvas size" {
  let request = sample_workspace_request(
    ",\"depth\":1,\"width\":800,\"height\":500",
  )
  let layout = as_object(
    field(as_object(parse_json(compute_workspace_json(request))), "layout"),
  )
  assert_true(as_number(field(layout, "width")) == 800.0)
  assert_true(as_number(field(layout, "height")) == 500.0)
  let center = find_node(as_array(field(layout, "nodes")), "guide")
  assert_true(as_number(field(center, "x")) == 400.0)
  assert_true(as_number(field(center, "y")) == 250.0)
}

///|
test "compute_workspace_json non-positive canvas falls back to defaults" {
  let request = sample_workspace_request(",\"depth\":1,\"width\":-10,\"height\":0")
  let layout = as_object(
    field(as_object(parse_json(compute_workspace_json(request))), "layout"),
  )
  assert_true(as_number(field(layout, "width")) == 600.0)
  assert_true(as_number(field(layout, "height")) == 400.0)
}

///|
test "compute_workspace_json clamps depth above two" {
  let response = as_object(
    parse_json(compute_workspace_json(sample_workspace_request(",\"depth\":9"))),
  )
  let layout = as_object(field(response, "layout"))
  let nodes = as_array(field(layout, "nodes"))
  assert_eq(nodes.length(), 7)
}

///|
test "compute_workspace_json edges carry valid canvas coordinates" {
  let response = as_object(
    parse_json(compute_workspace_json(sample_workspace_request(",\"depth\":2"))),
  )
  let layout = as_object(field(response, "layout"))
  let nodes = as_array(field(layout, "nodes"))
  let edges = as_array(field(layout, "edges"))
  assert_true(edges.length() > 0)
  let mut i = 0
  while i < edges.length() {
    let edge = as_object(edges[i])
    assert_true(has_node(nodes, as_string(field(edge, "source"))))
    assert_true(has_node(nodes, as_string(field(edge, "target"))))
    assert_true(as_number(field(edge, "x1")) >= 0.0)
    assert_true(as_number(field(edge, "y1")) >= 0.0)
    assert_true(as_number(field(edge, "x2")) >= 0.0)
    assert_true(as_number(field(edge, "y2")) >= 0.0)
    i += 1
  }
}

///|
test "compute_workspace_json handles a single note vault" {
  let request = "{\"notes\":[{\"id\":\"solo\",\"title\":\"Solo\",\"content\":\"# Solo\"}],\"active_id\":\"solo\"}"
  let response = as_object(parse_json(compute_workspace_json(request)))
  assert_true(as_bool(field(response, "ok")))
  let render = as_object(field(response, "active_render"))
  assert_eq(as_string(field(render, "html")), "<h1>Solo</h1>")
  assert_eq(as_array(field(response, "backlinks")).length(), 0)
  assert_eq(as_array(field(response, "unresolved_links")).length(), 0)
  let layout = as_object(field(response, "layout"))
  let nodes = as_array(field(layout, "nodes"))
  assert_eq(nodes.length(), 1)
  assert_eq(as_array(field(layout, "edges")).length(), 0)
  let center = as_object(nodes[0])
  assert_eq(as_int(field(center, "hop")), 0)
}

// ---------------------------------------------------------------------------
// compute_workspace_json: malformed input never panics
// ---------------------------------------------------------------------------

///|
test "compute_workspace_json rejects invalid JSON" {
  let message = expect_failure("{not valid json")
  assert_true(message.contains("invalid JSON"))
}

///|
test "compute_workspace_json rejects a non-object root" {
  let message = expect_failure("[]")
  assert_true(message.contains("JSON object"))
}

///|
test "compute_workspace_json requires notes" {
  let message = expect_failure("{\"active_id\":\"a\"}")
  assert_true(message.contains("notes"))
}

///|
test "compute_workspace_json rejects notes of the wrong type" {
  let message = expect_failure("{\"notes\":\"oops\",\"active_id\":\"a\"}")
  assert_true(message.contains("notes"))
  assert_true(message.contains("array"))
}

///|
test "compute_workspace_json rejects a non-object note" {
  let message = expect_failure("{\"notes\":[42],\"active_id\":\"a\"}")
  assert_true(message.contains("must be an object"))
}

///|
test "compute_workspace_json rejects a note without content" {
  let request = "{\"notes\":[{\"id\":\"a\",\"title\":\"A\"}],\"active_id\":\"a\"}"
  let message = expect_failure(request)
  assert_true(message.contains("content"))
}

///|
test "compute_workspace_json rejects non-string note fields" {
  let request = "{\"notes\":[{\"id\":7,\"title\":\"A\",\"content\":\"\"}],\"active_id\":\"a\"}"
  let message = expect_failure(request)
  assert_true(message.contains("must be a string"))
}

///|
test "compute_workspace_json requires active_id" {
  let message = expect_failure("{\"notes\":[]}")
  assert_true(message.contains("active_id"))
}

///|
test "compute_workspace_json rejects a non-string active_id" {
  let message = expect_failure("{\"notes\":[],\"active_id\":7}")
  assert_true(message.contains("must be a string"))
}

///|
test "compute_workspace_json reports an unknown active_id" {
  let message = expect_failure("{\"notes\":[],\"active_id\":\"missing\"}")
  assert_true(message.contains("active note not found"))
}

///|
test "compute_workspace_json rejects a non-numeric depth" {
  let message = expect_failure(sample_workspace_request(",\"depth\":\"two\""))
  assert_true(message.contains("depth"))
  assert_true(message.contains("number"))
}

///|
test "compute_workspace_json rejects a non-numeric width" {
  let message = expect_failure(sample_workspace_request(",\"width\":true"))
  assert_true(message.contains("width"))
}

///|
test "compute_workspace_json rejects a non-numeric height" {
  let message = expect_failure(sample_workspace_request(",\"height\":null"))
  assert_true(message.contains("height"))
}

// ---------------------------------------------------------------------------
// Folder metadata round-trips
// ---------------------------------------------------------------------------

///|
test "sample notes are distributed across three folders" {
  let notes = as_array(parse_json(get_sample_notes_json()))
  let folders = StringBuilder()
  let mut i = 0
  while i < notes.length() {
    let note = as_object(notes[i])
    let folder = as_string(field(note, "folder"))
    assert_true(folder.length() > 0)
    folders.write_string(as_string(field(note, "id")))
    folders.write_string("=")
    folders.write_string(folder)
    folders.write_string(";")
    i += 1
  }
  let text = folders.to_string()
  assert_true(text.contains("guide=01-快速开始"))
  assert_true(text.contains("markdown-syntax=01-快速开始"))
  assert_true(text.contains("wikilinks=02-双链与标签"))
  assert_true(text.contains("tags=02-双链与标签"))
  assert_true(text.contains("local-graph=03-技术架构"))
  assert_true(text.contains("moonbit=03-技术架构"))
}

///|
test "compute_workspace_json attaches note folders to layout nodes" {
  let response = as_object(
    parse_json(compute_workspace_json(sample_workspace_request(",\"depth\":1"))),
  )
  let nodes = as_array(field(as_object(field(response, "layout")), "nodes"))
  let center = find_node(nodes, "guide")
  assert_eq(as_string(field(center, "folder")), "01-快速开始")
  let neighbor = find_node(nodes, "wikilinks")
  assert_eq(as_string(field(neighbor, "folder")), "02-双链与标签")
  let ghost = find_node(nodes, "ghost:路线图规划")
  assert_eq(as_string(field(ghost, "folder")), "")
}

///|
test "compute_workspace_json defaults a missing folder to the root" {
  let request = "{\"notes\":[{\"id\":\"solo\",\"title\":\"Solo\",\"content\":\"# Solo\"}],\"active_id\":\"solo\"}"
  let response = as_object(parse_json(compute_workspace_json(request)))
  let nodes = as_array(field(as_object(field(response, "layout")), "nodes"))
  let center = find_node(nodes, "solo")
  assert_eq(as_string(field(center, "folder")), "")
}

///|
test "compute_workspace_json backlinks carry their folder" {
  let response = as_object(
    parse_json(compute_workspace_json(sample_workspace_request(",\"depth\":2"))),
  )
  let backlinks = as_array(field(response, "backlinks"))
  let first = as_object(backlinks[0])
  assert_eq(as_string(field(first, "id")), "wikilinks")
  assert_eq(as_string(field(first, "folder")), "02-双链与标签")
}

///|
test "compute_workspace_json merges explicitly listed empty folders" {
  let request = "{\"notes\":[{\"id\":\"a\",\"title\":\"A\",\"content\":\"\",\"folder\":\"01-快速开始\"}],\"active_id\":\"a\",\"folders\":[\"空文件夹\",\"01-快速开始\",\"空文件夹\"]}"
  let response = as_object(parse_json(compute_workspace_json(request)))
  assert_eq(response.length(), 7)
  let folders = as_array(field(response, "folders"))
  assert_eq(folders.length(), 2)
  assert_eq(as_string(folders[0]), "01-快速开始")
  assert_eq(as_string(folders[1]), "空文件夹")
}

///|
test "compute_workspace_json accepts an empty folders array" {
  let request = "{\"notes\":[{\"id\":\"a\",\"title\":\"A\",\"content\":\"\",\"folder\":\"核心语法\"}],\"active_id\":\"a\",\"folders\":[]}"
  let response = as_object(parse_json(compute_workspace_json(request)))
  assert_eq(response.length(), 7)
  let folders = as_array(field(response, "folders"))
  assert_eq(folders.length(), 1)
  assert_eq(as_string(folders[0]), "核心语法")
}

///|
test "compute_workspace_json rejects a non-array folders field" {
  let message = expect_failure(
    "{\"notes\":[],\"active_id\":\"a\",\"folders\":\"oops\"}",
  )
  assert_true(message.contains("folders"))
  assert_true(message.contains("array"))
}

///|
test "compute_workspace_json rejects a non-string note folder" {
  let message = expect_failure(
    "{\"notes\":[{\"id\":\"a\",\"title\":\"A\",\"content\":\"\",\"folder\":7}],\"active_id\":\"a\"}",
  )
  assert_true(message.contains("folder"))
  assert_true(message.contains("must be a string"))
}

///|
test "compute_workspace_json rejects a non-string folders entry" {
  let message = expect_failure(
    "{\"notes\":[],\"active_id\":\"a\",\"folders\":[42]}",
  )
  assert_true(message.contains("folders"))
  assert_true(message.contains("must be a string"))
}

// ---------------------------------------------------------------------------
// query_notes_json: keyword search and tag filter
// ---------------------------------------------------------------------------

///|
fn query_vault_json() -> String {
  "[{\"id\":\"a\",\"title\":\"Alpha Note\",\"content\":\"body #work #plan\",\"folder\":\"Work\"},{\"id\":\"b\",\"title\":\"Beta\",\"content\":\"hello #work\",\"folder\":\"Home\"},{\"id\":\"c\",\"title\":\"Gamma\",\"content\":\"nothing #misc\",\"folder\":\"\"}]"
}

///|
fn query_request(query : String, tag : String) -> String {
  "{\"notes\":" +
  query_vault_json() +
  ",\"query\":\"" +
  query +
  "\",\"tag\":\"" +
  tag +
  "\"}"
}

///|
fn string_array_text(items : Array[Json]) -> String {
  let values : Array[String] = []
  let mut i = 0
  while i < items.length() {
    values.push(as_string(items[i]))
    i += 1
  }
  join_strings(values, ",")
}

///|
fn find_tag_count(items : Array[Json], tag : String) -> Int {
  let mut i = 0
  while i < items.length() {
    let entry = as_object(items[i])
    if as_string(field(entry, "tag")) == tag {
      return as_int(field(entry, "count"))
    }
    i += 1
  }
  abort("tag count not found: " + tag)
}

///|
test "query_notes_json returns matches and the whole vault tag list" {
  let response = as_object(
    parse_json(query_notes_json(query_request("alpha", ""))),
  )
  assert_true(as_bool(field(response, "ok")))
  assert_true(is_null(field(response, "error")))
  assert_eq(response.length(), 5)
  assert_eq(string_array_text(as_array(field(response, "matches"))), "a")
  assert_eq(
    string_array_text(as_array(field(response, "tags"))),
    "misc,plan,work",
  )
}

///|
test "query_notes_json reports per-tag counts" {
  let response = as_object(
    parse_json(query_notes_json(query_request("", ""))),
  )
  let counts = as_array(field(response, "tag_counts"))
  assert_eq(counts.length(), 3)
  assert_eq(find_tag_count(counts, "work"), 2)
  assert_eq(find_tag_count(counts, "plan"), 1)
  assert_eq(find_tag_count(counts, "misc"), 1)
}

///|
test "query_notes_json keeps every tag count while filtering" {
  let response = as_object(
    parse_json(query_notes_json(query_request("", "work"))),
  )
  let counts = as_array(field(response, "tag_counts"))
  assert_eq(counts.length(), 3)
  assert_eq(find_tag_count(counts, "work"), 2)
  assert_eq(find_tag_count(counts, "misc"), 1)
}

///|
test "query_notes_json finds notes by folder name" {
  let response = as_object(
    parse_json(query_notes_json(query_request("HOME", ""))),
  )
  assert_eq(string_array_text(as_array(field(response, "matches"))), "b")
}

///|
test "query_notes_json filters by tag" {
  let response = as_object(
    parse_json(query_notes_json(query_request("", "work"))),
  )
  assert_eq(
    string_array_text(as_array(field(response, "matches"))),
    "a,b",
  )
}

///|
test "query_notes_json tag filter accepts hash prefix and mixed case" {
  let response = as_object(
    parse_json(query_notes_json(query_request("", "#WORK"))),
  )
  assert_eq(
    string_array_text(as_array(field(response, "matches"))),
    "a,b",
  )
}

///|
test "query_notes_json intersects keyword and tag filters" {
  let response = as_object(
    parse_json(query_notes_json(query_request("beta", "work"))),
  )
  assert_eq(string_array_text(as_array(field(response, "matches"))), "b")
  let empty = as_object(
    parse_json(query_notes_json(query_request("alpha", "misc"))),
  )
  assert_eq(as_array(field(empty, "matches")).length(), 0)
}

///|
test "query_notes_json with no filters returns every note" {
  let response = as_object(
    parse_json(query_notes_json(query_request("", ""))),
  )
  assert_eq(
    string_array_text(as_array(field(response, "matches"))),
    "a,b,c",
  )
  assert_eq(as_array(field(response, "tags")).length(), 3)
}

///|
test "query_notes_json unknown tag keeps the tag list visible" {
  let response = as_object(
    parse_json(query_notes_json(query_request("", "missing"))),
  )
  assert_eq(as_array(field(response, "matches")).length(), 0)
  assert_eq(as_array(field(response, "tags")).length(), 3)
}

///|
test "query_notes_json rejects invalid JSON" {
  let message = expect_query_failure("{not valid json")
  assert_true(message.contains("invalid JSON"))
}

///|
test "query_notes_json requires notes" {
  let message = expect_query_failure("{\"query\":\"x\"}")
  assert_true(message.contains("notes"))
}

///|
test "query_notes_json rejects a non-string query" {
  let message = expect_query_failure("{\"notes\":[],\"query\":7}")
  assert_true(message.contains("query"))
  assert_true(message.contains("must be a string"))
}

///|
test "query_notes_json rejects a non-string tag" {
  let message = expect_query_failure("{\"notes\":[],\"tag\":7}")
  assert_true(message.contains("tag"))
  assert_true(message.contains("must be a string"))
}
