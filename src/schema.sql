CREATE TABLE tags (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE
);

CREATE TABLE notes (
  id INTEGER PRIMARY KEY,
  content TEXT NOT NULL,
  files TEXT DEFAULT '[]',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  is_pinned BOOLEAN DEFAULT 0,
  is_favorited INTEGER DEFAULT 0 NOT NULL,
  is_archived INTEGER DEFAULT 0 NOT NULL,
  link_status TEXT DEFAULT 'pending',
  pics TEXT
);

CREATE TABLE note_tags (
  note_id INTEGER NOT NULL,
  tag_id INTEGER NOT NULL,
  PRIMARY KEY (note_id, tag_id),
  FOREIGN KEY (note_id) REFERENCES notes(id) ON DELETE CASCADE,
  FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
);


CREATE TABLE nodes (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  content TEXT,
  parent_id TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY (parent_id) REFERENCES nodes(id) ON DELETE CASCADE
);
-- =============================================
-- Section 2: Full-Text Search Virtual Table
-- (This is the only FTS-related statement you need)
-- =============================================
--
CREATE VIRTUAL TABLE notes_fts USING fts5(
  content,
  files,
  content='notes',
  content_rowid='id'
);


-- =============================================
-- Section 3: Triggers to keep FTS in sync
-- =============================================

CREATE TRIGGER notes_after_insert AFTER INSERT ON notes BEGIN
  INSERT INTO notes_fts(rowid, content, files) VALUES (new.id, new.content, new.files);
END;

CREATE TRIGGER notes_after_delete AFTER DELETE ON notes BEGIN
  INSERT INTO notes_fts(notes_fts, rowid, content, files) VALUES ('delete', old.id, old.content, old.files);
END;

CREATE TRIGGER notes_after_update AFTER UPDATE ON notes BEGIN
  INSERT INTO notes_fts(notes_fts, rowid, content, files) VALUES ('delete', old.id, old.content, old.files);
  INSERT INTO notes_fts(rowid, content, files) VALUES (new.id, new.content, new.files);
END;

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
