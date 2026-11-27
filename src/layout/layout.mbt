///|
/// Placeholder status kept for the Stage 1 bridge smoke test.
pub fn layout_status() -> String {
  "layout: ready"
}

// ---------------------------------------------------------------------------
// Public data structures
// ---------------------------------------------------------------------------

///|
/// A node with a resolved position on the 2D canvas.
///
/// `hop` is the shortest undirected distance from the center note, `radius`
/// is the visual radius chosen for that hop, and `(x, y)` is the node center
/// in canvas coordinates (origin at the top-left corner).
pub struct PositionedNode {
  id : String
  title : String
  exists : Bool
  hop : Int
  tags : Array[String]
  x : Double
  y : Double
  radius : Double
}

///|
/// A graph edge whose endpoints have been mapped to canvas coordinates.
pub struct LayoutEdge {
  source : String
  target : String
  x1 : Double
  y1 : Double
  x2 : Double
  y2 : Double
}

///|
/// The complete result of laying out one local graph.
///
/// `width` and `height` are the effective canvas size actually used; they
/// differ from the caller's arguments when an invalid size was replaced by
/// the safe default.
pub struct GraphLayout {
  center_id : String
  width : Double
  height : Double
  nodes : Array[PositionedNode]
  edges : Array[LayoutEdge]
}

// ---------------------------------------------------------------------------
// Layout tuning constants
// ---------------------------------------------------------------------------

///|
/// Fallback canvas width used when the caller passes a non-positive width.
const DEFAULT_CANVAS_WIDTH : Double = 600.0

///|
/// Fallback canvas height used when the caller passes a non-positive height.
const DEFAULT_CANVAS_HEIGHT : Double = 400.0

///|
/// Visual radius of the center node.
///
/// Obsidian-style rendering keeps the dot small and puts the readable title
/// below it instead of squeezing text inside the circle.
const CENTER_NODE_RADIUS : Double = 14.0

///|
/// Visual radius of first-hop nodes (inner orbit).
const HOP1_NODE_RADIUS : Double = 9.0

///|
/// Visual radius of second-hop nodes (outer orbit).
const HOP2_NODE_RADIUS : Double = 7.0

///|
/// Minimum gap left between two node circles.
const NODE_GAP : Double = 6.0

///|
/// Maximum safe border kept free around the orbit so nodes and labels are
/// never clipped by the canvas.
const CANVAS_MARGIN : Double = 48.0

///|
/// Orbit radius ratio when only one hop level is present.
const SINGLE_RING_RATIO : Double = 0.62

///|
/// Inner orbit ratio when both hop levels are present.
const INNER_RING_RATIO : Double = 0.48

///|
/// Outer orbit ratio when both hop levels are present.
const OUTER_RING_RATIO : Double = 0.90

///|
/// Gap between the bottom of a node circle and the top of its label.
const LABEL_GAP : Double = 5.0

///|
/// Approximate rendered height of one label line, used as vertical clearance
/// when two orbits sit close together.
const LABEL_HEIGHT : Double = 15.0

///|
/// Approximate advance width of one Latin character at the graph label size.
const LABEL_LATIN_WIDTH : Double = 6.0

///|
/// Approximate advance width of one CJK / full-width character.
const LABEL_CJK_WIDTH : Double = 12.0

///|
/// Smallest label allowance; two short labels still get breathing room.
const LABEL_MIN_WIDTH : Double = 22.0

///|
/// Largest label allowance. Extremely long titles are capped so one label
/// cannot push the whole orbit off the canvas.
const LABEL_MAX_WIDTH : Double = 96.0

///|
/// Extra horizontal gap demanded between two neighbouring labels.
const LABEL_HORIZONTAL_GAP : Double = 6.0

///|
/// Maximum vertical stretch applied to orbital radii on portrait canvases.
/// The vertical radius never exceeds the usable vertical space.
const MAX_VERTICAL_FLEX : Double = 1.6

// ---------------------------------------------------------------------------
// Public layout engine
// ---------------------------------------------------------------------------

///|
/// Compute a deterministic 2D orbital layout for `graph`.
///
/// The center note is pinned to the exact canvas center, first-hop notes are
/// distributed evenly on the inner orbit, and second-hop notes are
/// distributed evenly on the outer orbit. Nodes on each orbit are ordered by
/// id so the same input always produces exactly the same output.
///
/// `width` and `height` are replaced by `600.0 x 400.0` when either value is
/// not strictly positive.
pub fn compute_layout(
  graph : @graph.LocalGraph,
  width : Double,
  height : Double,
) -> GraphLayout {
  let mut canvas_width = width
  let mut canvas_height = height
  if canvas_width <= 0.0 || canvas_height <= 0.0 {
    canvas_width = DEFAULT_CANVAS_WIDTH
    canvas_height = DEFAULT_CANVAS_HEIGHT
  }
  let center_x = canvas_width / 2.0
  let center_y = canvas_height / 2.0

  // Split nodes into orbit groups, then sort each group by id. The sort makes
  // the angular assignment independent of the input node order.
  let center_nodes : Array[@graph.GraphNode] = []
  let inner_nodes : Array[@graph.GraphNode] = []
  let outer_nodes : Array[@graph.GraphNode] = []
  let mut index = 0
  while index < graph.nodes.length() {
    let node = graph.nodes[index]
    if node.hop == 0 {
      center_nodes.push(node)
    } else if node.hop == 1 {
      inner_nodes.push(node)
    } else {
      outer_nodes.push(node)
    }
    index += 1
  }
  sort_nodes_by_id(center_nodes)
  sort_nodes_by_id(inner_nodes)
  sort_nodes_by_id(outer_nodes)

  let inner_count = inner_nodes.length()
  let outer_count = outer_nodes.length()

  // Usable orbit space per axis. The circular radius is bounded by the
  // tighter axis, while a portrait canvas gets an extra vertical radius so
  // nodes use the tall space instead of huddling in a narrow column.
  let short_side = if canvas_width < canvas_height {
    canvas_width
  } else {
    canvas_height
  }
  let margin = canvas_margin(short_side)
  let mut avail_x = canvas_width / 2.0 - margin
  let mut avail_y = canvas_height / 2.0 - margin
  if avail_x < 0.0 {
    avail_x = 0.0
  }
  if avail_y < 0.0 {
    avail_y = 0.0
  }
  let available = if avail_x < avail_y { avail_x } else { avail_y }
  let vertical_flex : Double = if canvas_height > canvas_width &&
    avail_x > 0.0 {
    let ratio = avail_y / avail_x
    if ratio > MAX_VERTICAL_FLEX {
      MAX_VERTICAL_FLEX
    } else {
      ratio
    }
  } else {
    1.0
  }

  // Labels sit below the dots, so each ring reserves the widest label among
  // its own nodes when enforcing the minimum chord between neighbours.
  let inner_label_width = max_label_width(inner_nodes)
  let outer_label_width = max_label_width(outer_nodes)

  let inner_radii : Array[Double] = []
  let outer_radii : Array[Double] = []
  let inner_start = -@math.PI / 2.0
  let mut outer_start = -@math.PI / 2.0
  if inner_count > 0 && outer_count > 0 {
    // Two orbits: lay out the outer orbit first, then cap the inner orbit so
    // the two rings can never touch each other.
    let outer_cap = max_ring_radius(available, HOP2_NODE_RADIUS)
    push_all(
      outer_radii,
      ring_radii(
        outer_count,
        available * OUTER_RING_RATIO,
        outer_cap,
        HOP2_NODE_RADIUS,
        outer_label_width,
      ),
    )
    let outer_min = min_of(outer_radii)
    let radii_sum = HOP1_NODE_RADIUS + HOP2_NODE_RADIUS
    let preferred_gap = radii_sum + LABEL_HEIGHT + LABEL_GAP + NODE_GAP
    let center_safe_radius = CENTER_NODE_RADIUS +
      HOP1_NODE_RADIUS +
      LABEL_HEIGHT +
      LABEL_GAP +
      NODE_GAP
    let mut cross_cap = outer_min - preferred_gap
    // On very tight canvases the preferred gap can squeeze the inner orbit
    // down to the point where it touches the center node. Trade part of the
    // ring-to-ring gap for center clearance first; the half-step phase shift
    // still keeps the two rings from overlapping.
    if cross_cap < center_safe_radius {
      let tight_cap = outer_min - (radii_sum + 0.5)
      if tight_cap > cross_cap {
        cross_cap = tight_cap
      }
    }
    let mut inner_cap = max_ring_radius(available, HOP1_NODE_RADIUS)
    if cross_cap < inner_cap {
      inner_cap = cross_cap
    }
    if inner_cap < 0.0 {
      inner_cap = 0.0
    }
    push_all(
      inner_radii,
      ring_radii(
        inner_count,
        available * INNER_RING_RATIO,
        inner_cap,
        HOP1_NODE_RADIUS,
        inner_label_width,
      ),
    )
    // Half-step phase shift keeps outer nodes from lining up radially with
    // inner nodes, which would hide the connecting edges.
    outer_start = -@math.PI / 2.0 + ring_step(outer_count) / 2.0
  } else if inner_count > 0 {
    let inner_cap = max_ring_radius(available, HOP1_NODE_RADIUS)
    push_all(
      inner_radii,
      ring_radii(
        inner_count,
        available * SINGLE_RING_RATIO,
        inner_cap,
        HOP1_NODE_RADIUS,
        inner_label_width,
      ),
    )
  } else if outer_count > 0 {
    let outer_cap = max_ring_radius(available, HOP2_NODE_RADIUS)
    push_all(
      outer_radii,
      ring_radii(
        outer_count,
        available * SINGLE_RING_RATIO,
        outer_cap,
        HOP2_NODE_RADIUS,
        outer_label_width,
      ),
    )
  }

  let placed : Array[PositionedNode] = []

  // Center nodes sit exactly in the middle of the canvas.
  let mut center_index = 0
  while center_index < center_nodes.length() {
    placed.push(
      positioned(
        center_nodes[center_index],
        center_x,
        center_y,
        CENTER_NODE_RADIUS,
      ),
    )
    center_index += 1
  }

  // Inner orbit: evenly spaced angles starting from the top of the canvas.
  let inner_step = ring_step(inner_count)
  let mut inner_index = 0
  while inner_index < inner_count {
    let angle = inner_start + inner_step * inner_index.to_double()
    let radius = inner_radii[inner_index]
    placed.push(
      positioned(
        inner_nodes[inner_index],
        center_x + radius * @math.cos(angle),
        center_y + radius * vertical_flex * @math.sin(angle),
        HOP1_NODE_RADIUS,
      ),
    )
    inner_index += 1
  }

  // Outer orbit: same scheme, shifted by half a step.
  let outer_step = ring_step(outer_count)
  let mut outer_index = 0
  while outer_index < outer_count {
    let angle = outer_start + outer_step * outer_index.to_double()
    let radius = outer_radii[outer_index]
    placed.push(
      positioned(
        outer_nodes[outer_index],
        center_x + radius * @math.cos(angle),
        center_y + radius * vertical_flex * @math.sin(angle),
        HOP2_NODE_RADIUS,
      ),
    )
    outer_index += 1
  }

  // Map every edge endpoint to the position of its node. Edges that point to
  // nodes outside the laid-out subgraph are skipped instead of producing
  // misleading (0, 0) coordinates.
  let edges : Array[LayoutEdge] = []
  let mut edge_index = 0
  while edge_index < graph.edges.length() {
    let edge = graph.edges[edge_index]
    let from = find_position(placed, edge.source)
    let to = find_position(placed, edge.target)
    match from {
      Some(source_node) => {
        match to {
          Some(target_node) =>
            edges.push({
              source: edge.source,
              target: edge.target,
              x1: source_node.x,
              y1: source_node.y,
              x2: target_node.x,
              y2: target_node.y,
            })
          None => ()
        }
      }
      None => ()
    }
    edge_index += 1
  }

  {
    center_id: graph.center_id,
    width: canvas_width,
    height: canvas_height,
    nodes: placed,
    edges: edges,
  }
}

///|
/// Report whether any two distinct nodes overlap.
///
/// Two nodes overlap when the Euclidean distance between their centers is
/// strictly smaller than the sum of their visual radii. This invariant is
/// used by tests and by callers that want to validate a layout before
/// rendering it.
pub fn has_node_overlap(layout : GraphLayout) -> Bool {
  let mut i = 0
  while i < layout.nodes.length() {
    let a = layout.nodes[i]
    let mut j = i + 1
    while j < layout.nodes.length() {
      let b = layout.nodes[j]
      let dx = a.x - b.x
      let dy = a.y - b.y
      let distance = (dx * dx + dy * dy).sqrt()
      if distance < a.radius + b.radius {
        return true
      }
      j += 1
    }
    i += 1
  }
  false
}

// ---------------------------------------------------------------------------
// Orbit placement helpers
// ---------------------------------------------------------------------------

///|
/// Estimate the rendered width of `title` at the graph label size.
///
/// Latin characters count roughly half a CJK / full-width character. The
/// result is clamped to `LABEL_MIN_WIDTH..LABEL_MAX_WIDTH`; an empty title
/// returns `0.0` because it needs no horizontal clearance.
pub fn estimate_label_width(title : String) -> Double {
  if title.length() == 0 {
    return 0.0
  }
  let mut width = 0.0
  let mut i = 0
  while i < title.length() {
    let code = title.get_char(i).unwrap_or('\u{0}').to_int()
    if code >= 0x2E80 {
      width += LABEL_CJK_WIDTH
    } else {
      width += LABEL_LATIN_WIDTH
    }
    i += 1
  }
  if width < LABEL_MIN_WIDTH {
    LABEL_MIN_WIDTH
  } else if width > LABEL_MAX_WIDTH {
    LABEL_MAX_WIDTH
  } else {
    width
  }
}

///|
/// Widest label allowance among `nodes`; `0.0` for an empty ring.
fn max_label_width(nodes : Array[@graph.GraphNode]) -> Double {
  let mut widest = 0.0
  let mut i = 0
  while i < nodes.length() {
    let width = estimate_label_width(nodes[i].title)
    if width > widest {
      widest = width
    }
    i += 1
  }
  widest
}

///|
/// Compute the radii used by every node on one orbit.
///
/// `count` nodes are spread evenly, so the chord between neighbours is
/// `2 * r * sin(pi / count)`. When that chord would be smaller than the
/// minimum safe separation, the radius is grown up to `max_radius`. If even
/// the maximum radius cannot fit the whole ring, the nodes are staggered
/// across two sub-rings (even indices on the outer sub-ring, odd indices on
/// the inner one), which doubles the effective angular spacing per sub-ring.
fn ring_radii(
  count : Int,
  preferred_radius : Double,
  max_radius : Double,
  node_radius : Double,
  label_width : Double,
) -> Array[Double] {
  let radii : Array[Double] = []
  if count <= 0 {
    return radii
  }
  let cap = if max_radius > 0.0 { max_radius } else { 0.0 }
  let center_clearance = CENTER_NODE_RADIUS +
    node_radius +
    LABEL_HEIGHT +
    LABEL_GAP
  let mut base = preferred_radius
  if base > cap {
    base = cap
  }
  if base < center_clearance && center_clearance <= cap {
    base = center_clearance
  }
  if count == 1 {
    radii.push(base)
    return radii
  }
  // Two neighbouring dots may be close as long as their labels do not collide.
  // The chord between neighbours must therefore cover either the two circles
  // plus the node gap, or the widest label plus its own safe gap.
  let circle_separation = node_radius * 2.0 + NODE_GAP
  let label_separation = label_width + LABEL_HORIZONTAL_GAP
  let separation = if label_separation > circle_separation {
    label_separation
  } else {
    circle_separation
  }
  let required = separation / (2.0 * @math.sin(@math.PI / count.to_double()))
  if cap <= 0.0 {
    let mut i = 0
    while i < count {
      radii.push(0.0)
      i += 1
    }
  } else if required <= cap {
    let chosen = if required > base { required } else { base }
    let mut i = 0
    while i < count {
      radii.push(chosen)
      i += 1
    }
  } else {
    let outer = cap
    let mut inner = cap - separation * 1.25
    if inner < 0.0 {
      inner = 0.0
    }
    let wider_count = (count + 1) / 2
    let wider_required = separation / (2.0 * @math.sin(@math.PI / wider_count.to_double()))
    if inner < wider_required {
      inner = wider_required
    }
    if inner > outer {
      inner = outer
    }
    let mut i = 0
    while i < count {
      if i % 2 == 0 {
        radii.push(outer)
      } else {
        radii.push(inner)
      }
      i += 1
    }
  }
  radii
}

///|
/// Angular step between two neighbours on an orbit of `count` nodes.
fn ring_step(count : Int) -> Double {
  if count > 0 {
    2.0 * @math.PI / count.to_double()
  } else {
    0.0
  }
}

///|
/// Maximum orbit radius that keeps a node with `node_radius` inside the
/// usable canvas area.
fn max_ring_radius(available : Double, node_radius : Double) -> Double {
  let radius = available - node_radius
  if radius > 0.0 {
    radius
  } else {
    0.0
  }
}

///|
/// Safety margin scaled down for very small canvases so the orbit still has
/// some usable space.
fn canvas_margin(short_side : Double) -> Double {
  let scaled = short_side * 0.15
  if scaled < CANVAS_MARGIN {
    scaled
  } else {
    CANVAS_MARGIN
  }
}

///|
/// Copy a graph node into a positioned node at `(x, y)`.
fn positioned(
  node : @graph.GraphNode,
  x : Double,
  y : Double,
  radius : Double,
) -> PositionedNode {
  {
    id: node.id,
    title: node.title,
    exists: node.exists,
    hop: node.hop,
    tags: node.tags,
    x: x,
    y: y,
    radius: radius,
  }
}

///|
/// Look up a positioned node by id.
fn find_position(
  nodes : Array[PositionedNode],
  id : String,
) -> PositionedNode? {
  let mut i = 0
  while i < nodes.length() {
    if compare_string(nodes[i].id, id) == 0 {
      return Some(nodes[i])
    }
    i += 1
  }
  None
}

///|
/// Append every element of `source` to `target`.
fn push_all(target : Array[Double], source : Array[Double]) -> Unit {
  let mut i = 0
  while i < source.length() {
    target.push(source[i])
    i += 1
  }
}

///|
/// Smallest value in a non-empty array; `0.0` for an empty array.
fn min_of(values : Array[Double]) -> Double {
  if values.length() == 0 {
    return 0.0
  }
  let mut smallest = values[0]
  let mut i = 1
  while i < values.length() {
    if values[i] < smallest {
      smallest = values[i]
    }
    i += 1
  }
  smallest
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
/// Sort nodes by id with a stable insertion sort, keeping the layout output
/// independent of the input order.
fn sort_nodes_by_id(nodes : Array[@graph.GraphNode]) -> Unit {
  let mut i = 1
  while i < nodes.length() {
    let key = nodes[i]
    let mut j = i - 1
    while j >= 0 && compare_string(nodes[j].id, key.id) > 0 {
      nodes[j + 1] = nodes[j]
      j -= 1
    }
    nodes[j + 1] = key
    i += 1
  }
}
