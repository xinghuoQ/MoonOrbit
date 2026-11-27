/**
 * MoonOrbit · 月轨 — folder + Markdown document explorer.
 *
 * The tree is a pure projection of the app state. Every interaction is
 * reported through callbacks so `app.js` remains the single owner of notes,
 * folders and persistence.
 */

const ROOT_LABEL = '根目录';

function noteTags(note, tagCache) {
  return tagCache.get(note.id) || [];
}

function matchesSearch(note, query, tagCache) {
  if (!query) return true;
  const lower = query.toLowerCase();
  if (note.title.toLowerCase().includes(lower)) return true;
  if (note.content.toLowerCase().includes(lower)) return true;
  return noteTags(note, tagCache).some((tag) =>
    tag.toLowerCase().includes(lower),
  );
}

function makeIcon(className, glyph) {
  const span = document.createElement('span');
  span.className = className;
  span.setAttribute('aria-hidden', 'true');
  span.textContent = glyph;
  return span;
}

function makeNoteRow(note, model) {
  const { activeId, tagCache, callbacks } = model;
  const item = document.createElement('li');
  item.className = `tree-note${note.id === activeId ? ' is-active' : ''}`;

  const open = document.createElement('button');
  open.type = 'button';
  open.className = 'tree-note-open';
  open.title = `打开「${note.title}」`;
  open.setAttribute('aria-label', `打开文档 ${note.title}.md`);
  open.addEventListener('click', () => callbacks.onOpenNote(note.id));

  open.appendChild(makeIcon('tree-note-icon', '📄'));

  const name = document.createElement('span');
  name.className = 'tree-note-name';
  name.textContent = `${note.title || '未命名笔记'}.md`;
  open.appendChild(name);

  const tags = noteTags(note, tagCache);
  if (tags.length > 0) {
    const badge = document.createElement('span');
    badge.className = 'tree-note-badge';
    badge.title = tags.map((tag) => `#${tag}`).join(' ');
    badge.textContent = `#${tags.length}`;
    open.appendChild(badge);
  }

  const remove = document.createElement('button');
  remove.type = 'button';
  remove.className = 'tree-note-delete';
  remove.textContent = '×';
  remove.title = `删除「${note.title}」`;
  remove.setAttribute('aria-label', `删除文档 ${note.title}.md`);
  remove.addEventListener('click', (event) => {
    event.stopPropagation();
    callbacks.onDeleteNote(note.id);
  });

  item.append(open, remove);
  return item;
}

function makeFolderRow(folder, notes, model) {
  const { selectedFolder, expanded, query, callbacks } = model;
  const isRoot = folder === '';
  const isExpanded = Boolean(query) || expanded.has(folder);

  const item = document.createElement('li');
  item.className = `tree-folder${folder === selectedFolder ? ' is-selected' : ''}`;
  item.dataset.folder = folder;

  const row = document.createElement('div');
  row.className = 'tree-folder-row';

  const toggle = document.createElement('button');
  toggle.type = 'button';
  toggle.className = `tree-toggle${isExpanded ? ' is-open' : ''}`;
  toggle.textContent = isExpanded ? '▾' : '▸';
  toggle.title = isExpanded ? '折叠文件夹' : '展开文件夹';
  toggle.setAttribute('aria-expanded', String(isExpanded));
  toggle.addEventListener('click', (event) => {
    event.stopPropagation();
    callbacks.onToggleFolder(folder);
  });
  row.appendChild(toggle);

  row.appendChild(makeIcon('tree-folder-icon', '📁'));

  const name = document.createElement('button');
  name.type = 'button';
  name.className = 'tree-folder-name';
  name.textContent = isRoot ? ROOT_LABEL : folder;
  name.title = isRoot ? '根目录（新增文档默认位置）' : folder;
  name.addEventListener('click', () => {
    callbacks.onSelectFolder(folder);
    callbacks.onToggleFolder(folder);
  });
  row.appendChild(name);

  const count = document.createElement('span');
  count.className = 'tree-count';
  count.textContent = String(notes.length);
  row.appendChild(count);

  if (!isRoot) {
    const actions = document.createElement('span');
    actions.className = 'tree-folder-actions';

    const rename = document.createElement('button');
    rename.type = 'button';
    rename.className = 'tree-folder-action';
    rename.textContent = '✎';
    rename.title = `重命名文件夹「${folder}」`;
    rename.setAttribute('aria-label', `重命名文件夹 ${folder}`);
    rename.addEventListener('click', (event) => {
      event.stopPropagation();
      callbacks.onRenameFolder(folder);
    });
    actions.appendChild(rename);

    const remove = document.createElement('button');
    remove.type = 'button';
    remove.className = 'tree-folder-action is-danger';
    remove.textContent = '×';
    remove.title = `删除文件夹「${folder}」`;
    remove.setAttribute('aria-label', `删除文件夹 ${folder}`);
    remove.addEventListener('click', (event) => {
      event.stopPropagation();
      callbacks.onDeleteFolder(folder);
    });
    actions.appendChild(remove);

    row.appendChild(actions);
  }

  item.appendChild(row);

  if (isExpanded) {
    const list = document.createElement('ul');
    list.className = 'tree-notes';
    if (notes.length === 0) {
      const empty = document.createElement('li');
      empty.className = 'tree-empty';
      empty.textContent = '空文件夹';
      list.appendChild(empty);
    } else {
      for (const note of notes) {
        list.appendChild(makeNoteRow(note, model));
      }
    }
    item.appendChild(list);
  }

  return item;
}

/**
 * @param {HTMLElement} container
 * @param {{
 *   notes: Array<object>,
 *   folders: Array<string>,
 *   activeId: string | null,
 *   selectedFolder: string,
 *   expanded: Set<string>,
 *   tagCache: Map<string, string[]>,
 *   query: string,
 *   callbacks: object,
 * }} model
 */
export function renderExplorer(container, model) {
  const { notes, folders, query, tagCache } = model;
  const fragment = document.createDocumentFragment();

  const visible = notes.filter((note) => matchesSearch(note, query, tagCache));
  const rootNotes = visible.filter((note) => !note.folder);

  fragment.appendChild(makeFolderRow('', rootNotes, model));

  let renderedFolders = 0;
  for (const folder of folders) {
    const folderNotes = visible.filter((note) => note.folder === folder);
    const total = notes.filter((note) => note.folder === folder).length;
    if (query && folderNotes.length === 0) continue;
    renderedFolders += 1;
    fragment.appendChild(makeFolderRow(folder, folderNotes, model));
  }

  if (query && visible.length === 0) {
    const empty = document.createElement('li');
    empty.className = 'tree-empty is-search-empty';
    empty.textContent = `没有匹配「${query}」的文档`;
    fragment.appendChild(empty);
  } else if (notes.length === 0) {
    const empty = document.createElement('li');
    empty.className = 'tree-empty';
    empty.textContent = '还没有文档，点击「+ 新建文档」开始';
    fragment.appendChild(empty);
  } else if (!query && renderedFolders === 0 && rootNotes.length === 0) {
    const empty = document.createElement('li');
    empty.className = 'tree-empty';
    empty.textContent = '笔记库还是空的';
    fragment.appendChild(empty);
  }

  container.replaceChildren(fragment);
}
