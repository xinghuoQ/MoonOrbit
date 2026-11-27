// ---------------------------------------------------------------------------
// Layout test helpers
//
// Graphs are built through the public `NoteStore` API because `LocalGraph`
// and its nested records are read-only outside the graph package.
// ---------------------------------------------------------------------------

///|
test "layout smoke" {
  assert_eq(layout_status(), "layout: ready")
}

///|
fn make_note(id : String, content : String) -> @graph.Note {
  @graph.Note::new(id, id, content)
}

///|
fn make_store(notes : Array[@graph.Note]) -> @graph.NoteStore {
  let store = @graph.NoteStore::new()
  let mut i = 0
  while i < notes.length() {
    store.upsert_note(notes[i])
    i += 1
  }
  store
}

///|
fn links_to(ids : Array[String]) -> String {
  let builder = StringBuilder()
  let mut i = 0
  while i < ids.length() {
    builder.write_string("[[")
    builder.write_string(ids[i])
    builder.write_string("]] ")
    i += 1
  }
  builder.to_string()
}

///|
fn ring_id(prefix : String, index : Int) -> String {
  if index < 10 {
    prefix + "0" + index.to_string()
  } else {
    prefix + index.to_string()
  }
}

///|
/// A center note that links to every id in `leaves`; every leaf exists.
fn make_star_graph(leaves : Array[String]) -> @graph.LocalGraph {
  let notes : Array[@graph.Note] = [make_note("center", links_to(leaves))]
  let mut i = 0
  while i < leaves.length() {
    notes.push(make_note(leaves[i], ""))
    i += 1
  }
  make_store(notes).get_local_graph("center", 1)
}

///|
/// Build a two-layer graph: the center links to `inner_count` first-hop
/// nodes, and those first-hop nodes link out to `outer_count` second-hop
/// nodes. Every outer node is reachable as long as `inner_count > 0`.
fn make_layered_graph(
  inner_count : Int,
  outer_count : Int,
) -> @graph.LocalGraph {
  let inner_ids : Array[String] = []
  let mut i = 0
  while i < inner_count {
    inner_ids.push(ring_id("i", i))
    i += 1
  }
  let notes : Array[@graph.Note] = [make_note("center", links_to(inner_ids))]
  let inner_contents : Array[String] = []
  i = 0
  while i < inner_count {
    inner_contents.push("")
    i += 1
  }
  let mut outer_index = 0
  while outer_index < outer_count {
    if inner_count > 0 {
      let owner = outer_index % inner_count
      inner_contents[owner] = inner_contents[owner] + ("[[" + ring_id("o", outer_index) + "]] ")
    }
    outer_index += 1
  }
  i = 0
  while i < inner_count {
    notes.push(make_note(ring_id("i", i), inner_contents[i]))
    i += 1
  }
  outer_index = 0
  while outer_index < outer_count {
    notes.push(make_note(ring_id("o", outer_index), ""))
    outer_index += 1
  }
  make_store(notes).get_local_graph("center", 2)
}

///|
fn find_node(layout : GraphLayout, id : String) -> PositionedNode {
  let mut i = 0
  while i < layout.nodes.length() {
    if compare_string(layout.nodes[i].id, id) == 0 {
      return layout.nodes[i]
    }
    i += 1
  }
  abort("node not found in layout: " + id)
}

///|
fn close_enough(a : Double, b : Double) -> Bool {
  (a - b).abs() < 0.000001
}

///|
fn distance_from(node : PositionedNode, cx : Double, cy : Double) -> Double {
  let dx = node.x - cx
  let dy = node.y - cy
  (dx * dx + dy * dy).sqrt()
}

///|
fn make_positioned(
  id : String,
  x : Double,
  y : Double,
  radius : Double,
) -> PositionedNode {
  {
    id: id,
    title: id,
    exists: true,
    hop: 1,
    tags: [],
    x: x,
    y: y,
    radius: radius,
  }
}

// ---------------------------------------------------------------------------
// Empty and isolated graphs
// ---------------------------------------------------------------------------

///|
test "empty graph keeps canvas size and reports no overlap" {
  let store = @graph.NoteStore::new()
  let graph = store.get_local_graph("none", 2)
  let layout = compute_layout(graph, 600.0, 400.0)
  assert_eq(layout.center_id, "none")
  assert_eq(layout.width, 600.0)
  assert_eq(layout.height, 400.0)
  assert_eq(layout.nodes.length(), 0)
  assert_eq(layout.edges.length(), 0)
  assert_false(has_node_overlap(layout))
}

///|
test "isolated center node is placed exactly at the canvas center" {
  let store = make_store([make_note("center", "")])
  let graph = store.get_local_graph("center", 2)
  let layout = compute_layout(graph, 600.0, 400.0)
  assert_eq(layout.nodes.length(), 1)
  let center = layout.nodes[0]
  assert_eq(center.id, "center")
  assert_eq(center.hop, 0)
  assert_eq(center.x, 300.0)
  assert_eq(center.y, 200.0)
  assert_eq(center.radius, 14.0)
  assert_false(has_node_overlap(layout))
}

///|
test "center node tracks a custom positive canvas size" {
  let store = make_store([make_note("center", "")])
  let graph = store.get_local_graph("center", 2)
  let layout = compute_layout(graph, 800.0, 600.0)
  let center = layout.nodes[0]
  assert_eq(layout.width, 800.0)
  assert_eq(layout.height, 600.0)
  assert_eq(center.x, 400.0)
  assert_eq(center.y, 300.0)
}

// ---------------------------------------------------------------------------
// Single inner orbit (one hop)
// ---------------------------------------------------------------------------

///|
test "one-hop nodes are all equally distant from the center" {
  let leaves : Array[String] = ["a", "b", "d", "e"]
  let layout = compute_layout(make_star_graph(leaves), 600.0, 400.0)
  let center = find_node(layout, "center")
  let radius = distance_from(find_node(layout, "a"), center.x, center.y)
  assert_true(radius > 0.0)
  let mut i = 0
  while i < leaves.length() {
    let node = find_node(layout, leaves[i])
    assert_true(close_enough(distance_from(node, center.x, center.y), radius))
    i += 1
  }
}

///|
test "one-hop nodes start at the top and are spread evenly" {
  let leaves : Array[String] = ["a", "b", "c", "d"]
  let layout = compute_layout(make_star_graph(leaves), 600.0, 400.0)
  let center = find_node(layout, "center")
  let a = find_node(layout, "a")
  let radius = distance_from(a, center.x, center.y)
  // Sorted by id: a at -pi/2 (top), b at 0 (right), c at pi/2 (bottom),
  // d at pi (left).
  assert_true(close_enough(a.x, center.x))
  assert_true(close_enough(a.y, center.y - radius))
  let b = find_node(layout, "b")
  assert_true(close_enough(b.x, center.x + radius))
  assert_true(close_enough(b.y, center.y))
  let c = find_node(layout, "c")
  assert_true(close_enough(c.x, center.x))
  assert_true(close_enough(c.y, center.y + radius))
  let d = find_node(layout, "d")
  assert_true(close_enough(d.x, center.x - radius))
  assert_true(close_enough(d.y, center.y))
}

///|
test "one-hop layout ignores note insertion order" {
  let ordered = make_star_graph(["a", "b", "c", "d"])
  let shuffled_store = make_store([
    make_note("d", ""),
    make_note("a", ""),
    make_note("c", ""),
    make_note("center", "[[d]] [[b]] [[a]] [[c]]"),
    make_note("b", ""),
  ])
  let shuffled = shuffled_store.get_local_graph("center", 1)
  let layout_a = compute_layout(ordered, 600.0, 400.0)
  let layout_b = compute_layout(shuffled, 600.0, 400.0)
  let ids : Array[String] = ["a", "b", "c", "d"]
  let mut i = 0
  while i < ids.length() {
    let node_a = find_node(layout_a, ids[i])
    let node_b = find_node(layout_b, ids[i])
    assert_true(close_enough(node_a.x, node_b.x))
    assert_true(close_enough(node_a.y, node_b.y))
    i += 1
  }
}

///|
test "five one-hop nodes do not overlap" {
  let layout = compute_layout(
    make_star_graph(["a", "b", "c", "d", "e"]),
    600.0,
    400.0,
  )
  assert_eq(layout.nodes.length(), 6)
  assert_false(has_node_overlap(layout))
}

// ---------------------------------------------------------------------------
// Two orbits (one hop plus two hops)
// ---------------------------------------------------------------------------

///|
test "two-ring layout keeps 0 < inner radius < outer radius" {
  let layout = compute_layout(make_layered_graph(4, 4), 600.0, 400.0)
  let center = find_node(layout, "center")
  let inner_radius = distance_from(find_node(layout, "i00"), center.x, center.y)
  let outer_radius = distance_from(find_node(layout, "o00"), center.x, center.y)
  assert_true(inner_radius > 0.0)
  assert_true(outer_radius > inner_radius)
  let mut i = 0
  while i < 4 {
    let inner = find_node(layout, ring_id("i", i))
    let outer = find_node(layout, ring_id("o", i))
    assert_true(
      close_enough(distance_from(inner, center.x, center.y), inner_radius),
    )
    assert_true(
      close_enough(distance_from(outer, center.x, center.y), outer_radius),
    )
    i += 1
  }
}

///|
test "outer ring is phase-shifted by half a step" {
  let layout = compute_layout(make_layered_graph(4, 4), 600.0, 400.0)
  let center = find_node(layout, "center")
  let first_outer = find_node(layout, "o00")
  let outer_radius = distance_from(first_outer, center.x, center.y)
  // With four outer nodes the step is pi/2, so the first outer node sits at
  // -pi/2 + pi/4 = -pi/4 instead of sharing the inner starting angle.
  assert_true(
    close_enough(
      first_outer.x,
      center.x + outer_radius * @math.cos(-@math.PI / 4.0),
    ),
  )
  assert_true(
    close_enough(
      first_outer.y,
      center.y + outer_radius * @math.sin(-@math.PI / 4.0),
    ),
  )
  // And it must not line up with the first inner node (which is at the top).
  let first_inner = find_node(layout, "i00")
  assert_false(close_enough(first_outer.x, first_inner.x))
}

///|
test "two-ring layout with six and eight nodes has no overlap" {
  let layout = compute_layout(make_layered_graph(6, 8), 600.0, 400.0)
  assert_eq(layout.nodes.length(), 15)
  assert_eq(layout.edges.length(), 14)
  assert_false(has_node_overlap(layout))
}

// ---------------------------------------------------------------------------
// High-density anti-overlap checks
// ---------------------------------------------------------------------------

///|
test "twelve nodes on the inner orbit do not overlap" {
  let layout = compute_layout(make_layered_graph(12, 0), 600.0, 400.0)
  assert_eq(layout.nodes.length(), 13)
  assert_false(has_node_overlap(layout))
}

///|
test "sixteen nodes on the inner orbit do not overlap" {
  let layout = compute_layout(make_layered_graph(16, 0), 600.0, 400.0)
  assert_eq(layout.nodes.length(), 17)
  assert_false(has_node_overlap(layout))
}

///|
test "sixteen inner plus sixteen outer nodes do not overlap" {
  let layout = compute_layout(make_layered_graph(16, 16), 600.0, 400.0)
  assert_eq(layout.nodes.length(), 33)
  assert_false(has_node_overlap(layout))
}

///|
test "a large two-ring layout still clears the inner center node" {
  let layout = compute_layout(make_layered_graph(16, 16), 600.0, 400.0)
  let center = find_node(layout, "center")
  let first_inner = find_node(layout, "i00")
  assert_true(distance_from(first_inner, center.x, center.y) > 22.0 + 16.0)
}

// ---------------------------------------------------------------------------
// Canvas boundary constraints
// ---------------------------------------------------------------------------

///|
test "every node circle stays inside the canvas" {
  let layout = compute_layout(make_layered_graph(6, 8), 600.0, 400.0)
  let mut i = 0
  while i < layout.nodes.length() {
    let node = layout.nodes[i]
    assert_true(node.x - node.radius >= 0.0)
    assert_true(node.y - node.radius >= 0.0)
    assert_true(node.x + node.radius <= layout.width)
    assert_true(node.y + node.radius <= layout.height)
    i += 1
  }
}

///|
test "layout still fits a narrow canvas" {
  let layout = compute_layout(make_layered_graph(6, 8), 320.0, 240.0)
  let mut i = 0
  while i < layout.nodes.length() {
    let node = layout.nodes[i]
    assert_true(node.x - node.radius >= 0.0)
    assert_true(node.y - node.radius >= 0.0)
    assert_true(node.x + node.radius <= layout.width)
    assert_true(node.y + node.radius <= layout.height)
    i += 1
  }
  assert_false(has_node_overlap(layout))
}

// ---------------------------------------------------------------------------
// Edge endpoint mapping
// ---------------------------------------------------------------------------

///|
test "edge endpoints match their node coordinates" {
  let store = make_store([
    make_note("center", "[[a]]"),
    make_note("a", "[[b]]"),
    make_note("b", ""),
  ])
  let graph = store.get_local_graph("center", 2)
  assert_eq(graph.edges.length(), 2)
  let layout = compute_layout(graph, 600.0, 400.0)
  assert_eq(layout.edges.length(), graph.edges.length())
  let mut i = 0
  while i < layout.edges.length() {
    let edge = layout.edges[i]
    let source = find_node(layout, edge.source)
    let target = find_node(layout, edge.target)
    assert_eq(edge.x1, source.x)
    assert_eq(edge.y1, source.y)
    assert_eq(edge.x2, target.x)
    assert_eq(edge.y2, target.y)
    i += 1
  }
}

///|
test "self-loop edge collapses to the node coordinate" {
  let store = make_store([
    make_note("center", "[[a]]"),
    make_note("a", "[[a]]"),
  ])
  let graph = store.get_local_graph("center", 1)
  let layout = compute_layout(graph, 600.0, 400.0)
  let a = find_node(layout, "a")
  let mut i = 0
  let mut found = false
  while i < layout.edges.length() {
    let edge = layout.edges[i]
    if compare_string(edge.source, "a") == 0 &&
      compare_string(edge.target, "a") == 0 {
      found = true
      assert_eq(edge.x1, a.x)
      assert_eq(edge.y1, a.y)
      assert_eq(edge.x2, a.x)
      assert_eq(edge.y2, a.y)
    }
    i += 1
  }
  assert_true(found)
}

// ---------------------------------------------------------------------------
// Safe canvas fallbacks
// ---------------------------------------------------------------------------

///|
test "zero width and height fall back to the default canvas" {
  let store = make_store([make_note("center", "")])
  let graph = store.get_local_graph("center", 2)
  let layout = compute_layout(graph, 0.0, 0.0)
  assert_eq(layout.width, 600.0)
  assert_eq(layout.height, 400.0)
  let center = layout.nodes[0]
  assert_eq(center.x, 300.0)
  assert_eq(center.y, 200.0)
}

///|
test "negative width and height fall back to the default canvas" {
  let store = make_store([make_note("center", "")])
  let graph = store.get_local_graph("center", 2)
  let layout = compute_layout(graph, -120.0, -80.0)
  assert_eq(layout.width, 600.0)
  assert_eq(layout.height, 400.0)
  assert_eq(layout.nodes[0].x, 300.0)
  assert_eq(layout.nodes[0].y, 200.0)
}

///|
test "zero width alone falls back to the default canvas" {
  let store = make_store([make_note("center", "")])
  let graph = store.get_local_graph("center", 2)
  let layout = compute_layout(graph, 0.0, 500.0)
  assert_eq(layout.width, 600.0)
  assert_eq(layout.height, 400.0)
}

///|
test "zero height alone falls back to the default canvas" {
  let store = make_store([make_note("center", "")])
  let graph = store.get_local_graph("center", 2)
  let layout = compute_layout(graph, 500.0, 0.0)
  assert_eq(layout.width, 600.0)
  assert_eq(layout.height, 400.0)
}

// ---------------------------------------------------------------------------
// Determinism and data preservation
// ---------------------------------------------------------------------------

///|
test "repeated calls with identical input produce identical output" {
  let graph = make_layered_graph(6, 8)
  let first = compute_layout(graph, 600.0, 400.0)
  let second = compute_layout(graph, 600.0, 400.0)
  assert_eq(first.nodes.length(), second.nodes.length())
  let mut i = 0
  while i < first.nodes.length() {
    assert_eq(first.nodes[i].id, second.nodes[i].id)
    assert_eq(first.nodes[i].hop, second.nodes[i].hop)
    assert_true(close_enough(first.nodes[i].x, second.nodes[i].x))
    assert_true(close_enough(first.nodes[i].y, second.nodes[i].y))
    assert_true(close_enough(first.nodes[i].radius, second.nodes[i].radius))
    i += 1
  }
}

///|
test "ghost nodes keep their unresolved identity" {
  let store = make_store([make_note("center", "[[missing]]")])
  let graph = store.get_local_graph("center", 1)
  let layout = compute_layout(graph, 600.0, 400.0)
  let ghost = find_node(layout, "ghost:missing")
  assert_false(ghost.exists)
  assert_eq(ghost.title, "missing")
  assert_eq(ghost.tags.length(), 0)
}

///|
test "tags are preserved on positioned nodes" {
  let store = make_store([
    make_note("center", "[[tagged]]"),
    make_note("tagged", "#moonbit #graph"),
  ])
  let graph = store.get_local_graph("center", 1)
  let layout = compute_layout(graph, 600.0, 400.0)
  let tagged = find_node(layout, "tagged")
  assert_eq(tagged.tags.length(), 2)
  assert_eq(tagged.tags[0], "moonbit")
  assert_eq(tagged.tags[1], "graph")
}

///|
test "node radii follow the hop level" {
  let layout = compute_layout(make_layered_graph(4, 4), 600.0, 400.0)
  assert_eq(find_node(layout, "center").radius, 14.0)
  assert_eq(find_node(layout, "i00").radius, 9.0)
  assert_eq(find_node(layout, "o00").radius, 7.0)
}

// ---------------------------------------------------------------------------
// Portrait canvases and label clearance
// ---------------------------------------------------------------------------

///|
test "label width estimation distinguishes Latin and CJK text" {
  assert_eq(estimate_label_width(""), 0.0)
  assert_eq(estimate_label_width("ab"), 22.0)
  assert_eq(estimate_label_width("中文"), 24.0)
  assert_eq(estimate_label_width("abcdefghij"), 60.0)
  assert_eq(estimate_label_width("这是一个非常非常长的标题"), 96.0)
}

///|
/// A star graph whose notes carry readable titles instead of short ids.
fn make_titled_star_graph(titles : Array[String]) -> @graph.LocalGraph {
  let center_content = StringBuilder()
  let mut i = 0
  while i < titles.length() {
    center_content.write_string("[[")
    center_content.write_string(titles[i])
    center_content.write_string("]] ")
    i += 1
  }
  let notes : Array[@graph.Note] = [
    @graph.Note::new("center", "中心笔记", center_content.to_string()),
  ]
  i = 0
  while i < titles.length() {
    notes.push(@graph.Note::new("n" + i.to_string(), titles[i], ""))
    i += 1
  }
  make_store(notes).get_local_graph("center", 1)
}

///|
/// Smallest pairwise distance between two nodes on the given hop.
fn min_hop_distance(layout : GraphLayout, hop : Int) -> Double {
  let points : Array[PositionedNode] = []
  let mut i = 0
  while i < layout.nodes.length() {
    if layout.nodes[i].hop == hop {
      points.push(layout.nodes[i])
    }
    i += 1
  }
  let mut smallest = 1000000000.0
  let mut a = 0
  while a < points.length() {
    let mut b = a + 1
    while b < points.length() {
      let dx = points[a].x - points[b].x
      let dy = points[a].y - points[b].y
      let distance = (dx * dx + dy * dy).sqrt()
      if distance < smallest {
        smallest = distance
      }
      b += 1
    }
    a += 1
  }
  smallest
}

///|
test "portrait canvas stretches hop orbits vertically" {
  let layout = compute_layout(make_layered_graph(4, 4), 360.0, 720.0)
  let center = find_node(layout, "center")
  let mut max_dx = 0.0
  let mut max_dy = 0.0
  let mut i = 0
  while i < layout.nodes.length() {
    let node = layout.nodes[i]
    if node.hop > 0 {
      let dx = (node.x - center.x).abs()
      let dy = (node.y - center.y).abs()
      if dx > max_dx {
        max_dx = dx
      }
      if dy > max_dy {
        max_dy = dy
      }
    }
    i += 1
  }
  assert_true(max_dy > max_dx)
  assert_true(max_dy > 0.0)
}

///|
test "portrait layout keeps every node inside the canvas" {
  let layout = compute_layout(make_layered_graph(6, 8), 360.0, 720.0)
  let mut i = 0
  while i < layout.nodes.length() {
    let node = layout.nodes[i]
    assert_true(node.x - node.radius >= 0.0)
    assert_true(node.y - node.radius >= 0.0)
    assert_true(node.x + node.radius <= layout.width)
    assert_true(node.y + node.radius <= layout.height)
    i += 1
  }
  assert_false(has_node_overlap(layout))
}

///|
test "long titles reserve enough chord between neighbours" {
  let titles : Array[String] = [
    "这是一个很长的标题",
    "另一个同样很长的标题",
    "第三个长标题文本",
    "第四个长标题内容",
    "第五个长标题名称",
    "第六个长标题记录",
  ]
  let layout = compute_layout(make_titled_star_graph(titles), 420.0, 860.0)
  let smallest = min_hop_distance(layout, 1)
  assert_true(smallest > 0.0)
  let widest = estimate_label_width("这是一个很长的标题")
  assert_true(smallest + 0.001 >= widest)
  assert_false(has_node_overlap(layout))
}

///|
test "portrait two-ring layout still has no overlaps" {
  let layout = compute_layout(make_layered_graph(8, 8), 400.0, 900.0)
  assert_false(has_node_overlap(layout))
  let center = find_node(layout, "center")
  let inner_radius = distance_from(find_node(layout, "i00"), center.x, center.y)
  let outer_radius = distance_from(find_node(layout, "o00"), center.x, center.y)
  assert_true(outer_radius > inner_radius)
}

// ---------------------------------------------------------------------------
// The overlap checker itself
// ---------------------------------------------------------------------------

///|
test "overlap checker flags intersecting node circles" {
  let nodes : Array[PositionedNode] = [
    make_positioned("a", 10.0, 10.0, 5.0),
    make_positioned("b", 14.0, 10.0, 5.0),
  ]
  let layout : GraphLayout = {
    center_id: "a",
    width: 100.0,
    height: 100.0,
    nodes: nodes,
    edges: [],
  }
  assert_true(has_node_overlap(layout))
}

///|
test "overlap checker accepts separated node circles" {
  let nodes : Array[PositionedNode] = [
    make_positioned("a", 10.0, 10.0, 5.0),
    make_positioned("b", 30.0, 30.0, 5.0),
  ]
  let layout : GraphLayout = {
    center_id: "a",
    width: 100.0,
    height: 100.0,
    nodes: nodes,
    edges: [],
  }
  assert_false(has_node_overlap(layout))
}
