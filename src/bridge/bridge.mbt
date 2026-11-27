///|
/// Stage 1 smoke-test entry point, kept so the early bridge test and any
/// existing caller keep working after the JSON layer was added.
#export_name("bridge_status")
pub fn bridge_status() -> String {
  @parser.parser_status() +
  " | " +
  @graph.graph_status() +
  " | " +
  @layout.layout_status()
}

// ---------------------------------------------------------------------------
// JSON conversion helpers
// ---------------------------------------------------------------------------

///|
/// Copy a string array into a JSON array of strings.
fn strings_to_json(values : Array[String]) -> Json {
  let items : Array[Json] = []
  let mut i = 0
  while i < values.length() {
    items.push(Json::string(values[i]))
    i += 1
  }
  Json::array(items)
}

///|
/// Convert parsed wikilinks into the `links` array used by the web front end.
///
/// A link without an alias keeps an explicit `"alias": null` so the JavaScript
/// caller can read the field unconditionally.
fn links_to_json(links : Array[@parser.WikiLink]) -> Json {
  let items : Array[Json] = []
  let mut i = 0
  while i < links.length() {
    let link = links[i]
    let item : Json = match link.alias_text {
      Some(display) => { "target": link.target, "alias": display }
      None => { "target": link.target, "alias": @json.null }
    }
    items.push(item)
    i += 1
  }
  Json::array(items)
}

///|
/// Convert one Markdown parse result into the `active_render` object.
fn render_result_to_json(result : @parser.ParseResult) -> Json {
  {
    "html": result.html,
    "links": links_to_json(result.links),
    "tags": strings_to_json(result.tags),
  }
}

///|
/// Convert a backlink note into the compact `{id, title}` form the front end
/// needs for the backlink list.
fn note_summaries_to_json(notes : Array[@graph.Note]) -> Json {
  let items : Array[Json] = []
  let mut i = 0
  while i < notes.length() {
    let note = notes[i]
    let item : Json = { "id": note.id, "title": note.title }
    items.push(item)
    i += 1
  }
  Json::array(items)
}

///|
/// Convert positioned layout nodes into JSON, keeping every field the SVG
/// renderer needs.
fn positioned_nodes_to_json(nodes : Array[@layout.PositionedNode]) -> Json {
  let items : Array[Json] = []
  let mut i = 0
  while i < nodes.length() {
    let node = nodes[i]
    let item : Json = {
      "id": node.id,
      "title": node.title,
      "exists": node.exists,
      "hop": node.hop,
      "tags": strings_to_json(node.tags),
      "x": node.x,
      "y": node.y,
      "radius": node.radius,
    }
    items.push(item)
    i += 1
  }
  Json::array(items)
}

///|
/// Convert layout edges into JSON with both endpoints already in canvas
/// coordinates.
fn layout_edges_to_json(edges : Array[@layout.LayoutEdge]) -> Json {
  let items : Array[Json] = []
  let mut i = 0
  while i < edges.length() {
    let edge = edges[i]
    let item : Json = {
      "source": edge.source,
      "target": edge.target,
      "x1": edge.x1,
      "y1": edge.y1,
      "x2": edge.x2,
      "y2": edge.y2,
    }
    items.push(item)
    i += 1
  }
  Json::array(items)
}

///|
/// Convert the complete layout result into the `layout` object.
fn layout_to_json(layout : @layout.GraphLayout) -> Json {
  {
    "center_id": layout.center_id,
    "width": layout.width,
    "height": layout.height,
    "nodes": positioned_nodes_to_json(layout.nodes),
    "edges": layout_edges_to_json(layout.edges),
  }
}

///|
/// The error envelope returned when the request cannot be processed.
fn failure_response(message : String) -> Json {
  { "ok": false, "error": message }
}

// ---------------------------------------------------------------------------
// Request decoding
// ---------------------------------------------------------------------------

///|
/// Read a required string field from a request object.
fn required_string(
  obj : Map[String, Json],
  key : String,
) -> Result[String, String] {
  match obj.get(key) {
    Some(String(value)) => Ok(value)
    Some(_) => Err("field \"" + key + "\" must be a string")
    None => Err("missing required field \"" + key + "\"")
  }
}

///|
/// Read an optional numeric field, falling back to `default_value` when the
/// field is absent. A present but non-numeric value is an error rather than a
/// silent fallback, so the front end can surface a real problem.
fn optional_number(
  obj : Map[String, Json],
  key : String,
  default_value : Double,
) -> Result[Double, String] {
  match obj.get(key) {
    Some(Number(value, ..)) => Ok(value)
    Some(_) => Err("field \"" + key + "\" must be a number")
    None => Ok(default_value)
  }
}

///|
/// Decode the `notes` array into graph notes. Every note must be an object
/// with string `id`, `title` and `content` fields.
fn decode_notes(items : Array[Json]) -> Result[Array[@graph.Note], String] {
  let notes : Array[@graph.Note] = []
  let mut i = 0
  while i < items.length() {
    let path = "\"notes\"[" + i.to_string() + "]"
    let note_obj = match items[i] {
      Object(obj) => obj
      _ => return Err(path + " must be an object")
    }
    let id = match required_string(note_obj, "id") {
      Ok(value) => value
      Err(message) => return Err(path + " " + message)
    }
    let title = match required_string(note_obj, "title") {
      Ok(value) => value
      Err(message) => return Err(path + " " + message)
    }
    let content = match required_string(note_obj, "content") {
      Ok(value) => value
      Err(message) => return Err(path + " " + message)
    }
    notes.push(@graph.Note::new(id, title, content))
    i += 1
  }
  Ok(notes)
}

///|
/// Decode and execute one full workspace computation.
fn compute_workspace(request_json : String) -> Result[Json, String] {
  let root = @json.parse(request_json) catch {
    (error : @json.ParseError) =>
      return Err("invalid JSON: " + error.to_string())
  }
  let request = match root {
    Object(obj) => obj
    _ => return Err("request must be a JSON object")
  }
  let note_items = match request.get("notes") {
    Some(Array(items)) => items
    Some(_) => return Err("field \"notes\" must be an array")
    None => return Err("missing required field \"notes\"")
  }
  let active_id = match required_string(request, "active_id") {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let depth_value = match optional_number(request, "depth", 1.0) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let width = match optional_number(request, "width", 600.0) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let height = match optional_number(request, "height", 400.0) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let notes = match decode_notes(note_items) {
    Ok(value) => value
    Err(message) => return Err(message)
  }

  // Build a fresh, stateless store for this request.
  let store = @graph.NoteStore::new()
  let mut i = 0
  while i < notes.length() {
    store.upsert_note(notes[i])
    i += 1
  }

  let active_note = match store.get_note(active_id) {
    Some(note) => note
    None => return Err("active note not found: " + active_id)
  }

  let parsed = @parser.parse_markdown(active_note.content)
  let local_graph = store.get_local_graph(active_id, depth_value.to_int())
  let layout = @layout.compute_layout(local_graph, width, height)
  let backlinks = store.get_backlinks(active_id)
  let unresolved = store.get_unresolved_links()
  Ok({
    "ok": true,
    "error": @json.null,
    "active_render": render_result_to_json(parsed),
    "backlinks": note_summaries_to_json(backlinks),
    "unresolved_links": strings_to_json(unresolved),
    "layout": layout_to_json(layout),
  })
}

// ---------------------------------------------------------------------------
// Web-facing JSON API
// ---------------------------------------------------------------------------

///|
/// Render Markdown to HTML and return the wikilinks and tags as JSON:
/// `{"html":"...","links":[{"target":"...","alias":null}],"tags":["..."]}`.
///
/// The output is always a valid JSON document; the renderer itself escapes
/// HTML entities and the JSON encoder escapes string characters.
#export_name("render_markdown_json")
pub fn render_markdown_json(markdown : String) -> String {
  render_result_to_json(@parser.parse_markdown(markdown)).stringify()
}

///|
/// Stateless workspace computation for the web front end.
///
/// The request is
/// `{"notes":[...],"active_id":"...","depth":1,"width":600,"height":400}`;
/// `depth`, `width` and `height` are optional. On success the response carries
/// the rendered active note, its backlinks, every unresolved link title and the
/// positioned local graph. On any malformed input the response is
/// `{"ok":false,"error":"..."}` and no exception escapes.
#export_name("compute_workspace_json")
pub fn compute_workspace_json(request_json : String) -> String {
  match compute_workspace(request_json) {
    Ok(payload) => payload.stringify()
    Err(message) => failure_response(message).stringify()
  }
}

// ---------------------------------------------------------------------------
// Built-in sample vault
// ---------------------------------------------------------------------------

///|
fn sample_guide_content() -> String {
  let content =
    #|# MoonOrbit 使用指南
  #|
  #|欢迎使用 MoonOrbit —— 一个由 **MoonBit 1.0** 驱动的双链 Markdown 编辑器。
  #|
  #|## 快速开始
  #|
  #|1. 在左侧选择一篇笔记
  #|2. 在中间编辑 Markdown
  #|3. 在右侧查看局部图谱
  #|
  #|从 [[Markdown 语法]]、[[双链笔记]] 与 [[局部图谱]] 开始探索。
  #|也可以阅读 [[MoonBit 语言特性|MoonBit 1.0 特性]]。
  #|
  #|未来计划见 [[路线图规划]]。
  #|
  #|#指南 #moonorbit
  content
}

///|
fn sample_markdown_content() -> String {
  let content =
    #|# Markdown 语法
  #|
  #|支持 **粗体**、*斜体*、`行内代码` 与代码块。
  #|
  #|```moonbit
  #|let orbit = "MoonOrbit"
  #|```
  #|
  #|- 标题
  #|- 列表
  #|- 引用
  #|
  #|相关笔记：[[双链笔记]]、[[标签系统]]、[[路线图规划]]。
  #|
  #|#markdown #语法
  content
}

///|
fn sample_wikilinks_content() -> String {
  let content =
    #|# 双链笔记
  #|
  #|使用 `[[...]]` 创建链接，使用 `[[目标|别名]]` 显示不同文字。
  #|
  #|例如 [[MoonBit 语言特性|MoonBit 1.0 特性]] 与 [[标签系统|标签分类]]。
  #|返回 [[使用指南]]，也可以继续探索 [[局部图谱]]。
  #|
  #|#双链 #知识管理
  content
}

///|
fn sample_tags_content() -> String {
  let content =
    #|# 标签系统
  #|
  #|在任意位置输入 #标签 即可分类，支持层级写法 #工作/计划。
  #|
  #|标签会显示在对应笔记的图谱节点上。
  #|相关：[[双链笔记]]、[[局部图谱]]。
  #|
  #|#标签 #分类
  content
}

///|
fn sample_graph_content() -> String {
  let content =
    #|# 局部图谱
  #|
  #|局部图谱以当前笔记为中心，展示 1 跳与 2 跳邻居。
  #|
  #|- 1 跳：直接互相链接的笔记
  #|- 2 跳：邻居的邻居
  #|
  #|从 [[使用指南]] 出发，经过 [[双链笔记]] 就能看到 2 跳节点。
  #|未来计划见 [[路线图规划]]。
  #|
  #|#图谱 #可视化
  content
}

///|
fn sample_moonbit_content() -> String {
  let content =
    #|# MoonBit 1.0 特性
  #|
  #|MoonBit 1.0 提供：
  #|
  #|- 强类型与模式匹配
  #|- 零成本泛型
  #|- 可编译到 **JavaScript**、WebAssembly 与原生平台
  #|- 内置 JSON 与字符串处理
  #|
  #|返回 [[使用指南]]，了解 [[局部图谱]] 的实现。
  #|
  #|#moonbit #语言
  content
}

///|
fn sample_notes_json() -> Json {
  let notes : Array[Json] = [
    {
      "id": "guide",
      "title": "使用指南",
      "content": sample_guide_content(),
    },
    {
      "id": "markdown-syntax",
      "title": "Markdown 语法",
      "content": sample_markdown_content(),
    },
    {
      "id": "wikilinks",
      "title": "双链笔记",
      "content": sample_wikilinks_content(),
    },
    {
      "id": "tags",
      "title": "标签系统",
      "content": sample_tags_content(),
    },
    {
      "id": "local-graph",
      "title": "局部图谱",
      "content": sample_graph_content(),
    },
    {
      "id": "moonbit",
      "title": "MoonBit 语言特性",
      "content": sample_moonbit_content(),
    },
  ]
  Json::array(notes)
}

///|
/// Return six interlinked sample notes as a JSON array
/// `[{"id":"...","title":"...","content":"..."}, ...]`.
///
/// The vault is built for the first page load: `使用指南` is linked from three
/// notes, `双链笔记` bridges the second hop, aliases appear in several notes and
/// `[[路线图规划]]` is deliberately never created so unresolved links and a
/// ghost graph node are visible immediately.
#export_name("get_sample_notes_json")
pub fn get_sample_notes_json() -> String {
  sample_notes_json().stringify()
}
