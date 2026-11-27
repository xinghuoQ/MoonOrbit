///|
/// Placeholder status kept for the Stage 1 bridge smoke test.
pub fn graph_status() -> String {
  "graph: ready"
}

// ---------------------------------------------------------------------------
// Public data structures
// ---------------------------------------------------------------------------

///|
/// A note stored in the vault.
///
/// `id` is the stable identity used by every graph query, `title` is the
/// human-readable name that `[[wikilinks]]` resolve against, `content` is the
/// raw Markdown source, and `folder` is the workspace folder the note lives
/// in. An empty `folder` means the vault root.
pub struct Note {
  id : String
  title : String
  content : String
  folder : String
}

///|
/// Convenience constructor for a note at the vault root.
///
/// Kept for backward compatibility with every stage 1–6 caller: the folder
/// defaults to the empty string, which represents the root of the workspace.
pub fn Note::new(id : String, title : String, content : String) -> Note {
  { id: id, title: title, content: content, folder: "" }
}

///|
/// Constructor for a note inside `folder`.
///
/// Pass an empty string for `folder` to place the note at the vault root.
/// Folder names are stored verbatim (for example `"01-快速开始"`); the graph
/// engine never interprets them as nested paths.
pub fn Note::with_folder(
  id : String,
  title : String,
  content : String,
  folder : String,
) -> Note {
  { id: id, title: title, content: content, folder: folder }
}

///|
/// One node of a local graph.
///
/// `exists` is `true` for notes that have been created and `false` for
/// "ghost" nodes that are only referenced by `[[wikilinks]]`. `hop` is the
/// shortest undirected distance from the center node (center `0`, direct
/// neighbors `1`, second ring `2`).
pub struct GraphNode {
  id : String
  title : String
  exists : Bool
  hop : Int
  tags : Array[String]
}

///|
/// A directed reference edge: `source` contains a `[[wikilink]]` to `target`.
pub struct GraphEdge {
  source : String
  target : String
}

///|
/// The extracted subgraph around a center note.
pub struct LocalGraph {
  center_id : String
  depth : Int
  nodes : Array[GraphNode]
  edges : Array[GraphEdge]
}

// ---------------------------------------------------------------------------
// Internal index records
// ---------------------------------------------------------------------------

///|
/// A resolved reference extracted from a note body.
///
/// `target` is either a real note id or a synthetic ghost id, while `label`
/// keeps the original title text written inside `[[...]]`. `is_ghost` records
/// ghostness explicitly so a real note id that happens to start with the
/// reserved prefix is never misclassified.
priv struct LinkRecord {
  source : String
  target : String
  label : String
  is_ghost : Bool
}

///|
/// Tags extracted from one note, cached with the note id.
priv struct TagRecord {
  id : String
  tags : Array[String]
}

///|
/// Bookkeeping used while rebuilding the index: one ghost id per unresolved
/// title, chosen so it collides with neither a real note id nor another ghost
/// id.
priv struct GhostAssignment {
  title : String
  id : String
}

// ---------------------------------------------------------------------------
// Note store
// ---------------------------------------------------------------------------

///|
/// The note vault: owns every note plus the live outgoing-link and tag
/// indexes. Every mutation rebuilds the index so queries never observe stale
/// links or tags.
pub struct NoteStore {
  priv notes : Array[Note]
  priv mut links : Array[LinkRecord]
  priv mut tags : Array[TagRecord]
}

///|
/// Create an empty note store.
pub fn NoteStore::new() -> NoteStore {
  { notes: [], links: [], tags: [] }
}

///|
/// Insert a note, or replace the note that already has the same id.
///
/// The whole link index is rebuilt afterwards, so links that disappeared
/// from the new content stop resolving and newly added links start
/// resolving immediately.
pub fn NoteStore::upsert_note(self : NoteStore, note : Note) -> Unit {
  let index = find_note_index(self.notes, note.id)
  if index >= 0 {
    self.notes[index] = note
  } else {
    self.notes.push(note)
  }
  rebuild_index(self)
}

///|
/// Remove the note with `id`. Returns `true` when a note was removed and
/// `false` when the id was unknown. Removing a note turns references to it
/// back into unresolved ghost links.
pub fn NoteStore::remove_note(self : NoteStore, id : String) -> Bool {
  let index = find_note_index(self.notes, id)
  if index < 0 {
    return false
  }
  let _ = self.notes.remove(index)
  rebuild_index(self)
  true
}

///|
/// Look up a note by id, returning `None` when it does not exist.
pub fn NoteStore::get_note(self : NoteStore, id : String) -> Note? {
  find_note_by_id(self.notes, id)
}

///|
/// Return every note in insertion order. The returned array is a snapshot;
/// mutating it does not affect the store.
pub fn NoteStore::list_notes(self : NoteStore) -> Array[Note] {
  let result : Array[Note] = []
  let mut i = 0
  while i < self.notes.length() {
    result.push(self.notes[i])
    i += 1
  }
  result
}

///|
/// Every distinct non-root folder name used by a note, sorted by code unit.
///
/// The vault root (`""`) is deliberately excluded: callers render it as a
/// dedicated root row instead of a named folder.
pub fn NoteStore::list_folders(self : NoteStore) -> Array[String] {
  let folders : Array[String] = []
  let mut i = 0
  while i < self.notes.length() {
    let folder = self.notes[i].folder
    if folder != "" && !contains_string(folders, folder) {
      folders.push(folder)
    }
    i += 1
  }
  sort_strings(folders)
  folders
}

///|
/// Notes stored directly inside `folder`, in store insertion order.
///
/// Pass `""` to list the notes at the vault root.
pub fn NoteStore::notes_in_folder(
  self : NoteStore,
  folder : String,
) -> Array[Note] {
  let result : Array[Note] = []
  let mut i = 0
  while i < self.notes.length() {
    let note = self.notes[i]
    if note.folder == folder {
      result.push(note)
    }
    i += 1
  }
  result
}

///|
/// Move the note with `id` into `folder`.
///
/// Returns `false` when the id is unknown. The note's id, title and content
/// are preserved, and the link/tag indexes stay valid because folders never
/// participate in wikilink resolution.
pub fn NoteStore::set_note_folder(
  self : NoteStore,
  id : String,
  folder : String,
) -> Bool {
  let index = find_note_index(self.notes, id)
  if index < 0 {
    return false
  }
  let note = self.notes[index]
  self.notes[index] = Note::with_folder(
    note.id,
    note.title,
    note.content,
    folder,
  )
  true
}

///|
/// Target node ids referenced by the note `id`, in document order and
/// deduplicated. Ghost targets use the `ghost:<title>` id form, with a
/// numeric suffix when that id is already taken by a real note. Unknown note
/// ids yield an empty array.
pub fn NoteStore::get_outgoing_links(
  self : NoteStore,
  id : String,
) -> Array[String] {
  let targets : Array[String] = []
  let mut i = 0
  while i < self.links.length() {
    let link = self.links[i]
    if link.source == id && !contains_string(targets, link.target) {
      targets.push(link.target)
    }
    i += 1
  }
  targets
}

///|
/// Notes that contain a `[[wikilink]]` pointing at `id`, in store insertion
/// order. A note that links to itself is included.
pub fn NoteStore::get_backlinks(
  self : NoteStore,
  id : String,
) -> Array[Note] {
  let result : Array[Note] = []
  let mut i = 0
  while i < self.notes.length() {
    let current = self.notes[i]
    let mut j = 0
    let mut linked = false
    while j < self.links.length() && !linked {
      let link = self.links[j]
      if link.source == current.id && link.target == id {
        linked = true
      }
      j += 1
    }
    if linked {
      result.push(current)
    }
    i += 1
  }
  result
}

///|
/// Titles that are referenced by at least one `[[wikilink]]` but have no
/// created note yet. Unique and sorted by code unit for deterministic output.
pub fn NoteStore::get_unresolved_links(self : NoteStore) -> Array[String] {
  let titles : Array[String] = []
  let mut i = 0
  while i < self.links.length() {
    let link = self.links[i]
    if link.is_ghost && !contains_string(titles, link.label) {
      titles.push(link.label)
    }
    i += 1
  }
  sort_strings(titles)
  titles
}

///|
/// Extract the local graph around `center_id` using an undirected BFS.
///
/// Outgoing and incoming references both count as adjacency for traversal,
/// but every emitted edge keeps its original direction. `depth` is clamped to
/// the range `1..2`. Nodes are sorted by `(hop, id)` and edges by
/// `(source, target)` so the output is stable and testable.
///
/// An unknown `center_id` (neither a created note nor a referenced ghost
/// node) produces an empty graph with the requested center and clamped depth.
pub fn NoteStore::get_local_graph(
  self : NoteStore,
  center_id : String,
  depth : Int,
) -> LocalGraph {
  let effective_depth : Int = if depth < 1 {
    1
  } else if depth > 2 {
    2
  } else {
    depth
  }
  if !store_has_node(self, center_id) {
    let empty_nodes : Array[GraphNode] = []
    let empty_edges : Array[GraphEdge] = []
    return {
      center_id: center_id,
      depth: effective_depth,
      nodes: empty_nodes,
      edges: empty_edges,
    }
  }
  let visited : Array[String] = [center_id]
  let hops : Array[Int] = [0]
  let mut head = 0
  while head < visited.length() {
    let current = visited[head]
    let current_hop = hops[head]
    if current_hop < effective_depth {
      let neighbors = undirected_neighbors(self, current)
      let mut i = 0
      while i < neighbors.length() {
        let neighbor = neighbors[i]
        if !contains_string(visited, neighbor) {
          visited.push(neighbor)
          hops.push(current_hop + 1)
        }
        i += 1
      }
    }
    head += 1
  }
  let nodes : Array[GraphNode] = []
  let mut i = 0
  while i < visited.length() {
    let id = visited[i]
    let hop = hops[i]
    let note_opt = find_note_by_id(self.notes, id)
    let exists = match note_opt {
      Some(_) => true
      None => false
    }
    let title = match note_opt {
      Some(found) => found.title
      None => ghost_title_for(self, id)
    }
    let node_tags : Array[String] = if exists {
      tags_for(self, id)
    } else {
      []
    }
    nodes.push({
      id: id,
      title: title,
      exists: exists,
      hop: hop,
      tags: node_tags,
    })
    i += 1
  }
  sort_nodes(nodes)
  let edges : Array[GraphEdge] = []
  let mut j = 0
  while j < self.links.length() {
    let link = self.links[j]
    if contains_string(visited, link.source) &&
      contains_string(visited, link.target) {
      edges.push({ source: link.source, target: link.target })
    }
    j += 1
  }
  sort_edges(edges)
  { center_id: center_id, depth: effective_depth, nodes: nodes, edges: edges }
}

// ---------------------------------------------------------------------------
// Ghost node helpers
// ---------------------------------------------------------------------------

///|
/// Prefix used for synthetic ids of notes that have not been created yet.
fn ghost_prefix() -> String {
  "ghost:"
}

///|
fn ghost_id(title : String) -> String {
  ghost_prefix() + title
}

///|
/// Resolve the ghost id for an unresolved title during one index rebuild.
///
/// The same title always maps to the same id within a rebuild. The base
/// candidate is `ghost:<title>`; numeric suffixes are appended only when a
/// real note or an earlier ghost already owns that id.
fn assign_ghost_id(
  notes : Array[Note],
  ghosts : Array[GhostAssignment],
  title : String,
) -> String {
  let mut i = 0
  while i < ghosts.length() {
    if ghosts[i].title == title {
      return ghosts[i].id
    }
    i += 1
  }
  let base = ghost_id(title)
  let mut candidate = base
  let mut suffix = 1
  while find_note_index(notes, candidate) >= 0 ||
    ghost_id_in_use(ghosts, candidate) {
    suffix += 1
    candidate = base + ":" + suffix.to_string()
  }
  ghosts.push({ title: title, id: candidate })
  candidate
}

///|
fn ghost_id_in_use(
  ghosts : Array[GhostAssignment],
  candidate : String,
) -> Bool {
  let mut i = 0
  while i < ghosts.length() {
    if ghosts[i].id == candidate {
      return true
    }
    i += 1
  }
  false
}

///|
/// Original wikilink label for a ghost target id.
fn ghost_title_for(store : NoteStore, id : String) -> String {
  let mut i = 0
  while i < store.links.length() {
    let link = store.links[i]
    if link.is_ghost && link.target == id {
      return link.label
    }
    i += 1
  }
  id
}

// ---------------------------------------------------------------------------
// Lookup helpers
// ---------------------------------------------------------------------------

///|
fn find_note_index(notes : Array[Note], id : String) -> Int {
  let mut i = 0
  while i < notes.length() {
    if notes[i].id == id {
      return i
    }
    i += 1
  }
  -1
}

///|
fn find_note_by_id(notes : Array[Note], id : String) -> Note? {
  let index = find_note_index(notes, id)
  if index >= 0 {
    Some(notes[index])
  } else {
    None
  }
}

///|
/// First note whose title matches exactly. With duplicate titles the first
/// note in insertion order wins.
fn find_note_by_title(notes : Array[Note], title : String) -> Note? {
  let mut i = 0
  while i < notes.length() {
    if notes[i].title == title {
      return Some(notes[i])
    }
    i += 1
  }
  None
}

///|
fn contains_string(items : Array[String], value : String) -> Bool {
  let mut i = 0
  while i < items.length() {
    if items[i] == value {
      return true
    }
    i += 1
  }
  false
}

///|
fn contains_link_between(
  links : Array[LinkRecord],
  source : String,
  target : String,
) -> Bool {
  let mut i = 0
  while i < links.length() {
    if links[i].source == source && links[i].target == target {
      return true
    }
    i += 1
  }
  false
}

// ---------------------------------------------------------------------------
// Index maintenance
// ---------------------------------------------------------------------------

///|
/// Rebuild the outgoing-link and tag indexes from every note body.
fn rebuild_index(store : NoteStore) -> Unit {
  let links : Array[LinkRecord] = []
  let tags : Array[TagRecord] = []
  let ghosts : Array[GhostAssignment] = []
  let mut i = 0
  while i < store.notes.length() {
    let current = store.notes[i]
    let parsed = @parser.parse_markdown(current.content)
    let note_tags : Array[String] = []
    let mut t = 0
    while t < parsed.tags.length() {
      note_tags.push(parsed.tags[t])
      t += 1
    }
    tags.push({ id: current.id, tags: note_tags })
    let mut j = 0
    while j < parsed.links.length() {
      let label = parsed.links[j].target
      let resolved = find_note_by_title(store.notes, label)
      let target_is_ghost = resolved is None
      let target_id = match resolved {
        Some(target_note) => target_note.id
        None => assign_ghost_id(store.notes, ghosts, label)
      }
      if !contains_link_between(links, current.id, target_id) {
        links.push({
          source: current.id,
          target: target_id,
          label: label,
          is_ghost: target_is_ghost,
        })
      }
      j += 1
    }
    i += 1
  }
  store.links = links
  store.tags = tags
}

///|
fn tags_for(store : NoteStore, id : String) -> Array[String] {
  let result : Array[String] = []
  let mut i = 0
  while i < store.tags.length() {
    if store.tags[i].id == id {
      let mut j = 0
      while j < store.tags[i].tags.length() {
        result.push(store.tags[i].tags[j])
        j += 1
      }
      return result
    }
    i += 1
  }
  result
}

///|
/// A node exists in the graph when it is a created note or a referenced
/// ghost target.
fn store_has_node(store : NoteStore, id : String) -> Bool {
  if find_note_index(store.notes, id) >= 0 {
    return true
  }
  let mut i = 0
  while i < store.links.length() {
    if store.links[i].target == id {
      return true
    }
    i += 1
  }
  false
}

///|
/// Neighbors reached by following either direction of a reference. Self
/// loops resolve to the node itself and are filtered by the BFS visited set.
fn undirected_neighbors(store : NoteStore, id : String) -> Array[String] {
  let result : Array[String] = []
  let mut i = 0
  while i < store.links.length() {
    let link = store.links[i]
    if link.source == id && !contains_string(result, link.target) {
      result.push(link.target)
    }
    i += 1
  }
  let mut j = 0
  while j < store.links.length() {
    let link = store.links[j]
    if link.target == id && !contains_string(result, link.source) {
      result.push(link.source)
    }
    j += 1
  }
  result
}

// ---------------------------------------------------------------------------
// Deterministic sorting
// ---------------------------------------------------------------------------

///|
/// Compare two strings by code unit, returning -1, 0 or 1.
fn compare_string(a : String, b : String) -> Int {
  let length_a = a.length()
  let length_b = b.length()
  let mut i = 0
  while i < length_a && i < length_b {
    let ca = a.get_char(i).unwrap_or('\u{0}').to_int()
    let cb = b.get_char(i).unwrap_or('\u{0}').to_int()
    if ca < cb {
      return -1
    }
    if ca > cb {
      return 1
    }
    i += 1
  }
  if length_a < length_b {
    -1
  } else if length_a > length_b {
    1
  } else {
    0
  }
}

///|
fn sort_strings(items : Array[String]) -> Unit {
  let mut i = 1
  while i < items.length() {
    let key = items[i]
    let mut j = i - 1
    while j >= 0 && compare_string(items[j], key) > 0 {
      items[j + 1] = items[j]
      j -= 1
    }
    items[j + 1] = key
    i += 1
  }
}

///|
fn sort_nodes(nodes : Array[GraphNode]) -> Unit {
  let mut i = 1
  while i < nodes.length() {
    let key = nodes[i]
    let mut j = i - 1
    while j >= 0 && node_compare(nodes[j], key) > 0 {
      nodes[j + 1] = nodes[j]
      j -= 1
    }
    nodes[j + 1] = key
    i += 1
  }
}

///|
fn node_compare(a : GraphNode, b : GraphNode) -> Int {
  if a.hop < b.hop {
    -1
  } else if a.hop > b.hop {
    1
  } else {
    compare_string(a.id, b.id)
  }
}

///|
fn sort_edges(edges : Array[GraphEdge]) -> Unit {
  let mut i = 1
  while i < edges.length() {
    let key = edges[i]
    let mut j = i - 1
    while j >= 0 && edge_compare(edges[j], key) > 0 {
      edges[j + 1] = edges[j]
      j -= 1
    }
    edges[j + 1] = key
    i += 1
  }
}

///|
fn edge_compare(a : GraphEdge, b : GraphEdge) -> Int {
  let by_source = compare_string(a.source, b.source)
  if by_source != 0 {
    by_source
  } else {
    compare_string(a.target, b.target)
  }
}
