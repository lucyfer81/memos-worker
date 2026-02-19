# 链接表和反向索引功能实现计划

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**目标:** 为 memos-worker 添加双向链接系统，支持卡片之间的关联、反向链接查询和智能推荐

**架构:** 使用单向链接表 (note_links) 存储关系，通过查询生成反向链接视图，配合相似度算法提供智能推荐

**技术栈:** Cloudflare Workers, D1 数据库, 原生 JavaScript (无外部依赖)

---

## 数据库架构更新

### Task 1: 更新数据库架构文件

**文件:**
- 修改: `src/schema.sql`

**Step 1: 在 notes 表定义中添加 link_status 字段**

在 `CREATE TABLE notes` 语句中，`is_archived` 字段后添加：

```sql
link_status TEXT DEFAULT 'pending',
```

**Step 2: 在 notes_fts 触发器后添加链接系统表定义**

在文件末尾添加：

```sql
-- =============================================
-- 链接系统表
-- =============================================

CREATE TABLE note_links (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  from_id INTEGER NOT NULL,
  to_id INTEGER NOT NULL,
  link_type TEXT DEFAULT 'related',
  created_at INTEGER NOT NULL,
  FOREIGN KEY (from_id) REFERENCES notes(id) ON DELETE CASCADE,
  FOREIGN KEY (to_id) REFERENCES notes(id) ON DELETE CASCADE,
  UNIQUE(from_id, to_id)
);

CREATE INDEX idx_links_from ON note_links(from_id);
CREATE INDEX idx_links_to ON note_links(to_id);
CREATE INDEX idx_links_type ON note_links(link_type);
CREATE INDEX idx_links_created ON note_links(created_at);

-- 触发器：自动维护链接状态
CREATE TRIGGER update_link_status_after_link
AFTER INSERT ON note_links
BEGIN
  UPDATE notes SET link_status = 'linked' WHERE id = NEW.from_id;
END;

CREATE TRIGGER update_link_status_after_unlink
AFTER DELETE ON note_links
BEGIN
  UPDATE notes SET link_status = 'orphan'
  WHERE id = OLD.from_id
    AND (SELECT COUNT(*) FROM note_links WHERE from_id = OLD.from_id) = 0;
END;
```

**Step 3: 验证 SQL 语法**

检查: 确保所有语句正确，无语法错误

**Step 4: 提交**

```bash
git add src/schema.sql
git commit -m "feat: 添加链接系统数据库架构

- 添加 note_links 表存储单向链接
- 添加 link_status 字段跟踪关联状态
- 创建优化索引提升查询性能
- 添加触发器自动维护状态"
```

---

## 后端 API 实现

### Task 2: 添加链接相关 API 路由

**文件:**
- 修改: `src/index.js`

**Step 1: 在路由定义区域添加链接 API 路由**

在 `handleDocsNodeRename` 函数后、`handleShareFileRequest` 函数前添加：

```javascript
// --- 链接系统 API 路由 ---
const linksMatch = pathname.match(/^\/api\/notes\/(\d+)\/links$/);
if (linksMatch) {
  const noteId = linksMatch[1];
  if (request.method === 'GET') {
    return handleGetLinks(request, noteId, env);
  }
  if (request.method === 'POST') {
    return handleCreateLinks(request, noteId, env);
  }
  if (request.method === 'DELETE') {
    return handleDeleteLink(request, noteId, env);
  }
}

const backlinksMatch = pathname.match(/^\/api\/notes\/(\d+)\/backlinks$/);
if (backlinksMatch && request.method === 'GET') {
  const noteId = backlinksMatch[1];
  return handleGetBacklinks(request, noteId, env);
}

if (pathname === '/api/notes/search-for-linking' && request.method === 'GET') {
  return handleSearchForLinking(request, env);
}

const linkStatusMatch = pathname.match(/^\/api\/notes\/(\d+)\/status$/);
if (linkStatusMatch && request.method === 'PATCH') {
  const noteId = linkStatusMatch[1];
  return handleUpdateLinkStatus(request, noteId, env);
}
```

**Step 2: 添加链接辅助函数**

在 `jsonResponse` 函数前添加：

```javascript
/**
 * 获取卡片的所有标签
 */
async function getNoteTags(noteId, db) {
  const { results } = await db.prepare(`
    SELECT t.name FROM tags t
    JOIN note_tags nt ON t.id = nt.tag_id
    WHERE nt.note_id = ?
  `).bind(noteId).all();
  return results.map(r => r.name);
}

/**
 * 计算并返回相似卡片推荐
 */
async function findSimilarNotes(noteId, db, limit = 5) {
  const note = await db.prepare("SELECT id, content FROM notes WHERE id = ?").bind(noteId).first();
  if (!note) return [];

  const noteTags = await getNoteTags(noteId, db);

  // 基于标签重叠度
  let query = `
    SELECT n.id, n.content,
           COUNT(nt.tag_id) as common_tags
    FROM notes n
    JOIN note_tags nt ON n.id = nt.note_id
    WHERE n.id != ? AND n.link_status != 'pending'
  `;
  const params = [noteId];

  if (noteTags.length > 0) {
    query += ` AND nt.tag_id IN (${noteTags.map(() => '?').join(',')})`;
    params.push(...noteTags);
  }

  query += `
    GROUP BY n.id
    ORDER BY common_tags DESC, n.updated_at DESC
    LIMIT ?
  `;
  params.push(limit);

  const { results } = await db.prepare(query).bind(...params).all();
  return results;
}

/**
 * 获取最近编辑的卡片
 */
async function getRecentNotes(noteId, db, limit = 5) {
  const { results } = await db.prepare(`
    SELECT id, content, updated_at
    FROM notes
    WHERE id != ? AND link_status != 'pending'
    ORDER BY updated_at DESC
    LIMIT ?
  `).bind(noteId, limit).all();
  return results;
}

/**
 * 搜索卡片用于关联
 */
async function handleSearchForLinking(request, env) {
  const db = env.DB;
  const { searchParams } = new URL(request.url);
  const query = searchParams.get('q');
  const excludeId = searchParams.get('excludeId');
  const limit = parseInt(searchParams.get('limit') || '10');

  if (!query || query.trim().length < 2) {
    return jsonResponse({ suggestions: [], recent: [] });
  }

  try {
    const { results: suggestions } = await db.prepare(`
      SELECT id, content, updated_at
      FROM notes
      WHERE id != ? AND link_status != 'pending'
        AND (content LIKE ? OR id IN (
          SELECT note_id FROM note_tags nt
          JOIN tags t ON nt.tag_id = t.id
          WHERE t.name LIKE ?
        ))
      ORDER BY updated_at DESC
      LIMIT ?
    `).bind(excludeId, `%${query}%`, `%${query}%`, limit).all();

    const recent = await getRecentNotes(excludeId, db, 5);

    return jsonResponse({ suggestions, recent });
  } catch (e) {
    console.error("Search for Linking Error:", e.message);
    return jsonResponse({ error: 'Database Error', message: e.message }, 500);
  }
}

/**
 * 获取卡片的所有出站链接
 */
async function handleGetLinks(request, noteId, env) {
  const db = env.DB;
  const id = parseInt(noteId);

  if (isNaN(id)) {
    return jsonResponse({ error: 'Invalid Note ID' }, 400);
  }

  try {
    const { results } = await db.prepare(`
      SELECT nl.id, nl.to_id as toId, n.content as toTitle,
             nl.link_type as linkType, nl.created_at as createdAt
      FROM note_links nl
      JOIN notes n ON nl.to_id = n.id
      WHERE nl.from_id = ?
      ORDER BY nl.created_at DESC
    `).bind(id).all();

    return jsonResponse({ links: results });
  } catch (e) {
    console.error("Get Links Error:", e.message);
    return jsonResponse({ error: 'Database Error', message: e.message }, 500);
  }
}

/**
 * 获取卡片的反向链接
 */
async function handleGetBacklinks(request, noteId, env) {
  const db = env.DB;
  const id = parseInt(noteId);

  if (isNaN(id)) {
    return jsonResponse({ error: 'Invalid Note ID' }, 400);
  }

  try {
    const { results } = await db.prepare(`
      SELECT nl.id, nl.from_id as fromId, n.content as fromTitle,
             nl.link_type as linkType, nl.created_at as createdAt
      FROM note_links nl
      JOIN notes n ON nl.from_id = n.id
      WHERE nl.to_id = ?
      ORDER BY nl.created_at DESC
    `).bind(id).all();

    return jsonResponse({ backlinks: results });
  } catch (e) {
    console.error("Get Backlinks Error:", e.message);
    return jsonResponse({ error: 'Database Error', message: e.message }, 500);
  }
}

/**
 * 创建链接
 */
async function handleCreateLinks(request, noteId, env) {
  const db = env.DB;
  const fromId = parseInt(noteId);

  if (isNaN(fromId)) {
    return jsonResponse({ error: 'Invalid Note ID' }, 400);
  }

  try {
    const { links } = await request.json();

    if (!Array.isArray(links) || links.length === 0) {
      return jsonResponse({ error: 'Links array is required' }, 400);
    }

    const now = Date.now();
    const createdLinks = [];

    for (const link of links) {
      const { toId, linkType = 'related' } = link;

      if (!toId || toId === fromId) continue;

      try {
        const stmt = db.prepare(`
          INSERT INTO note_links (from_id, to_id, link_type, created_at)
          VALUES (?, ?, ?, ?)
          ON CONFLICT(from_id, to_id) DO UPDATE SET
            link_type = excluded.link_type,
            created_at = excluded.created_at
          RETURNING id, to_id, link_type
        `);

        const result = await stmt.bind(fromId, toId, linkType, now).first();
        if (result) {
          createdLinks.push(result);
        }
      } catch (e) {
        // 忽略重复链接错误
        if (!e.message.includes('UNIQUE')) {
          throw e;
        }
      }
    }

    return jsonResponse({ success: true, links: createdLinks });
  } catch (e) {
    console.error("Create Links Error:", e.message);
    return jsonResponse({ error: 'Database Error', message: e.message }, 500);
  }
}

/**
 * 删除链接
 */
async function handleDeleteLink(request, noteId, env) {
  const db = env.DB;
  const fromId = parseInt(noteId);
  const { searchParams } = new URL(request.url);
  const toId = parseInt(searchParams.get('toId'));

  if (isNaN(fromId) || isNaN(toId)) {
    return jsonResponse({ error: 'Invalid Note ID' }, 400);
  }

  try {
    await db.prepare(`
      DELETE FROM note_links WHERE from_id = ? AND to_id = ?
    `).bind(fromId, toId).run();

    return jsonResponse({ success: true });
  } catch (e) {
    console.error("Delete Link Error:", e.message);
    return jsonResponse({ error: 'Database Error', message: e.message }, 500);
  }
}

/**
 * 更新卡片链接状态
 */
async function handleUpdateLinkStatus(request, noteId, env) {
  const db = env.DB;
  const id = parseInt(noteId);

  if (isNaN(id)) {
    return jsonResponse({ error: 'Invalid Note ID' }, 400);
  }

  try {
    const { status } = await request.json();

    if (!['pending', 'linked', 'orphan'].includes(status)) {
      return jsonResponse({ error: 'Invalid status value' }, 400);
    }

    await db.prepare(`
      UPDATE notes SET link_status = ? WHERE id = ?
    `).bind(status, id).run();

    return jsonResponse({ success: true });
  } catch (e) {
    console.error("Update Link Status Error:", e.message);
    return jsonResponse({ error: 'Database Error', message: e.message }, 500);
  }
}
```

**Step 3: 修改 handleNotesList 的 POST 处理**

找到 `handleNotesList` 函数的 `POST` case，在插入笔记后添加状态设置：

```javascript
// 在 INSERT 语句中添加 link_status 字段
const insertStmt = db.prepare(
  "INSERT INTO notes (content, files, is_pinned, created_at, updated_at, pics, link_status) VALUES (?, ?, 0, ?, ?, ?, ?) RETURNING id"
);
const { id: noteId } = await insertStmt.bind(content, "[]", now, now, picUrls, 'pending').first();
```

**Step 4: 修改 handleNoteDetail 的 GET 处理**

在返回笔记数据时，添加链接信息：

```javascript
// 在返回 updatedNote 之前添加
const [linksResult, backlinksResult] = await Promise.all([
  db.prepare(`
    SELECT nl.id, nl.to_id, nl.link_type, n.content
    FROM note_links nl
    JOIN notes n ON nl.to_id = n.id
    WHERE nl.from_id = ?
  `).bind(id).all(),
  db.prepare(`
    SELECT nl.id, nl.from_id, nl.link_type, n.content
    FROM note_links nl
    JOIN notes n ON nl.from_id = n.id
    WHERE nl.to_id = ?
  `).bind(id).all()
]);

updatedNote.links = linksResult.results || [];
updatedNote.backlinks = backlinksResult.results || [];
```

**Step 5: 添加获取推荐卡片的 API**

在搜索 API 路由区域添加：

```javascript
if (pathname === '/api/notes/:noteId/suggestions' && request.method === 'GET') {
  const match = pathname.match(/^\/api\/notes\/(\d+)\/suggestions$/);
  if (match) {
    return handleGetSuggestions(request, match[1], env);
  }
}
```

添加处理函数：

```javascript
async function handleGetSuggestions(request, noteId, env) {
  const db = env.DB;
  const id = parseInt(noteId);

  if (isNaN(id)) {
    return jsonResponse({ error: 'Invalid Note ID' }, 400);
  }

  try {
    const [similar, recent] = await Promise.all([
      findSimilarNotes(id, db, 5),
      getRecentNotes(id, db, 5)
    ]);

    return jsonResponse({ similar, recent });
  } catch (e) {
    console.error("Get Suggestions Error:", e.message);
    return jsonResponse({ error: 'Database Error', message: e.message }, 500);
  }
}
```

**Step 6: 提交**

```bash
git add src/index.js
git commit -m "feat: 添加链接系统 API

- 添加创建/查询/删除链接的 API
- 添加反向链接查询
- 添加相似卡片推荐 API
- 添加搜索关联卡片功能
- 集成链接状态到笔记详情"
```

---

## 前端 UI 实现

### Task 3: 添加链接相关 CSS 样式

**文件:**
- 修改: `src/public/index.html`

**Step 1: 在 style 标签中添加链接相关样式**

在现有样式后添加：

```css
/* 链接系统样式 */
.link-decision-panel {
  position: fixed;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
  background: var(--surface-color);
  border-radius: 8px;
  box-shadow: 0 4px 20px rgba(0,0,0,0.3);
  width: 90%;
  max-width: 600px;
  max-height: 80vh;
  overflow-y: auto;
  z-index: 1000;
  padding: 20px;
}

.link-decision-panel h2 {
  margin: 0 0 15px 0;
  color: var(--text-color);
}

.link-suggestions, .link-recent {
  margin-bottom: 20px;
}

.link-suggestion-item {
  padding: 12px;
  border: 1px solid var(--border-color);
  border-radius: 6px;
  margin-bottom: 8px;
  cursor: pointer;
  transition: all 0.2s;
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.link-suggestion-item:hover {
  background: var(--hover-bg-color);
}

.link-suggestion-item.selected {
  background: var(--active-bg-color);
  border-color: var(--primary-color);
}

.link-suggestion-content {
  flex: 1;
}

.link-suggestion-title {
  font-weight: 600;
  color: var(--text-color);
  margin-bottom: 4px;
}

.link-suggestion-meta {
  font-size: 0.85em;
  color: var(--text-secondary);
}

.link-type-select {
  padding: 4px 8px;
  border: 1px solid var(--border-color);
  border-radius: 4px;
  background: var(--surface-color);
  color: var(--text-color);
}

.link-search-box {
  margin-bottom: 15px;
}

.link-search-box input {
  width: 100%;
  padding: 10px;
  border: 1px solid var(--border-color);
  border-radius: 6px;
  background: var(--surface-input-bg, var(--surface-color));
  color: var(--text-color);
}

.link-selected-count {
  padding: 10px;
  background: var(--quote-bg-color);
  border-left: 3px solid var(--accent-color);
  margin-bottom: 15px;
  font-size: 0.9em;
}

.link-decision-buttons {
  display: flex;
  gap: 10px;
  margin-top: 20px;
}

.link-decision-buttons button {
  flex: 1;
  padding: 10px;
  border: none;
  border-radius: 6px;
  cursor: pointer;
  font-weight: 600;
}

.link-btn-inbox {
  background: #f59e0b;
  color: white;
}

.link-btn-orphan {
  background: #6b7280;
  color: white;
}

.link-btn-save {
  background: var(--primary-color);
  color: white;
}

.note-status-pending {
  border-left: 3px solid #f59e0b;
}

.note-status-pending .note-header::before {
  content: '📥 ';
}

.backlinks-section {
  margin-top: 15px;
  padding-top: 15px;
  border-top: 1px solid var(--border-color);
}

.backlinks-title {
  font-size: 0.9em;
  color: var(--text-secondary);
  margin-bottom: 10px;
}

.backlink-item {
  padding: 8px;
  background: var(--hover-bg-color);
  border-radius: 4px;
  margin-bottom: 6px;
  cursor: pointer;
}

.backlink-item:hover {
  background: var(--active-bg-color);
}

.link-type-badge {
  display: inline-block;
  padding: 2px 6px;
  border-radius: 3px;
  font-size: 0.75em;
  margin-left: 6px;
}

.link-type-related { background: #e0f2fe; color: #0369a1; }
.link-type-supports { background: #dcfce7; color: #15803d; }
.link-type-contradicts { background: #fee2e2; color: #b91c1c; }
.link-type-expands { background: #f3e8ff; color: #7c3aed; }

.toast-warning {
  background: #fef3c7;
  color: #92400e;
  padding: 10px;
  border-radius: 6px;
  margin-bottom: 10px;
  border-left: 3px solid #f59e0b;
}
```

**Step 2: 提交**

```bash
git add src/public/index.html
git commit -m "style: 添加链接系统 UI 样式"
```

---

### Task 4: 实现关联决策面板 JavaScript

**文件:**
- 修改: `src/public/index.html` (在 script 标签内)

**Step 1: 添加链接相关状态变量**

在现有状态变量后添加：

```javascript
let linkSuggestions = [];
let selectedLinks = [];
let isLinkDecisionPending = false;
let pendingNoteContent = null;
```

**Step 2: 添加获取推荐卡片函数**

```javascript
async function fetchLinkSuggestions(noteId) {
  try {
    const response = await fetch(`/api/notes/${noteId}/suggestions`);
    if (!response.ok) throw new Error('Failed to fetch suggestions');
    return await response.json();
  } catch (error) {
    console.error('Error fetching suggestions:', error);
    return { similar: [], recent: [] };
  }
}

async function searchNotesForLinking(query, excludeId) {
  try {
    const response = await fetch(`/api/notes/search-for-linking?q=${encodeURIComponent(query)}&excludeId=${excludeId}`);
    if (!response.ok) throw new Error('Search failed');
    return await response.json();
  } catch (error) {
    console.error('Error searching notes:', error);
    return { suggestions: [], recent: [] };
  }
}
```

**Step 3: 添加显示关联决策面板函数**

```javascript
function showLinkDecisionPanel(noteId, content) {
  isLinkDecisionPending = true;
  pendingNoteContent = { id: noteId, content };
  selectedLinks = [];

  const panel = document.createElement('div');
  panel.className = 'link-decision-panel';
  panel.innerHTML = `
    <h2>🔗 建立关联关系</h2>

    <div class="link-suggestions">
      <h3>💡 相似卡片推荐</h3>
      <div id="similar-suggestions"></div>
    </div>

    <div class="link-recent">
      <h3>🕐 最近编辑</h3>
      <div id="recent-suggestions"></div>
    </div>

    <div class="link-search-box">
      <input type="text" id="link-search-input" placeholder="🔍 搜索其他卡片..." />
      <div id="search-results"></div>
    </div>

    <div id="link-selected-count"></div>

    <div class="link-decision-buttons">
      <button class="link-btn-inbox" onclick="saveToInbox()">📥 存入收件箱</button>
      <button class="link-btn-orphan" onclick="saveAsOrphan()">设为新主题起点</button>
      <button class="link-btn-save" onclick="saveWithLinks()">保存关联并完成</button>
    </div>
  `;

  document.body.appendChild(panel);

  // 加载推荐
  loadSuggestions(noteId);

  // 绑定搜索事件
  const searchInput = document.getElementById('link-search-input');
  let searchTimeout;
  searchInput.addEventListener('input', (e) => {
    clearTimeout(searchTimeout);
    searchTimeout = setTimeout(() => {
      if (e.target.value.length >= 2) {
        performSearch(e.target.value, noteId);
      }
    }, 300);
  });
}

function loadSuggestions(noteId) {
  fetchLinkSuggestions(noteId).then(data => {
    renderSuggestions('similar-suggestions', data.similar, 'similar');
    renderSuggestions('recent-suggestions', data.recent, 'recent');
  });
}

function renderSuggestions(containerId, items, type) {
  const container = document.getElementById(containerId);
  if (!items || items.length === 0) {
    container.innerHTML = '<p style="color: var(--text-secondary);">暂无推荐</p>';
    return;
  }

  container.innerHTML = items.map(item => `
    <div class="link-suggestion-item" data-id="${item.id}" onclick="toggleLinkSelection(${item.id}, '${escapeHtml(item.content.substring(0, 100))}')">
      <div class="link-suggestion-content">
        <div class="link-suggestion-title">${escapeHtml(item.content.substring(0, 50))}${item.content.length > 50 ? '...' : ''}</div>
        <div class="link-suggestion-meta">
          ${type === 'similar' ? `相似度: ${item.common_tags || 'N/A'}` : `最近编辑`}
        </div>
      </div>
      <select class="link-type-select" onclick="event.stopPropagation()">
        <option value="related">相关</option>
        <option value="supports">支持</option>
        <option value="contradicts">反驳</option>
        <option value="expands">扩展</option>
      </select>
    </div>
  `).join('');
}

function performSearch(query, excludeId) {
  searchNotesForLinking(query, excludeId).then(data => {
    const container = document.getElementById('search-results');
    if (data.suggestions.length === 0) {
      container.innerHTML = '<p style="color: var(--text-secondary);">未找到匹配卡片</p>';
      return;
    }

    container.innerHTML = data.suggestions.map(item => `
      <div class="link-suggestion-item" data-id="${item.id}" onclick="toggleLinkSelection(${item.id}, '${escapeHtml(item.content.substring(0, 100))}')">
        <div class="link-suggestion-content">
          <div class="link-suggestion-title">${escapeHtml(item.content.substring(0, 50))}${item.content.length > 50 ? '...' : ''}</div>
        </div>
        <select class="link-type-select" onclick="event.stopPropagation()">
          <option value="related">相关</option>
          <option value="supports">支持</option>
          <option value="contradicts">反驳</option>
          <option value="expands">扩展</option>
        </select>
      </div>
    `).join('');
  });
}

function toggleLinkSelection(noteId, title) {
  const existingIndex = selectedLinks.findIndex(l => l.toId === noteId);

  if (existingIndex >= 0) {
    selectedLinks.splice(existingIndex, 1);
  } else {
    if (selectedLinks.length >= 3) {
      showToast('💡 建议不超过3个关联。多个关联可能表示需要拆分卡片。', 'warning');
    }
    selectedLinks.push({ toId: noteId, linkType: 'related' });
  }

  updateSelectionUI();
}

function updateSelectionUI() {
  // 更新选中状态
  document.querySelectorAll('.link-suggestion-item').forEach(item => {
    const id = parseInt(item.dataset.id);
    if (selectedLinks.some(l => l.toId === id)) {
      item.classList.add('selected');
    } else {
      item.classList.remove('selected');
    }
  });

  // 更新计数显示
  const countEl = document.getElementById('link-selected-count');
  if (selectedLinks.length > 0) {
    countEl.innerHTML = `✅ 已选择 ${selectedLinks.length} 个关联`;
    countEl.style.display = 'block';
  } else {
    countEl.style.display = 'none';
  }
}

async function saveToInbox() {
  if (!pendingNoteContent) return;

  try {
    const response = await fetch(`/api/notes/${pendingNoteContent.id}/status`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: 'pending' })
    });

    if (!response.ok) throw new Error('Failed to save to inbox');

    closeLinkDecisionPanel();
    loadNotes();
    showToast('✅ 已存入收件箱');
  } catch (error) {
    console.error('Error saving to inbox:', error);
    showToast('❌ 保存失败', 'error');
  }
}

async function saveAsOrphan() {
  if (!pendingNoteContent) return;

  try {
    const response = await fetch(`/api/notes/${pendingNoteContent.id}/status`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ status: 'orphan' })
    });

    if (!response.ok) throw new Error('Failed to save as orphan');

    closeLinkDecisionPanel();
    loadNotes();
    showToast('✅ 已保存为新主题');
  } catch (error) {
    console.error('Error saving as orphan:', error);
    showToast('❌ 保存失败', 'error');
  }
}

async function saveWithLinks() {
  if (!pendingNoteContent) return;

  try {
    // 获取选中的链接类型
    selectedLinks.forEach(link => {
      const item = document.querySelector(`.link-suggestion-item[data-id="${link.toId}"]`);
      if (item) {
        const select = item.querySelector('.link-type-select');
        link.linkType = select.value;
      }
    });

    const response = await fetch(`/api/notes/${pendingNoteContent.id}/links`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ links: selectedLinks })
    });

    if (!response.ok) throw new Error('Failed to save links');

    closeLinkDecisionPanel();
    loadNotes();
    showToast(`✅ 已创建 ${selectedLinks.length} 个关联`);
  } catch (error) {
    console.error('Error saving links:', error);
    showToast('❌ 保存失败', 'error');
  }
}

function closeLinkDecisionPanel() {
  const panel = document.querySelector('.link-decision-panel');
  if (panel) {
    panel.remove();
  }
  isLinkDecisionPending = false;
  pendingNoteContent = null;
  selectedLinks = [];
}
```

**Step 4: 修改保存笔记流程**

找到现有的笔记保存函数，在保存成功后添加：

```javascript
// 在保存成功后添加
if (response.ok) {
  const note = await response.json();

  // 显示关联决策面板
  showLinkDecisionPanel(note.id, note.content);

  // 继续原有的刷新逻辑...
}
```

**Step 5: 添加显示链接和反向链接的函数**

```javascript
function renderNoteLinks(note) {
  if (!note.links && !note.backlinks) return '';

  let html = '<div class="links-section">';

  if (note.links && note.links.length > 0) {
    html += '<div class="outbound-links">';
    html += '<h4>🔗 关联的卡片</h4>';
    note.links.forEach(link => {
      html += `
        <div class="link-item" onclick="loadNoteById(${link.to_id})">
          <span class="link-type-badge link-type-${link.linkType}">${link.linkType}</span>
          ${escapeHtml(link.content.substring(0, 50))}...
        </div>
      `;
    });
    html += '</div>';
  }

  if (note.backlinks && note.backlinks.length > 0) {
    html += '<div class="backlinks-section">';
    html += '<h4>🔙 反向链接</h4>';
    note.backlinks.forEach(link => {
      html += `
        <div class="backlink-item" onclick="loadNoteById(${link.from_id})">
          <span class="link-type-badge link-type-${link.linkType}">${link.linkType}</span>
          ${escapeHtml(link.fromTitle.substring(0, 50))}...
        </div>
      `;
    });
    html += '</div>';
  }

  html += '</div>';
  return html;
}

async function loadNoteById(noteId) {
  try {
    const response = await fetch(`/api/notes/${noteId}`);
    if (!response.ok) throw new Error('Failed to load note');
    const note = await response.json();
    // 显示笔记详情的逻辑
    // 这里需要根据你现有的显示笔记逻辑来实现
  } catch (error) {
    console.error('Error loading note:', error);
    showToast('❌ 加载失败', 'error');
  }
}
```

**Step 6: 添加 Inbox 提示**

在侧边栏或合适位置添加：

```javascript
async function updateInboxCounter() {
  try {
    const response = await fetch('/api/notes?status=pending');
    if (response.ok) {
      const data = await response.json();
      const pendingCount = data.notes ? data.notes.length : 0;
      const inboxEl = document.getElementById('inbox-counter');
      if (inboxEl) {
        inboxEl.textContent = pendingCount > 0 ? `📥 收件箱 (${pendingCount})` : '📥 收件箱';
      }
    }
  } catch (error) {
    console.error('Error updating inbox counter:', error);
  }
}
```

**Step 7: 提交**

```bash
git add src/public/index.html
git commit -m "feat: 实现关联决策面板和链接显示

- 添加关联决策面板 UI
- 实现相似卡片推荐
- 实现搜索关联功能
- 添加 Inbox 暂缓流程
- 显示链接和反向链接
- 添加 Inbox 计数器"
```

---

## 测试和部署

### Task 5: 本地测试功能

**Step 1: 应用数据库迁移**

```bash
# 备份现有数据（如果需要）
npx wrangler d1 backups create memos-db --backup-name backup-before-links

# 应用新架构
npx wrangler d1 execute memos-db --file=src/schema.sql
```

**Step 2: 本地开发测试**

```bash
npm run dev
```

**Step 3: 测试功能清单**

- [ ] 创建新笔记，弹出关联决策面板
- [ ] 选择相似卡片并创建关联
- [ ] 使用搜索功能查找卡片
- [ ] 保存到 Inbox
- [ ] 设为新主题起点
- [ ] 点击 Inbox 笔记继续关联
- [ ] 查看卡片的出站链接
- [ ] 查看卡片的反向链接
- [ ] 删除链接
- [ ] 修改链接类型
- [ ] 超过3个关联时显示提示

**Step 4: 修复发现的问题**

记录并修复测试中发现的问题

**Step 5: 提交修复**

```bash
git add .
git commit -m "fix: 修复链接功能测试中发现的问题"
```

---

### Task 6: 部署到生产环境

**Step 1: 部署到 Cloudflare Workers**

```bash
npm run deploy
```

**Step 2: 验证生产环境**

- [ ] 访问生产环境 URL
- [ ] 测试所有功能
- [ ] 检查控制台错误

**Step 3: 提交并打标签**

```bash
git add .
git commit -m "release: 完成链接和反向索引功能

- 实现完整的双向链接系统
- 支持多种链接类型
- 智能相似卡片推荐
- Inbox 暂缓决策流程
- 反向链接查询和显示

功能已测试并部署到生产环境"

git tag v1.1.0
git push origin master --tags
```

---

## 总结

这个实现计划涵盖了：

1. ✅ 数据库架构（links 表、状态字段、索引、触发器）
2. ✅ 后端 API（创建、查询、删除、搜索、推荐）
3. ✅ 前端 UI（决策面板、链接显示、Inbox 管理）
4. ✅ 智能推荐（基于标签的相似度计算）
5. ✅ 测试和部署流程

所有代码都采用原生 JavaScript，无需外部依赖，完美适配 Cloudflare Workers 环境。
