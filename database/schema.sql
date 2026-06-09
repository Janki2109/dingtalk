-- ============================================================
-- DINGTALK DATABASE SCHEMA
-- Run: psql -U postgres -d dingtalk -f schema.sql
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- USERS
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) NOT NULL,
    email VARCHAR(150) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    phone VARCHAR(20),
    avatar_url TEXT,
    role VARCHAR(100) DEFAULT 'Employee',
    department VARCHAR(100) DEFAULT 'General',
    status VARCHAR(20) DEFAULT 'offline' CHECK (status IN ('online','away','busy','offline')),
    dingtalk_user_id VARCHAR(100),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- CHATS
CREATE TABLE IF NOT EXISTS chats (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(200),
    is_group BOOLEAN DEFAULT false,
    avatar_url TEXT,
    created_by UUID REFERENCES users(id),
    is_pinned BOOLEAN DEFAULT false,
    is_muted BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW()
);

-- CHAT MEMBERS
CREATE TABLE IF NOT EXISTS chat_members (
    chat_id UUID REFERENCES chats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    joined_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (chat_id, user_id)
);

-- MESSAGES
CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    chat_id UUID REFERENCES chats(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES users(id),
    content TEXT NOT NULL,
    message_type VARCHAR(20) DEFAULT 'text' CHECK (message_type IN ('text','image','file','audio','ai','system','location')),
    file_url TEXT,
    file_name VARCHAR(255),
    reply_to_id UUID REFERENCES messages(id),
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMP DEFAULT NOW()
);

-- MEETINGS
CREATE TABLE IF NOT EXISTS meetings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title VARCHAR(200) NOT NULL,
    description TEXT,
    organizer_id UUID REFERENCES users(id),
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP NOT NULL,
    meeting_link VARCHAR(500),
    status VARCHAR(20) DEFAULT 'upcoming' CHECK (status IN ('upcoming','ongoing','ended','cancelled')),
    created_at TIMESTAMP DEFAULT NOW()
);

-- MEETING PARTICIPANTS
CREATE TABLE IF NOT EXISTS meeting_participants (
    meeting_id UUID REFERENCES meetings(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    PRIMARY KEY (meeting_id, user_id)
);

-- TASKS
CREATE TABLE IF NOT EXISTS tasks (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title VARCHAR(300) NOT NULL,
    description TEXT,
    assignee_id UUID REFERENCES users(id),
    created_by UUID REFERENCES users(id),
    project_name VARCHAR(150) DEFAULT 'General',
    due_date TIMESTAMP,
    priority VARCHAR(20) DEFAULT 'medium' CHECK (priority IN ('low','medium','high','urgent')),
    status VARCHAR(20) DEFAULT 'todo' CHECK (status IN ('todo','in_progress','review','done')),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- ATTENDANCE
CREATE TABLE IF NOT EXISTS attendance (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id),
    date DATE NOT NULL,
    check_in TIMESTAMP,
    check_out TIMESTAMP,
    status VARCHAR(20) DEFAULT 'absent' CHECK (status IN ('present','absent','late','half_day','leave','holiday')),
    location VARCHAR(200),
    UNIQUE(user_id, date)
);

-- FILES
CREATE TABLE IF NOT EXISTS files (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(300) NOT NULL,
    file_type VARCHAR(20),
    size_bytes BIGINT DEFAULT 0,
    url TEXT NOT NULL,
    folder_id UUID,
    uploaded_by UUID REFERENCES users(id),
    chat_id UUID REFERENCES chats(id),
    uploaded_at TIMESTAMP DEFAULT NOW()
);

-- NOTIFICATIONS
CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id),
    title VARCHAR(300) NOT NULL,
    body TEXT,
    notification_type VARCHAR(30) CHECK (notification_type IN ('message','meeting','task','approval','attendance','system')),
    is_read BOOLEAN DEFAULT false,
    action_id UUID,
    created_at TIMESTAMP DEFAULT NOW()
);

-- APPROVALS
CREATE TABLE IF NOT EXISTS approvals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title VARCHAR(300) NOT NULL,
    approval_type VARCHAR(50),
    requester_id UUID REFERENCES users(id),
    approver_id UUID REFERENCES users(id),
    description TEXT,
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','cancelled')),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- INDEXES
CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at);
CREATE INDEX IF NOT EXISTS idx_attendance_user_date ON attendance(user_id, date);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id, is_read);
CREATE INDEX IF NOT EXISTS idx_tasks_assignee ON tasks(assignee_id);

-- SEED DEMO USERS (password: "password123" bcrypt)
INSERT INTO users (name, email, password_hash, role, department, status) VALUES
('Alex Morgan',   'alex@company.com',  '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lh', 'Product Manager',    'Product',     'online'),
('Sarah Chen',    'sarah@company.com', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lh', 'Senior Engineer',    'Engineering', 'busy'),
('James Wilson',  'james@company.com', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lh', 'UI/UX Designer',     'Design',      'away'),
('Priya Sharma',  'priya@company.com', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lh', 'Data Analyst',       'Analytics',   'online'),
('Marcus Lee',    'marcus@company.com','$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lh', 'Backend Engineer',   'Engineering', 'offline'),
('Emily Davis',   'emily@company.com', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lh', 'HR Manager',         'HR',          'online'),
('demo@company.com','demo@company.com','$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lh', 'Flutter Developer',  'Engineering', 'online')
ON CONFLICT (email) DO NOTHING;
