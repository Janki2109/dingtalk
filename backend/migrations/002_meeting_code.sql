-- Add meeting code and invite link for Zoom-like sharing
ALTER TABLE meetings ADD COLUMN IF NOT EXISTS code VARCHAR(10) UNIQUE;
ALTER TABLE meetings ADD COLUMN IF NOT EXISTS invite_link VARCHAR(500) DEFAULT '';

-- Back-fill codes for any existing meetings
UPDATE meetings SET code = UPPER(SUBSTRING(MD5(id::text) FROM 1 FOR 6))
WHERE code IS NULL;
