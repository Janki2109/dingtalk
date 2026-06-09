-- Migration 003: Real-time meeting system
-- Run: psql -U postgres -d dingtalk -f 003_realtime_meetings.sql

ALTER TABLE meetings ADD COLUMN IF NOT EXISTS waiting_room_enabled BOOLEAN DEFAULT true;
ALTER TABLE meetings ADD COLUMN IF NOT EXISTS allow_chat BOOLEAN DEFAULT true;

ALTER TABLE meeting_participants ADD COLUMN IF NOT EXISTS role        VARCHAR(20) DEFAULT 'participant';
ALTER TABLE meeting_participants ADD COLUMN IF NOT EXISTS joined_at   TIMESTAMP   DEFAULT NOW();
ALTER TABLE meeting_participants ADD COLUMN IF NOT EXISTS status      VARCHAR(20) DEFAULT 'invited';

CREATE TABLE IF NOT EXISTS meeting_chat_messages (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    meeting_id  UUID REFERENCES meetings(id)  ON DELETE CASCADE,
    sender_id   UUID REFERENCES users(id),
    content     TEXT NOT NULL,
    sent_at     TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS meeting_attendance (
    id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    meeting_id  UUID REFERENCES meetings(id) ON DELETE CASCADE,
    user_id     UUID REFERENCES users(id),
    joined_at   TIMESTAMP DEFAULT NOW(),
    left_at     TIMESTAMP,
    status      VARCHAR(20) DEFAULT 'attended',
    UNIQUE (meeting_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_meeting_chat_meeting   ON meeting_chat_messages(meeting_id);
CREATE INDEX IF NOT EXISTS idx_meeting_attendance_mid ON meeting_attendance(meeting_id);
CREATE INDEX IF NOT EXISTS idx_meeting_attendance_uid ON meeting_attendance(user_id);
