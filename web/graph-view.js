/**
 * MoonOrbit · 月轨 — Obsidian-style local graph renderer.
 *
 * Every node/edge coordinate comes from the MoonBit layout engine. This module
 * owns only SVG painting and pointer interaction: hover focus, wheel zoom,
 * drag-to-pan, free node dragging and click activation.
 */

const SVG_NS = 'http://www.w3.org/2000/svg';
const ZOOM_MIN = 0.5;
const ZOOM_MAX = 2.5;
const ZOOM_STEP = 1.12;
const DRAG_THRESHOLD = 3;
const EDGE_TRIM_START = 2;
const EDGE_TRIM_END = 7;
const MAX_CURVE_BEND = 16;

function svgEl(tag, attributes = {}) {
  const element = document.createElementNS(SVG_NS, tag);
  for (const [key, value] of Object.entries(attributes)) {
    if (value === undefined || value === null) continue;
    element.setAttribute(key, String(value));
  }
  return element;
}

function buildArrowMarker(id, className) {
  const marker = svgEl('marker', {
    id,
    viewBox: '0 0 8 8',
    refX: 7,
    refY: 4,
    markerWidth: 6,
    markerHeight: 6,
    markerUnits: 'userSpaceOnUse',
    orient: 'auto',
  });
  marker.appendChild(svgEl('path', { class: className, d: 'M0,0 L8,4 L0,8 Z' }));
  return marker;
}

function buildDefs() {
  const defs = svgEl('defs');
  defs.appendChild(buildArrowMarker('edge-arrow', 'edge-arrow'));
  defs.appendChild(buildArrowMarker('edge-arrow-hot', 'edge-arrow-hot'));

  const gradient = svgEl('radialGradient', {
    id: 'center-gradient',
    cx: '35%',
    cy: '30%',
    r: '78%',
  });
  gradient.appendChild(
    svgEl('stop', { offset: '0%', 'stop-color': '#9dbcff' }),
  );
  gradient.appendChild(
    svgEl('stop', { offset: '55%', 'stop-color': '#4a7dff' }),
  );
  gradient.appendChild(
    svgEl('stop', { offset: '100%', 'stop-color': '#2f63e8' }),
  );
  defs.appendChild(gradient);

  const glow = svgEl('filter', {
    id: 'center-glow',
    x: '-70%',
    y: '-70%',
    width: '240%',
    height: '240%',
  });
  glow.appendChild(
    svgEl('feGaussianBlur', {
      stdDeviation: '4',
      result: 'blur',
    }),
  );
  const merge = svgEl('feMerge');
  merge.appendChild(svgEl('feMergeNode', { in: 'blur' }));
  merge.appendChild(svgEl('feMergeNode', { in: 'SourceGraphic' }));
  glow.appendChild(merge);
  defs.appendChild(glow);
  return defs;
}

/**
 * @param {{
 *   svg: SVGSVGElement,
 *   canvas: HTMLElement,
 *   emptyEl: HTMLElement,
 *   onActivate: (node: object) => void,
 * }} options
 */
export function createGraphView({ svg, canvas, emptyEl, onActivate }) {
  let layout = null;
  let view = { scale: 1, tx: 0, ty: 0 };
  let highlightId = null;
  const overrides = new Map();
  const nodeById = new Map();
  const nodeGroups = new Map();
  let edgeEntries = [];
  let edgeLayer = null;
  let dragging = null;
  let panning = null;
  let activePointer = null;

  function effectivePosition(node) {
    const override = overrides.get(node.id);
    if (override) return { x: override.x, y: override.y };
    return { x: node.x, y: node.y };
  }

  function viewBoxSize() {
    const width =
      layout && Number.isFinite(layout.width) && layout.width > 0
        ? layout.width
        : 600;
    const height =
      layout && Number.isFinite(layout.height) && layout.height > 0
        ? layout.height
        : 400;
    return { width, height };
  }

  function clientToViewBox(event) {
    const rect = svg.getBoundingClientRect();
    const vb = svg.viewBox.baseVal;
    if (!vb || rect.width === 0 || rect.height === 0) return null;
    return {
      x: (event.clientX - rect.left) * (vb.width / rect.width) + vb.x,
      y: (event.clientY - rect.top) * (vb.height / rect.height) + vb.y,
    };
  }

  function clientToContent(event) {
    const point = clientToViewBox(event);
    if (!point) return null;
    return {
      x: (point.x - view.tx) / view.scale,
      y: (point.y - view.ty) / view.scale,
    };
  }

  function applyTransform() {
    const viewport = svg.querySelector('#graph-viewport');
    if (!viewport) return;
    viewport.setAttribute(
      'transform',
      `translate(${view.tx.toFixed(2)} ${view.ty.toFixed(2)}) scale(${view.scale.toFixed(3)})`,
    );
  }

  function resetViewState() {
    view = { scale: 1, tx: 0, ty: 0 };
  }

  function renderOrbits(layer) {
    const { width, height } = viewBoxSize();
    const centerX = width / 2;
    const centerY = height / 2;
    const radiiByHop = new Map();
    for (const node of layout.nodes) {
      if (node.hop === 0) continue;
      const position = effectivePosition(node);
      const distance = Math.hypot(position.x - centerX, position.y - centerY);
      if (distance < 6) continue;
      if (!radiiByHop.has(node.hop)) radiiByHop.set(node.hop, new Set());
      radiiByHop.get(node.hop).add(Math.round(distance));
    }
    const hops = Array.from(radiiByHop.keys()).sort((a, b) => a - b);
    for (const hop of hops) {
      const radii = Array.from(radiiByHop.get(hop))
        .sort((a, b) => a - b)
        .slice(0, 3);
      for (const radius of radii) {
        layer.appendChild(
          svgEl('circle', {
            class: `orbit-ring orbit-hop-${hop > 1 ? 2 : 1}`,
            cx: centerX,
            cy: centerY,
            r: radius,
          }),
        );
      }
    }
  }

  function edgeGeometry(source, target) {
    const from = effectivePosition(source);
    const to = effectivePosition(target);
    const dx = to.x - from.x;
    const dy = to.y - from.y;
    const length = Math.hypot(dx, dy);
    if (length < 1) return null;
    const ux = dx / length;
    const uy = dy / length;
    const startX = from.x + ux * (source.radius + EDGE_TRIM_START);
    const startY = from.y + uy * (source.radius + EDGE_TRIM_START);
    const endX = to.x - ux * (target.radius + EDGE_TRIM_END);
    const endY = to.y - uy * (target.radius + EDGE_TRIM_END);
    if (Math.hypot(endX - startX, endY - startY) < 6) return null;
    const bend = Math.min(MAX_CURVE_BEND, length * 0.1);
    const midX = (startX + endX) / 2 + -uy * bend;
    const midY = (startY + endY) / 2 + ux * bend;
    return {
      d: `M ${startX.toFixed(2)} ${startY.toFixed(2)} Q ${midX.toFixed(2)} ${midY.toFixed(2)} ${endX.toFixed(2)} ${endY.toFixed(2)}`,
    };
  }

  function drawEdges() {
    if (!edgeLayer) return;
    edgeLayer.replaceChildren();
    edgeEntries = [];
    if (!layout || !Array.isArray(layout.edges)) return;
    for (const edge of layout.edges) {
      if (edge.source === edge.target) continue;
      const source = nodeById.get(edge.source);
      const target = nodeById.get(edge.target);
      if (!source || !target) continue;
      const geometry = edgeGeometry(source, target);
      if (!geometry) continue;
      const path = svgEl('path', {
        class: 'edge',
        d: geometry.d,
        'marker-end': 'url(#edge-arrow)',
        'data-source': edge.source,
        'data-target': edge.target,
      });
      const tooltip = svgEl('title');
      tooltip.textContent = `${source.title} → ${target.title}`;
      path.appendChild(tooltip);
      edgeLayer.appendChild(path);
      edgeEntries.push({
        el: path,
        source: edge.source,
        target: edge.target,
      });
    }
    applyHighlight();
  }

  function buildNodeGroup(node) {
    const isCenter = node.hop === 0 || node.id === layout.center_id;
    const classes = ['node', `hop-${Math.min(Math.max(node.hop, 0), 2)}`];
    if (isCenter) classes.push('is-center');
    if (!node.exists) classes.push('is-ghost');

    const group = svgEl('g', {
      class: classes.join(' '),
      transform: `translate(${node.x} ${node.y})`,
      'data-id': node.id,
      tabindex: 0,
      role: 'button',
      'aria-label': `${node.title}${node.exists ? '' : '（未创建）'}，单击打开或创建`,
    });

    const tooltip = svgEl('title');
    tooltip.textContent = node.exists
      ? node.title
      : `${node.title}（未创建，单击创建）`;
    group.appendChild(tooltip);

    // A transparent hit circle keeps the visible dot tiny (Obsidian style)
    // while giving pointer, hover and drag a comfortable target.
    group.appendChild(
      svgEl('circle', { class: 'node-hit', r: node.radius + 9 }),
    );

    if (isCenter) {
      group.appendChild(
        svgEl('circle', {
          class: 'node-halo',
          r: node.radius + 15,
          filter: 'url(#center-glow)',
        }),
      );
    }
    group.appendChild(svgEl('circle', { class: 'node-dot', r: node.radius }));

    const label = svgEl('text', {
      class: 'node-label',
      x: 0,
      y: node.radius + 17,
      'text-anchor': 'middle',
    });
    label.textContent = node.title || node.id;
    group.appendChild(label);

    group.addEventListener('pointerdown', (event) =>
      startNodeDrag(event, node),
    );
    group.addEventListener('mouseenter', () => {
      if (!dragging && !panning) highlight(node.id);
    });
    group.addEventListener('mouseleave', () => {
      if (!dragging) clearHighlight();
    });
    group.addEventListener('focus', () => highlight(node.id));
    group.addEventListener('blur', () => clearHighlight());
    group.addEventListener('keydown', (event) => {
      if (event.key === 'Enter' || event.key === ' ') {
        event.preventDefault();
        onActivate(node);
      }
    });
    return group;
  }

  function renderNodes(layer) {
    const ordered = [...layout.nodes].sort((a, b) => b.hop - a.hop);
    for (const node of ordered) {
      const group = buildNodeGroup(node);
      layer.appendChild(group);
      nodeGroups.set(node.id, group);
    }
  }

  function render() {
    nodeGroups.clear();
    edgeEntries = [];
    if (!layout) {
      svg.replaceChildren();
      emptyEl.hidden = false;
      return;
    }
    emptyEl.hidden = true;
    const { width, height } = viewBoxSize();
    svg.setAttribute('viewBox', `0 0 ${width} ${height}`);
    svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');

    nodeById.clear();
    for (const node of layout.nodes) {
      nodeById.set(node.id, node);
    }

    const viewport = svgEl('g', { id: 'graph-viewport' });
    const orbitLayerEl = svgEl('g', { class: 'graph-orbits' });
    edgeLayer = svgEl('g', { class: 'graph-edges' });
    const nodeLayer = svgEl('g', { class: 'graph-nodes' });

    renderOrbits(orbitLayerEl);
    drawEdges();
    renderNodes(nodeLayer);

    viewport.append(orbitLayerEl, edgeLayer, nodeLayer);
    svg.replaceChildren(buildDefs(), viewport);
    applyTransform();
  }

  function setLayout(next, options = {}) {
    const { preserveView = false } = options;
    const usable =
      next && Array.isArray(next.nodes) && next.nodes.length > 0 ? next : null;
    layout = usable;
    overrides.clear();
    dragging = null;
    panning = null;
    activePointer = null;
    highlightId = null;
    canvas.classList.remove('is-panning', 'is-dragging');
    if (!preserveView) resetViewState();
    render();
  }

  function applyHighlight() {
    if (!highlightId) {
      for (const { el } of edgeEntries) {
        el.classList.remove('is-hot', 'is-dim');
        el.setAttribute('marker-end', 'url(#edge-arrow)');
      }
      for (const group of nodeGroups.values()) {
        group.classList.remove('is-dim', 'is-related');
      }
      return;
    }
    const related = new Set([highlightId]);
    for (const entry of edgeEntries) {
      if (entry.source === highlightId || entry.target === highlightId) {
        related.add(entry.source);
        related.add(entry.target);
        entry.el.classList.add('is-hot');
        entry.el.classList.remove('is-dim');
        entry.el.setAttribute('marker-end', 'url(#edge-arrow-hot)');
      } else {
        entry.el.classList.remove('is-hot');
        entry.el.classList.add('is-dim');
        entry.el.setAttribute('marker-end', 'url(#edge-arrow)');
      }
    }
    for (const [id, group] of nodeGroups) {
      const isRelated = related.has(id);
      group.classList.toggle('is-dim', !isRelated);
      group.classList.toggle('is-related', id !== highlightId && isRelated);
    }
  }

  function highlight(id) {
    if (highlightId === id) return;
    highlightId = id;
    applyHighlight();
  }

  function clearHighlight() {
    if (highlightId === null) return;
    highlightId = null;
    applyHighlight();
  }

  function setNodePosition(id, x, y) {
    overrides.set(id, { x, y });
    const group = nodeGroups.get(id);
    if (group) group.setAttribute('transform', `translate(${x} ${y})`);
    drawEdges();
  }

  function startNodeDrag(event, node) {
    if (event.button !== 0) return;
    event.stopPropagation();
    event.preventDefault();
    const start = clientToContent(event);
    if (!start) return;
    const origin = effectivePosition(node);
    dragging = {
      id: node.id,
      pointerId: event.pointerId,
      startClientX: event.clientX,
      startClientY: event.clientY,
      offsetX: origin.x - start.x,
      offsetY: origin.y - start.y,
      moved: false,
    };
    activePointer = event.pointerId;
    canvas.classList.add('is-dragging');
    svg.setPointerCapture(event.pointerId);
    clearHighlight();
  }

  function startPan(event) {
    panning = {
      pointerId: event.pointerId,
      lastX: event.clientX,
      lastY: event.clientY,
    };
    activePointer = event.pointerId;
    canvas.classList.add('is-panning');
    svg.setPointerCapture(event.pointerId);
    clearHighlight();
  }

  function movePointer(event) {
    if (dragging && event.pointerId === dragging.pointerId) {
      const dx = event.clientX - dragging.startClientX;
      const dy = event.clientY - dragging.startClientY;
      if (!dragging.moved && Math.hypot(dx, dy) > DRAG_THRESHOLD) {
        dragging.moved = true;
      }
      if (!dragging.moved) return;
      const point = clientToContent(event);
      if (!point) return;
      setNodePosition(
        dragging.id,
        point.x + dragging.offsetX,
        point.y + dragging.offsetY,
      );
      return;
    }

    if (panning && event.pointerId === panning.pointerId) {
      const vb = svg.viewBox.baseVal;
      const rect = svg.getBoundingClientRect();
      if (!vb || rect.width === 0 || rect.height === 0) return;
      view.tx += (event.clientX - panning.lastX) * (vb.width / rect.width);
      view.ty += (event.clientY - panning.lastY) * (vb.height / rect.height);
      panning.lastX = event.clientX;
      panning.lastY = event.clientY;
      applyTransform();
    }
  }

  function endPointer(event) {
    if (dragging && event.pointerId === dragging.pointerId) {
      const node = nodeById.get(dragging.id);
      const shouldActivate = !dragging.moved && node;
      dragging = null;
      activePointer = null;
      canvas.classList.remove('is-dragging');
      if (svg.hasPointerCapture(event.pointerId)) {
        svg.releasePointerCapture(event.pointerId);
      }
      if (shouldActivate) onActivate(node);
    }
    if (panning && event.pointerId === panning.pointerId) {
      panning = null;
      activePointer = null;
      canvas.classList.remove('is-panning');
      if (svg.hasPointerCapture(event.pointerId)) {
        svg.releasePointerCapture(event.pointerId);
      }
    }
  }

  function zoomAt(pointX, pointY, factor) {
    const nextScale = Math.min(
      ZOOM_MAX,
      Math.max(ZOOM_MIN, view.scale * factor),
    );
    const applied = nextScale / view.scale;
    view.tx = pointX - (pointX - view.tx) * applied;
    view.ty = pointY - (pointY - view.ty) * applied;
    view.scale = nextScale;
    applyTransform();
  }

  function zoomBy(factor) {
    const { width, height } = viewBoxSize();
    zoomAt(width / 2, height / 2, factor);
  }

  function reset() {
    overrides.clear();
    dragging = null;
    panning = null;
    activePointer = null;
    highlightId = null;
    canvas.classList.remove('is-panning', 'is-dragging');
    resetViewState();
    render();
  }

  svg.addEventListener(
    'wheel',
    (event) => {
      const point = clientToViewBox(event);
      if (!point) return;
      event.preventDefault();
      zoomAt(point.x, point.y, event.deltaY < 0 ? ZOOM_STEP : 1 / ZOOM_STEP);
    },
    { passive: false },
  );

  svg.addEventListener('pointerdown', (event) => {
    if (event.button !== 0) return;
    if (event.target instanceof Element && event.target.closest('.node')) {
      return;
    }
    startPan(event);
  });
  svg.addEventListener('pointermove', movePointer);
  svg.addEventListener('pointerup', endPointer);
  svg.addEventListener('pointercancel', endPointer);

  return {
    setLayout,
    reset,
    zoomIn: () => zoomBy(ZOOM_STEP),
    zoomOut: () => zoomBy(1 / ZOOM_STEP),
    hasLayout: () => Boolean(layout),
    get activePointer() {
      return activePointer;
    },
  };
}
