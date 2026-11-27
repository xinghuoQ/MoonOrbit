# MoonOrbit · 月轨

**由 MoonBit 1.0 驱动的双链 Markdown 编辑器与局部关系图谱**

**A dual-link Markdown editor and local graph engine powered by MoonBit 1.0.**

`MoonBit 1.0` · `171 unit tests` · `MIT License` · `Zero npm dependencies`

---

## 项目简介 · Overview

**中文**

MoonOrbit（月轨）把 **MarkText 的清爽实时排版** 与 **Obsidian 的局部关系图谱** 放进同一个三栏界面：

- **左栏**：文件夹 + `.md` 文档资源管理器（可折叠文件夹、文档标签徽章、新建/重命名/删除文件夹、导入与导出 `.md`）、关键词搜索、未创建链接（幽灵节点）。
- **中栏**：MarkText 风格的 Markdown 编辑与实时预览，顶部可切换当前文档所属文件夹；点击 `[[双链]]` 即可跳转或一键创建目标笔记，底部展示反向链接。
- **右栏**：Obsidian 风格的 SVG 局部图谱，支持 1 跳 / 2 跳、方向箭头、轨道参考圈、悬停聚焦淡化、滚轮缩放（0.5x–2.5x）、拖拽空白平移、单节点自由拖拽，右上角提供 + / − / 重置居中按钮。

项目采用 **“重 MoonBit 核心引擎 + 轻 Web 界面”** 架构：Markdown 解析、双链与标签提取、反向链接、未创建节点、局部子图、2D 布局坐标全部由 MoonBit 完成并编译为 JavaScript；前端只负责 DOM/SVG 渲染与交互，零 npm、零打包器、零运行时框架。

**English**

MoonOrbit combines **MarkText-style live Markdown typesetting** with an **Obsidian-style local graph** in a three-pane workspace:

- **Left**: a folder + `.md` document explorer (collapsible folders, per-note tag badges, new/rename/delete folder, `.md` import and export), keyword search and unresolved (“ghost”) links.
- **Center**: MarkText-inspired editing with live preview and a folder dropdown for the active document. Clicking a `[[wikilink]]` opens the target note or creates it on the spot; backlinks sit below the editor.
- **Right**: an Obsidian-inspired SVG local graph with 1-hop / 2-hop depth, directed arrowheads, orbit guide rings, hover focus with dimming, wheel zoom (0.5x–2.5x), drag-to-pan, free node dragging and + / − / reset controls.

The architecture is **heavy MoonBit core + light web shell**: Markdown rendering, wikilink and tag extraction, backlinks, unresolved links, local subgraph traversal and every `(x, y)` layout coordinate are produced by MoonBit compiled to JavaScript. The browser layer only renders DOM/SVG and handles interaction — no npm, no bundler, no frontend framework.

---

## 功能亮点 · Highlights

**中文**

| 能力 | 说明 |
| --- | --- |
| Markdown 渲染 | H1–H6、粗体、斜体、行内代码、代码块、列表、引用、普通链接 |
| 双链 | `[[目标笔记]]`、`[[目标笔记\|显示别名]]`，预览中可直接点击 |
| 标签 | `#moonbit`、`#工作/计划`，显示在笔记列表与图谱节点数据中 |
| 反向链接 | 谁引用了当前笔记，实时计算并展示为中栏底部胶囊 |
| 未创建链接 | 被引用但尚未创建的标题，左侧一键创建 |
| 文件夹树 | `📁 文件夹` 可折叠，文档显示为 `📄 标题.md` 并带标签数量徽章 |
| 文档工作流 | 编辑器顶部切换所属文件夹；支持多选导入本地 `.md` 与导出当前文档 |
| 局部图谱 | 以当前笔记为中心的 1 跳 / 2 跳子图，出链与入链都参与遍历 |
| 图谱交互 | 悬停聚焦（无关节点淡至 0.25）、滚轮缩放、拖拽平移、单节点自由拖拽 |
| 确定性布局 | 中心固定、内圈 1 跳、外圈 2 跳；节点 14/9/7 圆点，标题在圆点下方并预留防遮挡间距 |
| 竖屏自适应 | `height > width` 时在安全边距内拉伸纵向轨道，窄面板也能舒展分布 |
| 纯静态部署 | `web/` 可直接放到任意静态服务器，无需构建步骤 |

**English**

| Capability | Details |
| --- | --- |
| Markdown | Headings H1–H6, bold, italic, inline code, fenced code, lists, quotes, links |
| Wikilinks | `[[Target]]` and `[[Target\|alias]]`, clickable in the preview |
| Tags | `#moonbit`, `#work/plan`, surfaced in the vault list and graph data |
| Backlinks | Every note that references the active note, computed live |
| Unresolved links | Referenced-but-missing titles, creatable in one click |
| Folder tree | Collapsible `📁 folders`, `📄 title.md` documents and per-note tag badges |
| Markdown workflow | Folder dropdown in the editor, multi-file `.md` import and current-note export |
| Local graph | 1-hop / 2-hop subgraph around the active note; outgoing and incoming edges both traverse |
| Graph interaction | Hover focus (unrelated nodes dim to 0.25), wheel zoom, drag-to-pan and free node dragging |
| Deterministic layout | Center pinned, hop-1 inner ring, hop-2 outer ring; 14/9/7 dots with labels below and reserved clearance |
| Portrait adaptation | When `height > width`, orbits stretch vertically inside the safe margin |
| Static hosting | `web/` runs on any static file server with no build step |

---

## 架构设计 · Architecture

**中文**

```text
┌──────────────────────────────────────────────────────────────┐
│ Browser                                                      │
│  index.html + style.css + app.js   (native HTML/CSS/JS)      │
│        │                                                     │
│        │  import { ... } from './bridge.js'                  │
│        ▼                                                     │
│  bridge.js  ── MoonBit 1.0 compiled to an ES Module ──       │
│        │                                                     │
│        ├── parser  Markdown → HTML, wikilinks, tags          │
│        ├── graph   NoteStore, backlinks, unresolved, BFS     │
│        ├── layout  deterministic radial (x, y) coordinates   │
│        └── bridge  JSON request/response envelopes           │
│                                                              │
│  localStorage['moonorbit.vault.v1']  ← the shell owns data   │
└──────────────────────────────────────────────────────────────┘
```

数据流 / Data flow:

1. `app.js` 把全部笔记（含 `folder`）、空文件夹列表、当前笔记 id、深度与画布尺寸序列化为 JSON，调用 `compute_workspace_json`。
   `app.js` serialises every note (including `folder`), empty folders, the active id, depth and canvas size, then calls `compute_workspace_json`.
2. MoonBit 在**单次请求内**重建 `NoteStore`，解析全部正文、解析双链目标、执行无向 BFS、计算布局，并返回 JSON。
   MoonBit rebuilds a stateless `NoteStore`, parses every body, resolves wikilinks, runs an undirected BFS, computes layout, and returns JSON.
3. 前端只把返回的 `html` 放进预览、把 `(x, y)` 画成 SVG 节点与连线；不重复实现任何图算法。
   The shell only injects the returned `html` and draws the returned `(x, y)` coordinates; it reimplements no graph algorithm.
4. 笔记库持久化完全在浏览器 `localStorage`；MoonBit 引擎无全局状态，便于测试与多实例调用。
   Persistence lives entirely in `localStorage`; the MoonBit engine is stateless per request, which keeps it testable and re-entrant.

**English**

The diagram above is language-neutral. In short: the browser owns storage and pixels, MoonBit owns parsing and graph mathematics. A request is one pure function from `{notes, active_id, depth, width, height}` to rendered HTML, backlinks, unresolved titles and layout coordinates.

---

## 核心模块 · Core modules

### `src/parser` — Markdown, wikilinks, tags

**中文**

- 行级块解析：标题、围栏代码块、引用、无序/有序列表、段落。
- 行内解析：粗体、斜体、行内代码、`[普通链接](url)`、`[[目标|别名]]`、`#标签`。
- 所有用户文本与属性值都会 HTML 转义（`& < > "`），因此桥接层返回的 HTML 可安全交给 `innerHTML`。
- 双链输出为 `<a class="wiki-link" data-target="…" href="#note/…">`，前端据此做跳转。
- 标签支持中文、字母、数字、`_`、`-`、`/`；`C#`、`foo#bar` 不会被误判为标签。

**English**

Line-based block parsing (headings, fenced code, quotes, lists, paragraphs) plus inline parsing (bold, italic, inline code, links, wikilinks, tags). Every text and attribute value is HTML-escaped, so the bridge output is safe for `innerHTML`. Wikilinks render as `<a class="wiki-link" data-target="…">` for shell-side navigation.

### `src/graph` — note store, backlinks, local subgraph

**中文**

- `NoteStore` 维护笔记集合与实时重建的出链/标签索引。
- `Note.folder` 记录文档所在文件夹（`""` 为根目录）；`list_folders`、`notes_in_folder`、`set_note_folder` 提供文件夹树所需的查询、筛选与移动能力。
- 双链按**标题精确匹配**解析；未命中的标题生成 `ghost:<标题>` 幽灵 id，冲突时追加数字后缀。
- `get_backlinks` 返回引用当前笔记的已有笔记；`get_unresolved_links` 返回所有尚未创建的标题（去重、排序）。
- `get_local_graph` 使用无向 BFS，但输出边保留原始引用方向；深度被限制在 `1..2`；节点按 `(hop, id)`、边按 `(source, target)` 排序，保证输出稳定。

**English**

`NoteStore` keeps notes plus a rebuilt index of outgoing links and tags. `Note.folder` records the document's workspace folder (`""` is the root), and `list_folders`, `notes_in_folder` and `set_note_folder` power the folder tree. Wikilinks resolve by exact title; unresolved titles become synthetic `ghost:<title>` ids with numeric suffixes on collision. `get_backlinks` returns existing referrers, `get_unresolved_links` returns missing titles, and `get_local_graph` runs an undirected BFS while emitting the original directed edges. Output is sorted deterministically.

### `src/layout` — deterministic orbital layout

**中文**

- 中心节点固定在 `(width / 2, height / 2)`，圆点半径为 `14 / 9 / 7`（中心 / 1 跳 / 2 跳），文字标签放在圆点正下方。
- 1 跳节点均匀分布在内圈，2 跳节点分布在外圈；两圈之间做半角错位，避免连线被节点遮挡。
- 同环最小弦长同时考虑圆点直径与**标签宽度**，环间距额外预留标签高度，左右相邻文字不再打架；标签过宽时按 `22–96px` 截断估算。
- 画布为竖长型（`height > width`）时，纵向半径最多拉伸 `1.6x`（且不超出安全边距），让窄面板上下左右都舒展。
- 半径根据可用空间、节点数量与最小间距动态调整；极其拥挤时使用双半径交错排布，避免节点重叠。
- 宽或高非正数时回退到 `600 × 400`；实际使用的尺寸会随结果返回。
- 同样的输入永远得到同样的坐标，便于单元测试与稳定演示。

**English**

The center node is pinned to the canvas center with `14 / 9 / 7` dot radii for hop 0 / 1 / 2 and every title rendered below its dot. Hop-1 nodes fill an inner orbit, hop-2 nodes an outer orbit, with a half-step phase shift so edges are not hidden. The minimum chord accounts for both dot size and label width, while ring-to-ring clearance reserves label height. Portrait canvases stretch the vertical radius up to `1.6x` inside the safe margin. Tight canvases fall back to staggered sub-rings; invalid sizes fall back to `600 × 400`. Identical input always yields identical coordinates.

### `src/bridge` — JSON boundary

**中文**

对外暴露四个函数，其中三个是网页使用的稳定 API：

| 函数 | 作用 |
| --- | --- |
| `get_sample_notes_json()` | 返回 6 篇互链示例笔记，其中「路线图规划」故意未创建 |
| `render_markdown_json(markdown)` | 返回 `{html, links, tags}` |
| `compute_workspace_json(request)` | 返回渲染结果、反链、未创建链接与带坐标的布局 |
| `bridge_status()` | 阶段 1 保留的冒烟测试入口 |

请求 / Response contract:

```json
{
  "notes": [{ "id": "guide", "title": "使用指南", "content": "# 使用指南\n[[双链笔记]]", "folder": "01-快速开始" }],
  "folders": ["01-快速开始", "02-双链与标签", "03-技术架构"],
  "active_id": "guide",
  "depth": 2,
  "width": 420,
  "height": 760
}
```

```json
{
  "ok": true,
  "error": null,
  "active_render": { "html": "<h1>…</h1>", "links": [], "tags": [] },
  "backlinks": [{ "id": "wikilinks", "title": "双链笔记", "folder": "02-双链与标签" }],
  "unresolved_links": ["路线图规划"],
  "layout": {
    "center_id": "guide",
    "width": 420,
    "height": 760,
    "nodes": [{ "id": "guide", "title": "使用指南", "exists": true, "hop": 0, "tags": ["指南"], "folder": "01-快速开始", "x": 210, "y": 380, "radius": 14 }],
    "edges": [{ "source": "guide", "target": "wikilinks", "x1": 210, "y1": 380, "x2": 260, "y2": 200 }]
  },
  "folders": ["01-快速开始", "02-双链与标签", "03-技术架构"]
}
```

`folders` 是可选字段：请求不携带时响应保持旧的 6 键信封；携带（包括空数组）时响应追加合并后的文件夹列表，空文件夹也会保留。

任何非法输入都返回 `{"ok": false, "error": "…"}`，不会有异常逃逸到 JavaScript。

**English**

Three stable web APIs plus one legacy smoke-test entry. Each note may carry an optional `folder` (default `""`), layout nodes and backlinks echo it, and an optional request-level `folders` array preserves empty folders. Malformed input always returns `{"ok": false, "error": "…"}`; no exception escapes into JavaScript.

### `web/` — the shell

**中文**

- `index.html`：三栏语义结构、文件夹树、工具栏、图例、无障碍标签。
- `style.css`：明亮纸白主题、衬线阅读栏、文件夹树、轨道图谱与交互控件样式。
- `app.js`：localStorage 持久化、文件夹模型、`.md` 导入导出、防抖请求与事件编排。
- `explorer.js`：文件夹 + `.md` 文档树渲染、折叠/展开、标签徽章与文件夹操作回调。
- `graph-view.js`：SVG 图谱渲染、悬停聚焦、滚轮缩放、拖拽平移、节点拖拽与激活。
- `bridge.js`：由 MoonBit 源码生成的 ES Module（构建产物，已提交以便静态托管）。

**English**

`index.html` provides the semantic three-pane structure, folder tree and controls; `style.css` the light-paper visual system; `app.js` persistence, the folder vault model, `.md` import/export and event orchestration; `explorer.js` the folder/document tree; `graph-view.js` SVG painting plus hover focus, zoom, pan and node dragging. `bridge.js` is the committed MoonBit build artifact so the site stays zero-build.

---

## 测试 · Testing

**中文**

当前 **171 个单元测试全部通过**，覆盖四个包：

- `src/parser`：块级与行内 Markdown、转义、别名双链、标签边界、CRLF。
- `src/graph`：笔记增删改、反链、幽灵节点、深度截断、BFS 跳数、排序稳定性、`folder` 存储/更新/移动。
- `src/layout`：中心固定、14/9/7 半径、内外圈半径、节点不重叠、标签宽度估算、竖屏拉伸、异常画布回退、确定性。
- `src/bridge`：JSON 往返、`folder`/`folders` 往返、错误信封、示例库完整性。

```bash
$ moon check --deny-warn
Finished. moon: no work to do

$ moon test
Total tests: 171, passed: 171, failed: 0.
```

**English**

All **171 unit tests pass**, covering the parser (blocks, inline syntax, escaping, aliases, tag boundaries, CRLF), the graph store (mutation, backlinks, ghost ids, depth clamping, BFS hops, deterministic sorting, folder storage/moves), layout (center pinning, 14/9/7 radii, ring radii, non-overlap, label-width clearance, portrait stretching, invalid-canvas fallback, determinism) and the JSON bridge (folder round-trips, error envelope, sample vault).

---

## 快速开始 · Getting started

### 环境要求 · Requirements

- **MoonBit 1.0 toolchain**（本仓库验证于 `moon 0.1.20261126`）。安装说明见 <https://www.moonbitlang.com/>。
- 任意静态 HTTP 服务器：Python 3、Node.js、Caddy、Nginx 均可。

### 1. 检查与测试 · Check and test

```bash
moon check --deny-warn
moon test
```

### 2. 构建 JS 引擎并同步到 `web/` · Build and sync the JS engine

```bash
moon build --target js --release
cp _build/js/release/build/src/bridge/bridge.js web/bridge.js
```

> 若使用 debug 构建，产物在 `_build/js/debug/build/src/bridge/bridge.js`。
> Debug builds live under `_build/js/debug/build/src/bridge/bridge.js`.

### 3. 启动本地静态服务器 · Serve the web shell

```bash
python -m http.server 8080 --directory web
```

或 / or:

```bash
cd web && python -m http.server 8080
```

然后打开 / then open <http://localhost:8080/>。

**为什么必须用 HTTP 而不是双击 `index.html`？**
**Why not open `index.html` directly?**

`app.js` 使用原生 ES Module `import './bridge.js'`。浏览器对 `file://` 协议下的模块导入执行严格的同源/CORS 限制，会直接拒绝加载。通过 `http://localhost` 提供文件即可正常工作。

`app.js` uses a native ES Module import. Browsers block module imports under the `file://` origin, so the page must be served over HTTP.

### 4. 可选：用 Node 验证桥接层 · Optional: verify the bridge in Node

```bash
cp web/bridge.js /tmp/bridge.mjs
node --input-type=module -e "
import('/tmp/bridge.mjs').then((m) => {
  const notes = JSON.parse(m.get_sample_notes_json());
  const result = JSON.parse(m.compute_workspace_json(JSON.stringify({
    notes, active_id: 'guide', depth: 2, width: 600, height: 400,
  })));
  console.log(result.ok, result.layout.nodes.length);
});
"
```

> Node 会把无 `package.json` 的 `.js` 当作 CommonJS，因此临时复制成 `.mjs` 再导入。
> Node treats a `.js` file without `package.json` as CommonJS, hence the temporary `.mjs` copy.

---

## 项目结构 · Project layout

```text
MoonOrbit/
├── moon.mod                     # MoonBit module manifest
├── PRD.md                       # product requirements
├── README.md                    # this document
├── LICENSE                      # MIT
├── cmd/main/                    # tiny CLI smoke entry
├── src/
│   ├── parser/                  # Markdown + wikilinks + tags
│   ├── graph/                   # NoteStore, backlinks, local BFS
│   ├── layout/                  # deterministic 2D orbital layout
│   └── bridge/                  # JSON API compiled to JS
├── web/
│   ├── index.html               # three-pane shell + folder tree + graph tools
│   ├── style.css                # light-paper design system
│   ├── app.js                   # vault model, import/export, orchestration
│   ├── explorer.js              # folder + .md document tree
│   ├── graph-view.js            # SVG graph, zoom/pan/hover/node dragging
│   └── bridge.js                # MoonBit build artifact (ES Module)
└── _build/                      # generated by moon (git-ignored)
```

---

## 设计取舍 · Design notes

**中文**

1. **为什么布局放在 MoonBit？** 布局是纯函数、边界条件多（小画布、单环、双环、节点拥挤），放在强类型语言里最容易测试。前端只消费坐标，避免两套几何逻辑漂移。
2. **为什么引擎无状态？** 每次请求重建索引，换来可重入、易测试、无隐藏状态的桥接层；笔记库很小，重建成本可忽略。
3. **为什么提交 `web/bridge.js`？** 黑客松演示需要“打开即用”。源码仍是唯一事实来源，重新构建即可覆盖。
4. **安全边界**：所有 Markdown 文本先转义再拼接 HTML；前端用 `textContent` 构建笔记列表、图例与提示，避免注入。
5. **确定性**：节点与边排序、角度分配都基于 id，图谱不会因输入顺序不同而跳动。

**English**

1. **Why is layout in MoonBit?** It is a pure function with many edge cases (small canvas, single ring, two rings, crowding). A typed implementation is easier to test; the shell consumes coordinates and never duplicates geometry.
2. **Why stateless?** Rebuilding the index per request keeps the bridge re-entrant and trivial to test. Vaults are small, so the cost is irrelevant.
3. **Why commit `web/bridge.js`?** Hackathon demos should open instantly. MoonBit sources remain the source of truth; rebuild to refresh.
4. **Security boundary**: Markdown text is escaped before HTML assembly; dynamic shell content uses `textContent`.
5. **Determinism**: Node/edge ordering and angular assignment depend only on ids, so the graph never jitters between equivalent inputs.

---

## 路线图 · Roadmap

- [ ] 表格、任务列表、脚注等扩展 Markdown 语法 / tables, task lists, footnotes
- [ ] 全文搜索高亮与标签筛选 / search highlighting and tag filters
- [x] 文件夹树与 `.md` 导入导出 / folder tree and `.md` import/export
- [x] 图谱节点自由拖拽 / free node dragging
- [ ] 节点固定与整库图谱 / pinning and whole-vault graph
- [ ] 全局图谱视图 / whole-vault graph view
- [ ] WebAssembly 目标与性能对比 / WASM target benchmark

---

## 开源协议 · License

**中文**

本项目采用 **MIT License** 发布。你可以自由使用、复制、修改、合并、发布、分发、再许可和销售本软件，但需在副本中保留版权声明与许可声明。软件按“原样”提供，不附带任何明示或默示担保。完整文本见 [LICENSE](./LICENSE)。

**English**

Released under the **MIT License**. You may use, copy, modify, merge, publish, distribute, sublicense and sell copies, provided the copyright and permission notice are included. The software is provided “as is”, without warranty of any kind. See [LICENSE](./LICENSE) for the full text.

---

## 致谢 · Acknowledgements

- [MoonBit](https://www.moonbitlang.com/) — 语言、标准库与 JS 后端 / language, standard library and JS backend.
- [MarkText](https://github.com/marktext/marktext) — 实时预览排版体验的灵感 / inspiration for the live-preview reading experience.
- [Obsidian](https://obsidian.md/) — 双链与局部图谱交互的灵感 / inspiration for wikilinks and local graphs.

---

**MoonOrbit · 月轨** — 让笔记沿着轨道彼此相连。
**MoonOrbit** — notes in orbit around each other.
