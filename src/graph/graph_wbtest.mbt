///|
test "graph smoke" {
  assert_eq(graph_status(), "graph: ready")
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

///|
fn make_note(id : String, title : String, content : String) -> Note {
  Note::new(id, title, content)
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
fn note_ids_text(notes : Array[Note]) -> String {
  let ids : Array[String] = []
  let mut i = 0
  while i < notes.length() {
    ids.push(notes[i].id)
    i += 1
  }
  join_strings(ids, ",")
}

///|
/// Render nodes as `id@hop+` (created) or `id@hop-` (ghost).
fn nodes_text(graph : LocalGraph) -> String {
  let parts : Array[String] = []
  let mut i = 0
  while i < graph.nodes.length() {
    let node = graph.nodes[i]
    let marker = if node.exists {
      "+"
    } else {
      "-"
    }
    parts.push(node.id + "@" + node.hop.to_string() + marker)
    i += 1
  }
  join_strings(parts, ",")
}

///|
fn edges_text(graph : LocalGraph) -> String {
  let parts : Array[String] = []
  let mut i = 0
  while i < graph.edges.length() {
    let edge = graph.edges[i]
    parts.push(edge.source + "->" + edge.target)
    i += 1
  }
  join_strings(parts, ",")
}

// ---------------------------------------------------------------------------
// Store basics
// ---------------------------------------------------------------------------

///|
test "new store is empty" {
  let store = NoteStore::new()
  assert_eq(store.list_notes().length(), 0)
  assert_eq(store.get_unresolved_links().length(), 0)
}

///|
test "upsert stores note and get_note returns it" {
  let store = NoteStore::new()
  store.upsert_note(make_note("a", "Alpha", "hello"))
  match store.get_note("a") {
    Some(note) => {
      assert_eq(note.id, "a")
      assert_eq(note.title, "Alpha")
      assert_eq(note.content, "hello")
    }
    None => assert_true(false)
  }
}

///|
test "upsert with same id replaces note without duplicating" {
  let store = NoteStore::new()
  store.upsert_note(make_note("a", "Old", "old body"))
  store.upsert_note(make_note("a", "New", "[[Beta]]"))
  assert_eq(store.list_notes().length(), 1)
  match store.get_note("a") {
    Some(note) => assert_eq(note.title, "New")
    None => assert_true(false)
  }
  assert_eq(
    join_strings(store.get_outgoing_links("a"), ","),
    "ghost:Beta",
  )
}

///|
test "list_notes keeps insertion order" {
  let store = NoteStore::new()
  store.upsert_note(make_note("n1", "One", ""))
  store.upsert_note(make_note("n2", "Two", ""))
  assert_eq(note_ids_text(store.list_notes()), "n1,n2")
}

///|
test "get_note returns none for unknown id" {
  let store = NoteStore::new()
  assert_true(store.get_note("missing") is None)
}

///|
test "remove_note reports success and unknown ids" {
  let store = NoteStore::new()
  store.upsert_note(make_note("a", "Alpha", ""))
  assert_true(store.remove_note("a"))
  assert_false(store.remove_note("a"))
  assert_true(store.get_note("a") is None)
}

// ---------------------------------------------------------------------------
// Outgoing links and unresolved links
// ---------------------------------------------------------------------------

///|
test "outgoing links resolve titles to note ids" {
  let store = NoteStore::new()
  store.upsert_note(make_note("b", "Beta", ""))
  store.upsert_note(make_note("a", "Alpha", "[[Beta]] and [[Beta|bee]]"))
  assert_eq(join_strings(store.get_outgoing_links("a"), ","), "b")
}

///|
test "outgoing links for unknown note are empty" {
  let store = NoteStore::new()
  store.upsert_note(make_note("a", "Alpha", "[[Beta]]"))
  assert_eq(store.get_outgoing_links("missing").length(), 0)
}

///|
test "unresolved links are deduplicated and sorted" {
  let store = NoteStore::new()
  store.upsert_note(
    make_note("a", "Alpha", "[[Zed]] [[Alpha Ghost]] [[Zed]]"),
  )
  assert_eq(
    join_strings(store.get_unresolved_links(), ","),
    "Alpha Ghost,Zed",
  )
}

///|
test "unresolved ghost link disappears once target is created" {
  let store = NoteStore::new()
  store.upsert_note(make_note("a", "Alpha", "[[Future]]"))
  assert_eq(
    join_strings(store.get_outgoing_links("a"), ","),
    "ghost:Future",
  )
  assert_eq(join_strings(store.get_unresolved_links(), ","), "Future")
  store.upsert_note(make_note("f", "Future", ""))
  assert_eq(join_strings(store.get_outgoing_links("a"), ","), "f")
  assert_eq(store.get_unresolved_links().length(), 0)
  assert_eq(note_ids_text(store.get_backlinks("f")), "a")
}

// ---------------------------------------------------------------------------
// Real-time index updates
// ---------------------------------------------------------------------------

///|
test "updating content drops stale links" {
  let store = NoteStore::new()
  store.upsert_note(make_note("b", "Beta", ""))
  store.upsert_note(make_note("a", "Alpha", "[[Beta]]"))
  assert_eq(note_ids_text(store.get_backlinks("b")), "a")
  store.upsert_note(make_note("a", "Alpha", "no links here"))
  assert_eq(store.get_backlinks("b").length(), 0)
  assert_eq(store.get_outgoing_links("a").length(), 0)
}

///|
test "updating content adds new links" {
  let store = NoteStore::new()
  store.upsert_note(make_note("a", "Alpha", "plain text"))
  assert_eq(store.get_unresolved_links().length(), 0)
  store.upsert_note(make_note("a", "Alpha", "[[Charlie]]"))
  assert_eq(join_strings(store.get_unresolved_links(), ","), "Charlie")
}

///|
test "removing a note turns its backlinks into ghosts" {
  let store = NoteStore::new()
  store.upsert_note(make_note("b", "Beta", ""))
  store.upsert_note(make_note("a", "Alpha", "[[Beta]]"))
  assert_true(store.remove_note("b"))
  assert_eq(join_strings(store.get_unresolved_links(), ","), "Beta")
  assert_eq(
    join_strings(store.get_outgoing_links("a"), ","),
    "ghost:Beta",
  )
}

// ---------------------------------------------------------------------------
// Backlinks
// ---------------------------------------------------------------------------

///|
test "backlinks list every referencing note in insertion order" {
  let store = NoteStore::new()
  store.upsert_note(make_note("t", "Target", ""))
  store.upsert_note(make_note("a", "Alpha", "[[Target]]"))
  store.upsert_note(make_note("c", "Charlie", "see [[Target|it]]"))
  assert_eq(note_ids_text(store.get_backlinks("t")), "a,c")
}

///|
test "self link counts as a backlink" {
  let store = NoteStore::new()
  store.upsert_note(make_note("a", "Alpha", "[[Alpha]]"))
  assert_eq(note_ids_text(store.get_backlinks("a")), "a")
  assert_eq(join_strings(store.get_outgoing_links("a"), ","), "a")
}

// ---------------------------------------------------------------------------
// Local graphs
// ---------------------------------------------------------------------------

///|
test "isolated note graph contains only the center" {
  let store = NoteStore::new()
  store.upsert_note(make_note("a", "Alpha", "just text"))
  let graph = store.get_local_graph("a", 1)
  assert_eq(graph.center_id, "a")
  assert_eq(graph.depth, 1)
  assert_eq(nodes_text(graph), "a@0+")
  assert_eq(edges_text(graph), "")
}

///|
test "depth one excludes two hop nodes" {
  let store = NoteStore::new()
  store.upsert_note(make_note("a", "A", "[[B]]"))
  store.upsert_note(make_note("b", "B", "[[C]]"))
  store.upsert_note(make_note("c", "C", ""))
  let graph = store.get_local_graph("a", 1)
  assert_eq(nodes_text(graph), "a@0+,b@1+")
  assert_eq(edges_text(graph), "a->b")
}

///|
test "depth two includes two hop nodes" {
  let store = NoteStore::new()
  store.upsert_note(make_note("a", "A", "[[B]]"))
  store.upsert_note(make_note("b", "B", "[[C]]"))
  store.upsert_note(make_note("c", "C", ""))
  let graph = store.get_local_graph("a", 2)
  assert_eq(nodes_text(graph), "a@0+,b@1+,c@2+")
  assert_eq(edges_text(graph), "a->b,b->c")
}

///|
test "incoming references are one hop neighbors" {
  let store = NoteStore::new()
  store.upsert_note(make_note("a", "A", ""))
  store.upsert_note(make_note("b", "B", "[[A]]"))
  store.upsert_note(make_note("c", "C", "[[A]]"))
  let graph = store.get_local_graph("a", 1)
  assert_eq(nodes_text(graph), "a@0+,b@1+,c@1+")
  assert_eq(edges_text(graph), "b->a,c->a")
}

///|
test "middle of a chain sees both directions at one hop" {
  let store = NoteStore::new()
  store.upsert_note(make_note("a", "A", "[[B]]"))
  store.upsert_note(make_note("b", "B", "[[C]]"))
  store.upsert_note(make_note("c", "C", ""))
  let graph = store.get_local_graph("b", 1)
  assert_eq(nodes_text(graph), "b@0+,a@1+,c@1+")
  assert_eq(edges_text(graph), "a->b,b->c")
}

///|
test "mutual links produce two directed edges" {
  let store = NoteStore::new()
  store.upsert_note(make_note("a", "A", "[[B]]"))
  store.upsert_note(make_note("b", "B", "[[A]]"))
  let graph = store.get_local_graph("a", 1)
  assert_eq(nodes_text(graph), "a@0+,b@1+")
  assert_eq(edges_text(graph), "a->b,b->a")
}

///|
test "cycle terminates and hops follow shortest distance" {
  let store = NoteStore::new()
  store.upsert_note(make_note("a", "A", "[[B]]"))
  store.upsert_note(make_note("b", "B", "[[C]]"))
  store.upsert_note(make_note("c", "C", "[[D]]"))
  store.upsert_note(make_note("d", "D", "[[A]]"))
  let graph = store.get_local_graph("a", 2)
  assert_eq(nodes_text(graph), "a@0+,b@1+,d@1+,c@2+")
  assert_eq(edges_text(graph), "a->b,b->c,c->d,d->a")
}

///|
test "depth is clamped to one through two" {
  let store = NoteStore::new()
  store.upsert_note(make_note("a", "A", "[[B]]"))
  store.upsert_note(make_note("b", "B", "[[C]]"))
  store.upsert_note(make_note("c", "C", ""))
  let shallow = store.get_local_graph("a", 0)
  assert_eq(shallow.depth, 1)
  assert_eq(nodes_text(shallow), "a@0+,b@1+")
  let deep = store.get_local_graph("a", 9)
  assert_eq(deep.depth, 2)
  assert_eq(nodes_text(deep), "a@0+,b@1+,c@2+")
}

///|
test "unknown center yields empty graph with clamped depth" {
  let store = NoteStore::new()
  store.upsert_note(make_note("a", "A", ""))
  let graph = store.get_local_graph("missing", 5)
  assert_eq(graph.center_id, "missing")
  assert_eq(graph.depth, 2)
  assert_eq(graph.nodes.length(), 0)
  assert_eq(graph.edges.length(), 0)
}

///|
test "nodes are sorted by hop then id" {
  let store = NoteStore::new()
  store.upsert_note(make_note("a", "A", ""))
  store.upsert_note(make_note("b", "B", ""))
  store.upsert_note(make_note("c", "C", "[[B]] [[A]]"))
  let graph = store.get_local_graph("c", 1)
  assert_eq(nodes_text(graph), "c@0+,a@1+,b@1+")
}

///|
test "ghost nodes appear with exists false" {
  let store = NoteStore::new()
  store.upsert_note(make_note("a", "A", "[[Ghost]]"))
  let graph = store.get_local_graph("a", 1)
  assert_eq(nodes_text(graph), "a@0+,ghost:Ghost@1-")
  assert_eq(graph.nodes[1].title, "Ghost")
  assert_false(graph.nodes[1].exists)
  assert_eq(edges_text(graph), "a->ghost:Ghost")
}

///|
test "edges to nodes outside the subgraph are excluded" {
  let store = NoteStore::new()
  store.upsert_note(make_note("a", "A", "[[B]]"))
  store.upsert_note(make_note("b", "B", ""))
  store.upsert_note(make_note("c", "C", "[[B]]"))
  let graph = store.get_local_graph("a", 1)
  assert_eq(nodes_text(graph), "a@0+,b@1+")
  assert_eq(edges_text(graph), "a->b")
}

// ---------------------------------------------------------------------------
// Reserved prefix and ghost identity
// ---------------------------------------------------------------------------

///|
test "real note ids may use the reserved prefix without becoming unresolved" {
  let store = NoteStore::new()
  store.upsert_note(make_note("ghost:Notes", "Notes", ""))
  store.upsert_note(make_note("a", "A", "[[Notes]]"))
  assert_eq(store.get_unresolved_links().length(), 0)
  assert_eq(
    join_strings(store.get_outgoing_links("a"), ","),
    "ghost:Notes",
  )
  assert_eq(note_ids_text(store.get_backlinks("ghost:Notes")), "a")
  let graph = store.get_local_graph("a", 1)
  assert_eq(nodes_text(graph), "a@0+,ghost:Notes@1+")
  assert_eq(graph.nodes[1].title, "Notes")
  assert_true(graph.nodes[1].exists)
}

///|
test "ghost ids avoid colliding with real note ids" {
  let store = NoteStore::new()
  store.upsert_note(make_note("ghost:G", "Real", ""))
  store.upsert_note(make_note("a", "A", "[[G]]"))
  assert_eq(join_strings(store.get_unresolved_links(), ","), "G")
  assert_eq(
    join_strings(store.get_outgoing_links("a"), ","),
    "ghost:G:2",
  )
  let graph = store.get_local_graph("a", 1)
  assert_eq(nodes_text(graph), "a@0+,ghost:G:2@1-")
  assert_eq(graph.nodes[1].title, "G")
  assert_false(graph.nodes[1].exists)
  assert_eq(edges_text(graph), "a->ghost:G:2")
}

///|
test "shared ghost title keeps one ghost node and supports ghost centers" {
  let store = NoteStore::new()
  store.upsert_note(make_note("a", "A", "[[X]]"))
  store.upsert_note(make_note("b", "B", "[[X]]"))
  assert_eq(join_strings(store.get_outgoing_links("a"), ","), "ghost:X")
  assert_eq(join_strings(store.get_outgoing_links("b"), ","), "ghost:X")
  assert_eq(join_strings(store.get_unresolved_links(), ","), "X")
  let graph = store.get_local_graph("ghost:X", 1)
  assert_eq(nodes_text(graph), "ghost:X@0-,a@1+,b@1+")
  assert_eq(edges_text(graph), "a->ghost:X,b->ghost:X")
}

// ---------------------------------------------------------------------------
// Tags
// ---------------------------------------------------------------------------

///|
test "tags are attached to graph nodes" {
  let store = NoteStore::new()
  store.upsert_note(make_note("a", "A", "#work [[B]]"))
  store.upsert_note(make_note("b", "B", ""))
  let graph = store.get_local_graph("a", 1)
  assert_eq(graph.nodes[0].id, "a")
  assert_eq(join_strings(graph.nodes[0].tags, ","), "work")
  assert_eq(graph.nodes[1].id, "b")
  assert_eq(graph.nodes[1].tags.length(), 0)
}

///|
test "tag updates are reflected in the local graph" {
  let store = NoteStore::new()
  store.upsert_note(make_note("a", "A", "#old"))
  assert_eq(
    join_strings(store.get_local_graph("a", 1).nodes[0].tags, ","),
    "old",
  )
  store.upsert_note(make_note("a", "A", "#new"))
  assert_eq(
    join_strings(store.get_local_graph("a", 1).nodes[0].tags, ","),
    "new",
  )
}

// ---------------------------------------------------------------------------
// Folder metadata
// ---------------------------------------------------------------------------

///|
test "Note::new defaults folder to the vault root" {
  let note = Note::new("a", "Alpha", "body")
  assert_eq(note.folder, "")
}

///|
test "Note::with_folder stores the folder verbatim" {
  let note = Note::with_folder("a", "Alpha", "body", "01-快速开始")
  assert_eq(note.id, "a")
  assert_eq(note.title, "Alpha")
  assert_eq(note.content, "body")
  assert_eq(note.folder, "01-快速开始")
}

///|
test "upsert keeps folder metadata readable through get_note" {
  let store = NoteStore::new()
  store.upsert_note(Note::with_folder("a", "Alpha", "body", "02-双链与标签"))
  match store.get_note("a") {
    Some(note) => assert_eq(note.folder, "02-双链与标签")
    None => assert_true(false)
  }
  assert_eq(store.list_notes()[0].folder, "02-双链与标签")
}

///|
test "upsert with the same id updates the folder" {
  let store = NoteStore::new()
  store.upsert_note(Note::with_folder("a", "Alpha", "body", "old"))
  store.upsert_note(Note::with_folder("a", "Alpha", "body", "new"))
  assert_eq(store.list_notes().length(), 1)
  assert_eq(store.list_notes()[0].folder, "new")
}

///|
test "set_note_folder moves a note and preserves its content" {
  let store = NoteStore::new()
  store.upsert_note(Note::with_folder("a", "Alpha", "[[B]]", "old"))
  assert_true(store.set_note_folder("a", "new"))
  match store.get_note("a") {
    Some(note) => {
      assert_eq(note.folder, "new")
      assert_eq(note.title, "Alpha")
      assert_eq(note.content, "[[B]]")
    }
    None => assert_true(false)
  }
  assert_false(store.set_note_folder("missing", "new"))
}

///|
test "list_folders deduplicates, sorts and excludes the root" {
  let store = NoteStore::new()
  store.upsert_note(Note::new("root", "Root", ""))
  store.upsert_note(Note::with_folder("b", "Beta", "", "02-双链与标签"))
  store.upsert_note(Note::with_folder("a", "Alpha", "", "01-快速开始"))
  store.upsert_note(Note::with_folder("c", "Gamma", "", "02-双链与标签"))
  assert_eq(
    join_strings(store.list_folders(), ","),
    "01-快速开始,02-双链与标签",
  )
}

///|
test "notes_in_folder filters root and named folders" {
  let store = NoteStore::new()
  store.upsert_note(Note::new("root", "Root", ""))
  store.upsert_note(Note::with_folder("a", "Alpha", "", "01-快速开始"))
  store.upsert_note(Note::with_folder("b", "Beta", "", "02-双链与标签"))
  store.upsert_note(Note::with_folder("c", "Gamma", "", "01-快速开始"))
  assert_eq(note_ids_text(store.notes_in_folder("")), "root")
  assert_eq(note_ids_text(store.notes_in_folder("01-快速开始")), "a,c")
  assert_eq(store.notes_in_folder("missing").length(), 0)
}

///|
test "removing the last note in a folder drops the folder" {
  let store = NoteStore::new()
  store.upsert_note(Note::with_folder("a", "Alpha", "", "solo"))
  assert_eq(join_strings(store.list_folders(), ","), "solo")
  assert_true(store.remove_note("a"))
  assert_eq(store.list_folders().length(), 0)
}

///|
test "moving a note between folders leaves links untouched" {
  let store = NoteStore::new()
  store.upsert_note(Note::with_folder("b", "Beta", "", "old"))
  store.upsert_note(Note::with_folder("a", "Alpha", "[[Beta]]", "old"))
  assert_eq(note_ids_text(store.get_backlinks("b")), "a")
  assert_true(store.set_note_folder("a", "new"))
  match store.get_note("a") {
    Some(note) => assert_eq(note.folder, "new")
    None => assert_true(false)
  }
  assert_eq(note_ids_text(store.get_backlinks("b")), "a")
  assert_eq(join_strings(store.get_outgoing_links("a"), ","), "b")
}

// ---------------------------------------------------------------------------
// Full-text search and tag filters
// ---------------------------------------------------------------------------

///|
fn make_search_store() -> NoteStore {
  let store = NoteStore::new()
  store.upsert_note(
    Note::with_folder("a", "Alpha Guide", "hello world", "Work"),
  )
  store.upsert_note(
    Note::with_folder("b", "Beta Notes", "MoonBit rocks", "Home"),
  )
  store.upsert_note(Note::with_folder("c", "Gamma", "nothing here", ""))
  store
}

///|
fn make_tag_store() -> NoteStore {
  let store = NoteStore::new()
  store.upsert_note(Note::new("a", "A", "#work #plan"))
  store.upsert_note(Note::new("b", "B", "#WORK"))
  store.upsert_note(Note::new("c", "C", "#misc"))
  store
}

///|
test "search_notes matches titles case-insensitively" {
  let store = make_search_store()
  assert_eq(note_ids_text(store.search_notes("ALPHA")), "a")
  assert_eq(note_ids_text(store.search_notes("alpha")), "a")
}

///|
test "search_notes matches content case-insensitively" {
  let store = make_search_store()
  assert_eq(note_ids_text(store.search_notes("moonbit ROCKS")), "b")
}

///|
test "search_notes matches folder names case-insensitively" {
  let store = make_search_store()
  assert_eq(note_ids_text(store.search_notes("work")), "a")
}

///|
test "search_notes empty query returns every note in insertion order" {
  let store = make_search_store()
  assert_eq(note_ids_text(store.search_notes("")), "a,b,c")
  assert_eq(note_ids_text(store.search_notes("   ")), "a,b,c")
}

///|
test "search_notes trims surrounding whitespace" {
  let store = make_search_store()
  assert_eq(note_ids_text(store.search_notes("  beta  ")), "b")
}

///|
test "search_notes returns nothing for an unknown term" {
  let store = make_search_store()
  assert_eq(store.search_notes("does-not-exist").length(), 0)
}

///|
test "get_notes_by_tag returns only matching notes" {
  let store = make_tag_store()
  assert_eq(note_ids_text(store.get_notes_by_tag("plan")), "a")
  assert_eq(note_ids_text(store.get_notes_by_tag("work")), "a,b")
}

///|
test "get_notes_by_tag accepts hash prefix and mixed case" {
  let store = make_tag_store()
  assert_eq(note_ids_text(store.get_notes_by_tag("#WORK")), "a,b")
  assert_eq(note_ids_text(store.get_notes_by_tag("  #work  ")), "a,b")
}

///|
test "get_notes_by_tag returns empty for blank or unknown tags" {
  let store = make_tag_store()
  assert_eq(store.get_notes_by_tag("").length(), 0)
  assert_eq(store.get_notes_by_tag("#").length(), 0)
  assert_eq(store.get_notes_by_tag("missing").length(), 0)
}

///|
test "list_tags deduplicates and sorts every tag" {
  let store = make_tag_store()
  assert_eq(join_strings(store.list_tags(), ","), "WORK,misc,plan,work")
  assert_eq(NoteStore::new().list_tags().length(), 0)
}
