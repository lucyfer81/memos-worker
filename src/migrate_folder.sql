ALTER TABLE notes ADD COLUMN folder TEXT DEFAULT 'Inbox' NOT NULL;
CREATE INDEX IF NOT EXISTS idx_notes_folder ON notes(folder);
CREATE TABLE IF NOT EXISTS folders (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  path TEXT NOT NULL UNIQUE,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
INSERT OR IGNORE INTO folders(path, created_at, updated_at)
VALUES ('Inbox', CAST(strftime('%s','now') AS INTEGER) * 1000, CAST(strftime('%s','now') AS INTEGER) * 1000);
INSERT OR IGNORE INTO folders(path, created_at, updated_at)
SELECT DISTINCT COALESCE(NULLIF(TRIM(folder), ''), 'Inbox') AS path,
       CAST(strftime('%s','now') AS INTEGER) * 1000,
       CAST(strftime('%s','now') AS INTEGER) * 1000
FROM notes;
DELETE FROM folders WHERE path IS NULL OR TRIM(path) = '';
DELETE FROM folders
WHERE id NOT IN (
  SELECT MIN(id) FROM folders GROUP BY LOWER(path)
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_folders_path_lower ON folders(LOWER(path));
