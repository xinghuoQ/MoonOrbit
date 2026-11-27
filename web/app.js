/**
 * MoonOrbit · 月轨 — web shell.
 *
 * Every Markdown parse, wikilink/tag extraction, backlink query, local graph
 * traversal and (x, y) layout coordinate comes from the MoonBit engine compiled
 * into ./bridge.js. This file owns DOM orchestration, the folder vault model,
 * local persistence and user interaction; the explorer tree and SVG graph live
 * in dedicated modules so each surface stays small and focused.
 */

import {
  compute_workspace_json,
  get_sample_notes_json,
  query_notes_json,
  render_markdown_json,
} from './bridge.js';
import { renderExplorer } from './explorer.js';
import { createGraphView } from './graph-view.js';

const STORAGE_KEY = 'moonorbit.vault.v1';
const SAMPLE_ACTIVE_ID = 'guide';
const DEFAULT_NOTE_TITLE = '未命名笔记';
const DEFAULT_FOLDER = '';
const COMPUTE_DEBOUNCE_MS = 120;
const RESIZE_DEBOUNCE_MS = 180;
const SAMPLE_EXPANDED_FOLDER = '01-快速开始';

const state = {
  notes: [],
  folders: [],
  activeId: null,
  depth: 1,
  search: '',
  viewMode: 'split',
  editorNoteId: null,
  workspace: null,
  graphSignature: null,
  tagCache: new Map(),
  allTags: [],
  activeTag: '',
  tagMatches: null,
  selectedFolder: DEFAULT_FOLDER,
  expandedFolders: new Set(),
};

const $ = (selector) => document.querySelector(selector);

const els = {
  searchInput: $('#search-input'),
  newNoteBtn: $('#new-note-btn'),
  newFolderBtn: $('#new-folder-btn'),
  importBtn: $('#import-btn'),
  importInput: $('#import-input'),
  exportBtn: $('#export-btn'),
  resetSampleBtn: $('#reset-sample-btn'),
  noteCount: $('#note-count'),
  tagBar: $('#tag-bar'),
  tagFilterState: $('#tag-filter-state'),
  folderTree: $('#folder-tree'),
  unresolvedCount: $('#unresolved-count'),
  unresolvedList: $('#unresolved-list'),
  engineStatus: $('#engine-status'),
  engineAlert: $('#engine-alert'),
  titleInput: $('#title-input'),
  folderSelect: $('#folder-select'),
  viewSwitch: $('.view-switch'),
  formatBar: $('.format-bar'),
  editorBody: $('#editor-body'),
  editor: $('#editor'),
  previewPane: $('.preview-pane'),
  preview: $('#preview'),
  backlinkCount: $('#backlink-count'),
  backlinkList: $('#backlink-list'),
  depthSwitch: $('.depth-switch'),
  graphZoomIn: $('#graph-zoom-in'),
  graphZoomOut: $('#graph-zoom-out'),
  graphReset: $('#graph-reset'),
  graphCanvas: $('#graph-canvas'),
  graphSvg: $('#graph-svg'),
  graphEmpty: $('#graph-empty'),
  graphMeta: $('#graph-meta'),
  toast: $('#toast'),
};

const graphView = createGraphView({
  svg: els.graphSvg,
  canvas: els.graphCanvas,
  emptyEl: els.graphEmpty,
  onActivate: activateGraphNode,
});

// ---------------------------------------------------------------------------
// Small utilities
// ---------------------------------------------------------------------------

function debounce(fn, wait) {
  let timer = null;
  return (...args) => {
    window.clearTimeout(timer);
    timer = window.setTimeout(() => {
      timer = null;
      fn(...args);
    }, wait);
  };
}

let toastTimer = null;

function toast(message) {
  els.toast.textContent = message;
  els.toast.classList.add('is-visible');
  window.clearTimeout(toastTimer);
  toastTimer = window.setTimeout(() => {
    els.toast.classList.remove('is-visible');
  }, 2400);
}

function normalizeFolder(value) {
  return typeof value === 'string' ? value : DEFAULT_FOLDER;
}

function isValidNote(note) {
  return (
    Boolean(note) &&
    typeof note.id === 'string' &&
    note.id.length > 0 &&
    typeof note.title === 'string' &&
    typeof note.content === 'string'
  );
}

function listEmpty(message) {
  const item = document.createElement('li');
  item.className = 'list-empty';
  item.textContent = message;
  return item;
}

function uniqueFolders(values) {
  const seen = new Set();
  const result = [];
  for (const value of values) {
    const folder = normalizeFolder(value).trim();
    if (folder && !seen.has(folder)) {
      seen.add(folder);
      result.push(folder);
    }
  }
  return result;
}

function allFolders() {
  return uniqueFolders([
    ...state.folders,
    ...state.notes.map((note) => note.folder),
  ]).sort((a, b) => a.localeCompare(b, 'zh-Hans-CN'));
}

function folderExists(folder) {
  if (folder === DEFAULT_FOLDER) return true;
  return allFolders().includes(folder);
}

function currentFolder() {
  return folderExists(state.selectedFolder)
    ? state.selectedFolder
    : DEFAULT_FOLDER;
}

function notesPayload() {
  return state.notes.map(({ id, title, content, folder }) => ({
    id,
    title,
    content,
    folder,
  }));
}

// ---------------------------------------------------------------------------
// Vault persistence
// ---------------------------------------------------------------------------

function restoreVault() {
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const data = JSON.parse(raw);
    if (!data || !Array.isArray(data.notes)) return null;
    const seen = new Set();
    const notes = data.notes
      .filter(isValidNote)
      .filter((note) => {
        if (seen.has(note.id)) return false;
        seen.add(note.id);
        return true;
      })
      .map((note) => ({
        id: note.id,
        title: note.title,
        content: note.content,
        folder: normalizeFolder(note.folder).trim(),
      }));
    if (notes.length === 0) return null;
    const activeId = notes.some((note) => note.id === data.activeId)
      ? data.activeId
      : notes[0].id;
    return {
      notes,
      folders: uniqueFolders(Array.isArray(data.folders) ? data.folders : []),
      activeId,
      depth: data.depth === 2 ? 2 : 1,
      selectedFolder: normalizeFolder(data.selectedFolder),
      expandedFolders: Array.isArray(data.expandedFolders)
        ? data.expandedFolders.filter((name) => typeof name === 'string')
        : [],
    };
  } catch (error) {
    console.warn('无法读取本地笔记库，改用示例笔记。', error);
    return null;
  }
}

function persist() {
  try {
    window.localStorage.setItem(
      STORAGE_KEY,
      JSON.stringify({
        version: 2,
        notes: state.notes,
        folders: state.folders,
        activeId: state.activeId,
        depth: state.depth,
        selectedFolder: state.selectedFolder,
        expandedFolders: [...state.expandedFolders],
      }),
    );
  } catch (error) {
    console.warn('无法写入本地笔记库。', error);
  }
}

function readSampleNotes() {
  try {
    const parsed = JSON.parse(get_sample_notes_json());
    if (Array.isArray(parsed)) {
      const notes = parsed.filter(isValidNote).map((note) => ({
        id: note.id,
        title: note.title,
        content: note.content,
        folder: normalizeFolder(note.folder),
      }));
      if (notes.length > 0) return notes;
    }
  } catch (error) {
    console.error('MoonBit 示例笔记解析失败。', error);
  }
  return [
    {
      id: 'welcome',
      title: '欢迎使用 MoonOrbit',
      content:
        '# 欢迎使用 MoonOrbit\n\nMoonBit 引擎暂时没有返回示例笔记，请点击「重置示例」重试。\n',
      folder: DEFAULT_FOLDER,
    },
  ];
}

// ---------------------------------------------------------------------------
// Note and folder helpers
// ---------------------------------------------------------------------------

function activeNote() {
  return state.notes.find((note) => note.id === state.activeId) || null;
}

function noteByTitle(title) {
  return state.notes.find((note) => note.title === title) || null;
}

function makeNoteId() {
  let id = '';
  do {
    id = `note-${Date.now().toString(36)}-${Math.random()
      .toString(36)
      .slice(2, 8)}`;
  } while (state.notes.some((note) => note.id === id));
  return id;
}

function makeNote(title, content, folder = DEFAULT_FOLDER) {
  return {
    id: makeNoteId(),
    title,
    content: content === undefined ? `# ${title}\n\n` : content,
    folder: normalizeFolder(folder).trim(),
  };
}

function uniqueTitle(base, excludeId = null) {
  const clean = (base || '').trim() || DEFAULT_NOTE_TITLE;
  let candidate = clean;
  let suffix = 2;
  while (
    state.notes.some(
      (note) => note.id !== excludeId && note.title === candidate,
    )
  ) {
    candidate = `${clean} ${suffix}`;
    suffix += 1;
  }
  return candidate;
}

function ensureActiveNote() {
  if (state.notes.length === 0) {
    const fallback = makeNote(
      DEFAULT_NOTE_TITLE,
      `# ${DEFAULT_NOTE_TITLE}\n\n`,
      currentFolder(),
    );
    state.notes = [fallback];
    state.activeId = fallback.id;
  } else if (!state.notes.some((note) => note.id === state.activeId)) {
    state.activeId = state.notes[0].id;
  }
}

function updateNote(id, patch) {
  state.notes = state.notes.map((note) =>
    note.id === id ? { ...note, ...patch } : note,
  );
}

function refreshTagCache() {
  state.tagCache.clear();
  for (const note of state.notes) {
    try {
      const parsed = JSON.parse(render_markdown_json(note.content));
      state.tagCache.set(
        note.id,
        Array.isArray(parsed.tags) ? parsed.tags : [],
      );
    } catch (error) {
      console.warn(`无法解析笔记「${note.title}」的标签。`, error);
      state.tagCache.set(note.id, []);
    }
  }
}

// ---------------------------------------------------------------------------
// Editor / vault actions
// ---------------------------------------------------------------------------

function updateFolderSelect() {
  const note = activeNote();
  const folders = allFolders();
  const fragment = document.createDocumentFragment();

  const rootOption = document.createElement('option');
  rootOption.value = DEFAULT_FOLDER;
  rootOption.textContent = '📁 根目录';
  fragment.appendChild(rootOption);

  for (const folder of folders) {
    const option = document.createElement('option');
    option.value = folder;
    option.textContent = `📁 ${folder}`;
    fragment.appendChild(option);
  }

  els.folderSelect.replaceChildren(fragment);
  els.folderSelect.value =
    note && folders.includes(note.folder) ? note.folder : DEFAULT_FOLDER;
}

function loadEditor({ force = false } = {}) {
  const note = activeNote();
  if (!note) return;
  if (force || state.editorNoteId !== note.id) {
    els.titleInput.value = note.title;
    els.editor.value = note.content;
    state.editorNoteId = note.id;
  }
  updateFolderSelect();
}

function selectNote(id) {
  const note = state.notes.find((item) => item.id === id);
  if (!note) return;
  const changed = state.activeId !== id;
  state.activeId = id;
  state.selectedFolder = normalizeFolder(note.folder);
  state.expandedFolders.add(state.selectedFolder);
  if (changed) {
    state.graphSignature = null;
    loadEditor({ force: true });
  }
  persist();
  renderTree();
  computeAndRender();
  if (changed) {
    els.previewPane.scrollTop = 0;
    els.editor.scrollTop = 0;
  }
}

function createNote(title, options = {}) {
  const { exact = false, content, select = true, folder } = options;
  // A brand-new document should always be visible, even when a tag filter was
  // hiding parts of the vault a moment ago.
  state.activeTag = '';
  state.tagMatches = null;
  const targetFolder =
    folder === undefined ? currentFolder() : normalizeFolder(folder);
  const finalTitle = exact
    ? (title || '').trim() || DEFAULT_NOTE_TITLE
    : uniqueTitle(title);
  const note = makeNote(finalTitle, content, targetFolder);
  state.notes = [...state.notes, note];
  state.selectedFolder = targetFolder;
  state.expandedFolders.add(targetFolder);
  if (select) {
    selectNote(note.id);
  } else {
    persist();
    renderTree();
    updateFolderSelect();
    computeAndRender();
  }
  return note;
}

function openByTitle(title) {
  const existing = noteByTitle(title);
  if (existing) {
    selectNote(existing.id);
    return;
  }
  const note = createNote(title, {
    exact: true,
    content: `# ${title}\n\n`,
    select: true,
    folder: currentFolder(),
  });
  toast(`已创建笔记「${note.title}」`);
}

function deleteNote(id) {
  const index = state.notes.findIndex((note) => note.id === id);
  if (index < 0) return;
  const note = state.notes[index];
  const confirmed = window.confirm(
    `确定删除文档「${note.title}.md」吗？引用它的双链会变成未创建节点。`,
  );
  if (!confirmed) return;

  const wasActive = state.activeId === id;
  state.notes = state.notes.filter((item) => item.id !== id);
  state.tagCache.delete(id);

  if (state.notes.length === 0) {
    const fallback = makeNote(
      DEFAULT_NOTE_TITLE,
      `# ${DEFAULT_NOTE_TITLE}\n\n`,
      currentFolder(),
    );
    state.notes = [fallback];
    state.activeId = fallback.id;
  } else if (wasActive) {
    state.activeId = state.notes[Math.min(index, state.notes.length - 1)].id;
  }

  if (wasActive) {
    state.graphSignature = null;
    loadEditor({ force: true });
    els.previewPane.scrollTop = 0;
    els.editor.scrollTop = 0;
  }
  persist();
  renderTree();
  updateFolderSelect();
  computeAndRender();
  toast(`已删除「${note.title}.md」`);
}

function moveNoteToFolder(id, folder) {
  const note = state.notes.find((item) => item.id === id);
  if (!note) return;
  const target = normalizeFolder(folder).trim();
  if (note.folder === target) return;
  updateNote(id, { folder: target });
  state.selectedFolder = target;
  state.expandedFolders.add(target);
  persist();
  renderTree();
  updateFolderSelect();
  computeAndRender();
  toast(target ? `已移动到「${target}」` : '已移动到根目录');
}

function normalizeActiveTitle() {
  const note = activeNote();
  if (!note) return;
  const normalized = uniqueTitle(note.title, note.id);
  if (note.title !== normalized) {
    updateNote(note.id, { title: normalized });
    els.titleInput.value = normalized;
    persist();
    renderTree();
    scheduleCompute();
  }
}

// ---------------------------------------------------------------------------
// Folder actions
// ---------------------------------------------------------------------------

function createFolder() {
  const entered = window.prompt('新建文件夹名称（例如 01-快速开始）', '');
  if (entered === null) return;
  const name = entered.trim();
  if (!name) {
    toast('文件夹名称不能为空');
    return;
  }
  if (allFolders().includes(name)) {
    toast('同名文件夹已存在');
    return;
  }
  state.folders = uniqueFolders([...state.folders, name]);
  state.expandedFolders.add(name);
  state.selectedFolder = name;
  persist();
  renderTree();
  updateFolderSelect();
  computeAndRender();
  toast(`已新建文件夹「${name}」`);
}

function renameFolder(folder) {
  const entered = window.prompt('重命名文件夹', folder);
  if (entered === null) return;
  const name = entered.trim();
  if (!name) {
    toast('文件夹名称不能为空');
    return;
  }
  if (name === folder) return;
  if (allFolders().includes(name)) {
    toast('同名文件夹已存在');
    return;
  }
  state.notes = state.notes.map((note) =>
    note.folder === folder ? { ...note, folder: name } : note,
  );
  state.folders = uniqueFolders(
    state.folders.map((item) => (item === folder ? name : item)),
  );
  if (state.expandedFolders.has(folder)) {
    state.expandedFolders.delete(folder);
    state.expandedFolders.add(name);
  }
  if (state.selectedFolder === folder) {
    state.selectedFolder = name;
  }
  persist();
  renderTree();
  updateFolderSelect();
  computeAndRender();
  toast(`文件夹已重命名为「${name}」`);
}

function deleteFolder(folder) {
  const affected = state.notes.filter(
    (note) => note.folder === folder,
  ).length;
  const confirmed = window.confirm(
    affected > 0
      ? `删除文件夹「${folder}」？其中 ${affected} 篇文档将移动到根目录。`
      : `删除空文件夹「${folder}」？`,
  );
  if (!confirmed) return;
  state.notes = state.notes.map((note) =>
    note.folder === folder ? { ...note, folder: DEFAULT_FOLDER } : note,
  );
  state.folders = state.folders.filter((item) => item !== folder);
  state.expandedFolders.delete(folder);
  if (state.selectedFolder === folder) {
    state.selectedFolder = DEFAULT_FOLDER;
  }
  persist();
  renderTree();
  updateFolderSelect();
  computeAndRender();
  toast(`已删除文件夹「${folder}」`);
}

function toggleFolder(folder) {
  if (state.expandedFolders.has(folder)) {
    state.expandedFolders.delete(folder);
  } else {
    state.expandedFolders.add(folder);
  }
  persist();
  renderTree();
}

function selectFolder(folder) {
  state.selectedFolder = normalizeFolder(folder);
  state.expandedFolders.add(state.selectedFolder);
  persist();
  renderTree();
}

// ---------------------------------------------------------------------------
// Markdown import / export
// ---------------------------------------------------------------------------

function stripMarkdownExtension(filename) {
  return filename.replace(/\.md$/i, '').trim();
}

async function importMarkdownFiles(fileList) {
  const files = Array.from(fileList).filter((file) => /\.md$/i.test(file.name));
  if (files.length === 0) {
    toast('请选择 .md 文件');
    return;
  }

  const folder = currentFolder();
  const imported = [];
  state.activeTag = '';
  state.tagMatches = null;
  for (const file of files) {
    try {
      const text = await file.text();
      const base = stripMarkdownExtension(file.name) || DEFAULT_NOTE_TITLE;
      const title = uniqueTitle(base);
      const note = makeNote(title, text, folder);
      state.notes = [...state.notes, note];
      imported.push(note);
    } catch (error) {
      console.warn(`导入「${file.name}」失败。`, error);
    }
  }

  if (imported.length === 0) {
    toast('没有成功导入任何 .md 文件');
    return;
  }

  state.activeId = imported[0].id;
  state.selectedFolder = folder;
  state.expandedFolders.add(folder);
  state.graphSignature = null;
  persist();
  refreshTagCache();
  loadEditor({ force: true });
  renderTree();
  updateFolderSelect();
  computeAndRender();
  toast(`已导入 ${imported.length} 篇 .md 文档`);
}

function newDocument() {
  const note = createNote(DEFAULT_NOTE_TITLE, { select: true });
  els.titleInput.focus();
  els.titleInput.select();
  toast(`已新建「${note.title}.md」`);
}

function exportActiveNote() {
  const note = activeNote();
  if (!note) return;
  const safeName =
    (note.title || DEFAULT_NOTE_TITLE)
      .replace(/[\\/:*?"<>|]/g, '_')
      .trim() || DEFAULT_NOTE_TITLE;
  const blob = new Blob([note.content], {
    type: 'text/markdown;charset=utf-8',
  });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = `${safeName}.md`;
  document.body.appendChild(link);
  link.click();
  link.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 1200);
  toast(`已导出「${safeName}.md」`);
}

// ---------------------------------------------------------------------------
// MoonBit workspace request
// ---------------------------------------------------------------------------

function graphCanvasSize() {
  const width = Math.round(els.graphCanvas.clientWidth || 0);
  const height = Math.round(els.graphCanvas.clientHeight || 0);
  return {
    width: width > 0 ? width : 600,
    height: height > 0 ? height : 400,
  };
}

function showEngineError(error) {
  const message = error instanceof Error ? error.message : String(error);
  console.error('[MoonOrbit] MoonBit 引擎错误:', error);
  els.engineAlert.textContent = `MoonBit 引擎错误：${message}`;
  els.engineAlert.hidden = false;
  toast('MoonBit 引擎返回错误');
}

function clearEngineError() {
  if (!els.engineAlert.hidden) {
    els.engineAlert.hidden = true;
    els.engineAlert.textContent = '';
  }
}

// ---------------------------------------------------------------------------
// Tag filter (MoonBit query_notes_json)
// ---------------------------------------------------------------------------

function renderTagBar() {
  const fragment = document.createDocumentFragment();

  const allChip = document.createElement('button');
  allChip.type = 'button';
  allChip.className = `tag-chip${state.activeTag ? '' : ' is-active'}`;
  allChip.textContent = '全部';
  allChip.title = '显示全部文档';
  allChip.setAttribute('aria-pressed', String(!state.activeTag));
  allChip.addEventListener('click', () => setActiveTag(''));
  fragment.appendChild(allChip);

  for (const tag of state.allTags) {
    const chip = document.createElement('button');
    chip.type = 'button';
    const isActive = state.activeTag === tag;
    chip.className = `tag-chip${isActive ? ' is-active' : ''}`;
    chip.textContent = `#${tag}`;
    chip.title = `按标签 #${tag} 筛选（再次点击取消）`;
    chip.setAttribute('aria-pressed', String(isActive));
    chip.addEventListener('click', () => setActiveTag(tag));
    fragment.appendChild(chip);
  }

  if (state.allTags.length === 0) {
    const empty = document.createElement('span');
    empty.className = 'tag-empty';
    empty.textContent = '暂无标签';
    fragment.appendChild(empty);
  }

  els.tagBar.replaceChildren(fragment);
  els.tagFilterState.textContent = state.activeTag
    ? `#${state.activeTag}`
    : '全部';
}

function refreshQueryState() {
  let data;
  try {
    data = JSON.parse(
      query_notes_json(
        JSON.stringify({
          notes: notesPayload(),
          query: '',
          tag: state.activeTag,
        }),
      ),
    );
  } catch (error) {
    console.warn('MoonBit 标签查询失败。', error);
    return;
  }
  if (!data || data.ok !== true) {
    console.warn(
      'MoonBit 标签查询返回错误。',
      data && data.error ? data.error : '未知错误',
    );
    return;
  }
  state.allTags = Array.isArray(data.tags) ? data.tags : [];
  state.tagMatches = state.activeTag
    ? new Set(Array.isArray(data.matches) ? data.matches : [])
    : null;
  renderTagBar();
}

function setActiveTag(tag) {
  state.activeTag = tag === state.activeTag ? '' : tag;
  // Every chip click re-asks the MoonBit engine for the matching note ids.
  refreshQueryState();
  renderTree();
}

function renderTree() {
  const visibleNotes = state.tagMatches
    ? state.notes.filter((note) => state.tagMatches.has(note.id))
    : state.notes;

  renderExplorer(els.folderTree, {
    notes: visibleNotes,
    folders: allFolders(),
    activeId: state.activeId,
    selectedFolder: state.selectedFolder,
    expanded: state.expandedFolders,
    tagCache: state.tagCache,
    query: state.search,
    callbacks: {
      onOpenNote: selectNote,
      onDeleteNote: deleteNote,
      onSelectFolder: selectFolder,
      onToggleFolder: toggleFolder,
      onRenameFolder: renameFolder,
      onDeleteFolder: deleteFolder,
    },
  });

  if (state.activeTag) {
    els.noteCount.textContent = `${visibleNotes.length} / ${state.notes.length}`;
  } else if (state.search) {
    els.noteCount.textContent = `${state.notes.length} 篇 · 搜索中`;
  } else {
    els.noteCount.textContent = String(state.notes.length);
  }
}

function computeAndRender() {
  const note = activeNote();
  if (!note) return;

  const size = graphCanvasSize();
  const request = {
    notes: notesPayload(),
    folders: allFolders(),
    active_id: note.id,
    depth: state.depth,
    width: size.width,
    height: size.height,
  };

  let data;
  try {
    data = JSON.parse(compute_workspace_json(JSON.stringify(request)));
  } catch (error) {
    showEngineError(error);
    return;
  }

  if (!data || data.ok !== true) {
    showEngineError(data && data.error ? data.error : '未知引擎错误');
    return;
  }

  clearEngineError();
  const layout = data.layout || null;
  const signature = layout
    ? `${layout.center_id}:${layout.width}x${layout.height}:${state.depth}`
    : null;
  const preserveView = signature !== null && signature === state.graphSignature;

  state.workspace = data;
  state.graphSignature = signature;
  state.tagCache.set(note.id, data.active_render.tags || []);
  refreshQueryState();

  renderTree();
  renderPreview(data.active_render.html);
  renderBacklinks(data.backlinks || []);
  renderUnresolved(data.unresolved_links || []);
  graphView.setLayout(layout, { preserveView });
  els.graphMeta.textContent = layout
    ? `${layout.nodes.length} 节点 · ${layout.edges.length} 连线 · ${state.depth} 跳`
    : `0 节点 · 0 连线 · ${state.depth} 跳`;
  els.engineStatus.textContent = `MoonBit 引擎在线 · ${state.notes.length} 篇文档 · ${allFolders().length} 个文件夹`;
}

const scheduleCompute = debounce(computeAndRender, COMPUTE_DEBOUNCE_MS);

// ---------------------------------------------------------------------------
// Rendering — navigation, preview, backlinks
// ---------------------------------------------------------------------------

function renderUnresolved(titles) {
  els.unresolvedCount.textContent = String(titles.length);
  const fragment = document.createDocumentFragment();
  if (titles.length === 0) {
    fragment.appendChild(listEmpty('没有未创建链接'));
  }

  for (const title of titles) {
    const item = document.createElement('li');
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'ghost-link';
    button.dataset.title = title;
    button.title = `一键创建「${title}」`;

    const mark = document.createElement('span');
    mark.className = 'ghost-mark';
    const label = document.createElement('span');
    label.className = 'ghost-title';
    label.textContent = title;
    const plus = document.createElement('span');
    plus.className = 'ghost-plus';
    plus.textContent = '+';

    button.append(mark, label, plus);
    item.appendChild(button);
    fragment.appendChild(item);
  }

  els.unresolvedList.replaceChildren(fragment);
}

function renderBacklinks(backlinks) {
  els.backlinkCount.textContent = String(backlinks.length);
  const fragment = document.createDocumentFragment();
  if (backlinks.length === 0) {
    fragment.appendChild(listEmpty('暂无反向链接'));
  }

  for (const backlink of backlinks) {
    const item = document.createElement('li');
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'backlink-chip';
    button.dataset.id = backlink.id;
    button.textContent = backlink.title;
    button.title = backlink.folder
      ? `跳转到「${backlink.title}」（${backlink.folder}）`
      : `跳转到「${backlink.title}」`;
    item.appendChild(button);
    fragment.appendChild(item);
  }

  els.backlinkList.replaceChildren(fragment);
}

function renderPreview(html) {
  const scrollTop = els.previewPane.scrollTop;
  // The MoonBit Markdown renderer escapes every text and attribute value it
  // emits (see src/parser/parser.mbt `write_escaped`/`escape_attr`), so this
  // HTML is produced by our own trusted engine rather than raw user input.
  els.preview.innerHTML =
    html || '<p class="preview-empty">开始输入 Markdown…</p>';
  els.previewPane.scrollTop = scrollTop;
}

// ---------------------------------------------------------------------------
// Formatting toolbar
// ---------------------------------------------------------------------------

function notifyEditorChanged() {
  els.editor.dispatchEvent(new Event('input', { bubbles: true }));
  els.editor.focus();
}

function wrapSelection(prefix, suffix, placeholder) {
  const editor = els.editor;
  const start = editor.selectionStart;
  const end = editor.selectionEnd;
  const selected = editor.value.slice(start, end);
  const inner = selected || placeholder;
  editor.setRangeText(prefix + inner + suffix, start, end, 'end');
  editor.setSelectionRange(
    start + prefix.length,
    start + prefix.length + inner.length,
  );
  notifyEditorChanged();
}

function insertHeading() {
  const editor = els.editor;
  const lineStart =
    editor.value.lastIndexOf('\n', editor.selectionStart - 1) + 1;
  editor.setRangeText('## ', lineStart, lineStart, 'end');
  notifyEditorChanged();
}

function insertCodeBlock() {
  const editor = els.editor;
  const start = editor.selectionStart;
  const end = editor.selectionEnd;
  const selected = editor.value.slice(start, end) || '在这里输入代码';
  const needsLeadingNewline = start > 0 && editor.value[start - 1] !== '\n';
  const prefix = `${needsLeadingNewline ? '\n' : ''}\`\`\`\n`;
  const suffix = '\n```\n';
  editor.setRangeText(prefix + selected + suffix, start, end, 'end');
  const innerStart = start + prefix.length;
  editor.setSelectionRange(innerStart, innerStart + selected.length);
  notifyEditorChanged();
}

function applyFormat(action) {
  switch (action) {
    case 'heading':
      insertHeading();
      break;
    case 'bold':
      wrapSelection('**', '**', '粗体文本');
      break;
    case 'italic':
      wrapSelection('*', '*', '斜体文本');
      break;
    case 'code':
      insertCodeBlock();
      break;
    case 'wikilink':
      wrapSelection('[[', ']]', '目标笔记');
      break;
    default:
      break;
  }
}

// ---------------------------------------------------------------------------
// View state
// ---------------------------------------------------------------------------

function setViewMode(mode) {
  const allowed = ['split', 'edit', 'preview'];
  state.viewMode = allowed.includes(mode) ? mode : 'split';
  els.editorBody.dataset.mode = state.viewMode;
  for (const button of els.viewSwitch.querySelectorAll('button[data-mode]')) {
    const isActive = button.dataset.mode === state.viewMode;
    button.classList.toggle('is-active', isActive);
    button.setAttribute('aria-pressed', String(isActive));
  }
}

function updateDepthButtons() {
  for (const button of els.depthSwitch.querySelectorAll('button[data-depth]')) {
    const isActive = Number(button.dataset.depth) === state.depth;
    button.classList.toggle('is-active', isActive);
    button.setAttribute('aria-pressed', String(isActive));
  }
}

// ---------------------------------------------------------------------------
// Graph activation
// ---------------------------------------------------------------------------

function activateGraphNode(node) {
  if (node.exists) {
    selectNote(node.id);
  } else {
    openByTitle(node.title);
  }
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

function bindEvents() {
  els.searchInput.addEventListener('input', () => {
    state.search = els.searchInput.value.trim();
    renderTree();
  });

  els.newNoteBtn.addEventListener('click', newDocument);

  els.newFolderBtn.addEventListener('click', createFolder);
  els.importBtn.addEventListener('click', () => els.importInput.click());
  els.importInput.addEventListener('change', async () => {
    const files = els.importInput.files;
    if (files && files.length > 0) {
      await importMarkdownFiles(files);
    }
    els.importInput.value = '';
  });
  els.exportBtn.addEventListener('click', exportActiveNote);

  els.resetSampleBtn.addEventListener('click', () => {
    const confirmed = window.confirm(
      '重置示例笔记库？当前所有文档与文件夹将被替换为 3 个文件夹中的 6 篇示例。',
    );
    if (!confirmed) return;
    const sample = readSampleNotes();
    state.notes = sample;
    state.folders = uniqueFolders(sample.map((note) => note.folder));
    state.activeId = sample.some((note) => note.id === SAMPLE_ACTIVE_ID)
      ? SAMPLE_ACTIVE_ID
      : sample[0].id;
    state.depth = 1;
    state.search = '';
    state.editorNoteId = null;
    state.graphSignature = null;
    state.activeTag = '';
    state.tagMatches = null;
    state.selectedFolder = SAMPLE_EXPANDED_FOLDER;
    state.expandedFolders = new Set(state.folders);
    els.searchInput.value = '';
    persist();
    refreshTagCache();
    updateDepthButtons();
    loadEditor({ force: true });
    renderTree();
    computeAndRender();
    toast('示例笔记库已恢复');
  });

  els.titleInput.addEventListener('input', () => {
    const note = activeNote();
    if (!note) return;
    updateNote(note.id, { title: els.titleInput.value });
    persist();
    renderTree();
    scheduleCompute();
  });

  els.titleInput.addEventListener('blur', normalizeActiveTitle);
  els.titleInput.addEventListener('keydown', (event) => {
    if (event.key === 'Enter') {
      event.preventDefault();
      els.titleInput.blur();
    }
  });

  els.folderSelect.addEventListener('change', () => {
    const note = activeNote();
    if (!note) return;
    moveNoteToFolder(note.id, els.folderSelect.value);
  });

  els.editor.addEventListener('input', () => {
    const note = activeNote();
    if (!note) return;
    updateNote(note.id, { content: els.editor.value });
    persist();
    scheduleCompute();
  });

  els.editor.addEventListener('keydown', (event) => {
    if (!(event.ctrlKey || event.metaKey)) return;
    const key = event.key.toLowerCase();
    if (key === 'b') {
      event.preventDefault();
      wrapSelection('**', '**', '粗体文本');
    } else if (key === 'i') {
      event.preventDefault();
      wrapSelection('*', '*', '斜体文本');
    }
  });

  els.viewSwitch.addEventListener('click', (event) => {
    const button = event.target.closest('button[data-mode]');
    if (!button) return;
    setViewMode(button.dataset.mode);
  });

  els.formatBar.addEventListener('click', (event) => {
    const button = event.target.closest('button[data-format]');
    if (!button) return;
    applyFormat(button.dataset.format);
  });

  els.preview.addEventListener('click', (event) => {
    const link = event.target.closest('a.wiki-link');
    if (!link) return;
    event.preventDefault();
    openByTitle(link.dataset.target);
  });

  els.backlinkList.addEventListener('click', (event) => {
    const button = event.target.closest('button[data-id]');
    if (!button) return;
    selectNote(button.dataset.id);
  });

  els.unresolvedList.addEventListener('click', (event) => {
    const button = event.target.closest('button[data-title]');
    if (!button) return;
    openByTitle(button.dataset.title);
  });

  els.depthSwitch.addEventListener('click', (event) => {
    const button = event.target.closest('button[data-depth]');
    if (!button) return;
    const depth = Number(button.dataset.depth) === 2 ? 2 : 1;
    if (depth === state.depth) return;
    state.depth = depth;
    state.graphSignature = null;
    persist();
    updateDepthButtons();
    computeAndRender();
  });

  els.graphZoomIn.addEventListener('click', () => graphView.zoomIn());
  els.graphZoomOut.addEventListener('click', () => graphView.zoomOut());
  els.graphReset.addEventListener('click', () => graphView.reset());
}

function bindGlobalShortcuts() {
  document.addEventListener('keydown', (event) => {
    if (!(event.ctrlKey || event.metaKey) || event.altKey) return;
    if (event.defaultPrevented) return;
    const key = event.key.toLowerCase();
    if (key === 's') {
      event.preventDefault();
      exportActiveNote();
    } else if (key === 'n') {
      event.preventDefault();
      newDocument();
    }
  });
}

function observeGraphResize() {
  const onResize = debounce(() => {
    state.graphSignature = null;
    computeAndRender();
  }, RESIZE_DEBOUNCE_MS);

  if (typeof ResizeObserver === 'undefined') {
    window.addEventListener('resize', onResize);
    return;
  }

  let lastWidth = -1;
  let lastHeight = -1;
  const observer = new ResizeObserver((entries) => {
    const rect = entries[0] && entries[0].contentRect;
    if (!rect) return;
    if (
      Math.abs(rect.width - lastWidth) < 2 &&
      Math.abs(rect.height - lastHeight) < 2
    ) {
      return;
    }
    lastWidth = rect.width;
    lastHeight = rect.height;
    onResize();
  });
  observer.observe(els.graphCanvas);
}

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------

function boot() {
  bindEvents();
  bindGlobalShortcuts();
  const restored = restoreVault();

  if (restored) {
    state.notes = restored.notes;
    state.folders = restored.folders;
    state.activeId = restored.activeId;
    state.depth = restored.depth;
    state.selectedFolder = restored.selectedFolder;
    state.expandedFolders = new Set(restored.expandedFolders);
  } else {
    const sample = readSampleNotes();
    state.notes = sample;
    state.folders = uniqueFolders(sample.map((note) => note.folder));
    state.activeId = SAMPLE_ACTIVE_ID;
    state.depth = 1;
    state.selectedFolder = SAMPLE_EXPANDED_FOLDER;
    state.expandedFolders = new Set(state.folders);
    persist();
  }

  ensureActiveNote();
  const active = activeNote();
  if (active) {
    state.selectedFolder = normalizeFolder(active.folder);
    state.expandedFolders.add(state.selectedFolder);
  }
  refreshTagCache();
  updateDepthButtons();
  setViewMode(state.viewMode);
  loadEditor({ force: true });
  renderTree();
  computeAndRender();
  observeGraphResize();

  if (!restored) {
    window.setTimeout(() => {
      toast('已载入 3 个文件夹 · 试试拖拽右侧图谱节点');
    }, 600);
  }
}

boot();
