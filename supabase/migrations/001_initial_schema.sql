-- ============================================
-- SPORTSDUG Database Schema
-- Initial Migration
-- ============================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- USERS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    base_zip_code TEXT,
    bio TEXT,
    photo_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- USER SPORTS (Many-to-Many)
-- ============================================
CREATE TABLE IF NOT EXISTS user_sports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    sport TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, sport)
);

-- ============================================
-- TEAMS TABLE
-- ============================================
CREATE TABLE IF NOT EXISTS teams (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    sport TEXT NOT NULL,
    description TEXT,
    proficiency_level TEXT CHECK (proficiency_level IN ('Recreational', 'Intermediate', 'Competitive')),
    zip_code TEXT,
    team_number INTEGER,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- TEAM MEMBERS (Many-to-Many)
-- ============================================
CREATE TABLE IF NOT EXISTS team_members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role TEXT DEFAULT 'member' CHECK (role IN ('member', 'captain', 'admin')),
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(team_id, user_id)
);

-- ============================================
-- INSTANT MATCH REQUESTS
-- ============================================
CREATE TABLE IF NOT EXISTS instant_match_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    team_id UUID REFERENCES teams(id) ON DELETE SET NULL,
    sport TEXT NOT NULL,
    zip_code TEXT,
    mode TEXT NOT NULL CHECK (mode IN ('team_vs_team', 'individual')),
    start_time_1 TIMESTAMPTZ,
    start_time_2 TIMESTAMPTZ,
    venue TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'matched', 'cancelled', 'completed')),
    matched_team_id UUID REFERENCES teams(id) ON DELETE SET NULL,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    creator_id UUID REFERENCES users(id) ON DELETE SET NULL,
    cancelled_by UUID REFERENCES users(id) ON DELETE SET NULL,
    cancelled_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- INSTANT REQUEST INVITES
-- ============================================
CREATE TABLE IF NOT EXISTS instant_request_invites (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    request_id UUID NOT NULL REFERENCES instant_match_requests(id) ON DELETE CASCADE,
    target_team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'denied')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- TEAM MATCH ATTENDANCE
-- ============================================
CREATE TABLE IF NOT EXISTS team_match_attendance (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    request_id UUID NOT NULL REFERENCES instant_match_requests(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(request_id, user_id)
);

-- ============================================
-- USER HIDDEN GAMES
-- ============================================
CREATE TABLE IF NOT EXISTS user_hidden_games (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    request_id UUID NOT NULL REFERENCES instant_match_requests(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, request_id)
);

-- ============================================
-- INDEXES for Performance
-- ============================================

-- Users
CREATE INDEX IF NOT EXISTS idx_users_zip_code ON users(base_zip_code);

-- User Sports
CREATE INDEX IF NOT EXISTS idx_user_sports_user_id ON user_sports(user_id);
CREATE INDEX IF NOT EXISTS idx_user_sports_sport ON user_sports(sport);

-- Teams
CREATE INDEX IF NOT EXISTS idx_teams_sport ON teams(sport);
CREATE INDEX IF NOT EXISTS idx_teams_zip_code ON teams(zip_code);
CREATE INDEX IF NOT EXISTS idx_teams_created_by ON teams(created_by);

-- Team Members
CREATE INDEX IF NOT EXISTS idx_team_members_team_id ON team_members(team_id);
CREATE INDEX IF NOT EXISTS idx_team_members_user_id ON team_members(user_id);
CREATE INDEX IF NOT EXISTS idx_team_members_role ON team_members(role);

-- Instant Match Requests
CREATE INDEX IF NOT EXISTS idx_match_requests_team_id ON instant_match_requests(team_id);
CREATE INDEX IF NOT EXISTS idx_match_requests_sport ON instant_match_requests(sport);
CREATE INDEX IF NOT EXISTS idx_match_requests_zip_code ON instant_match_requests(zip_code);
CREATE INDEX IF NOT EXISTS idx_match_requests_status ON instant_match_requests(status);
CREATE INDEX IF NOT EXISTS idx_match_requests_mode ON instant_match_requests(mode);
CREATE INDEX IF NOT EXISTS idx_match_requests_matched_team_id ON instant_match_requests(matched_team_id);
CREATE INDEX IF NOT EXISTS idx_match_requests_created_by ON instant_match_requests(created_by);

-- Instant Request Invites
CREATE INDEX IF NOT EXISTS idx_invites_request_id ON instant_request_invites(request_id);
CREATE INDEX IF NOT EXISTS idx_invites_target_team_id ON instant_request_invites(target_team_id);
CREATE INDEX IF NOT EXISTS idx_invites_status ON instant_request_invites(status);

-- Team Match Attendance
CREATE INDEX IF NOT EXISTS idx_attendance_request_id ON team_match_attendance(request_id);
CREATE INDEX IF NOT EXISTS idx_attendance_user_id ON team_match_attendance(user_id);
CREATE INDEX IF NOT EXISTS idx_attendance_team_id ON team_match_attendance(team_id);
CREATE INDEX IF NOT EXISTS idx_attendance_status ON team_match_attendance(status);

-- User Hidden Games
CREATE INDEX IF NOT EXISTS idx_hidden_games_user_id ON user_hidden_games(user_id);
CREATE INDEX IF NOT EXISTS idx_hidden_games_request_id ON user_hidden_games(request_id);

-- ============================================
-- TRIGGERS for updated_at
-- ============================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_teams_updated_at BEFORE UPDATE ON teams
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_invites_updated_at BEFORE UPDATE ON instant_request_invites
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_attendance_updated_at BEFORE UPDATE ON team_match_attendance
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

