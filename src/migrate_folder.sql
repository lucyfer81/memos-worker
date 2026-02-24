ALTER TABLE notes ADD COLUMN folder TEXT DEFAULT 'Inbox' NOT NULL;
CREATE INDEX IF NOT EXISTS idx_notes_folder ON notes(folder);

