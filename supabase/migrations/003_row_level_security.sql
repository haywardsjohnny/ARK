-- ============================================
-- Row Level Security (RLS) Policies
-- ============================================

-- Enable RLS on all tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_sports ENABLE ROW LEVEL SECURITY;
ALTER TABLE teams ENABLE ROW LEVEL SECURITY;
ALTER TABLE team_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE instant_match_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE instant_request_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE team_match_attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_hidden_games ENABLE ROW LEVEL SECURITY;

-- ============================================
-- USERS POLICIES
-- ============================================
-- Users can read their own profile
CREATE POLICY "Users can read own profile"
    ON users FOR SELECT
    USING (auth.uid() = id);

-- Users can update their own profile
CREATE POLICY "Users can update own profile"
    ON users FOR UPDATE
    USING (auth.uid() = id);

-- Users can insert their own profile
CREATE POLICY "Users can insert own profile"
    ON users FOR INSERT
    WITH CHECK (auth.uid() = id);

-- ============================================
-- USER SPORTS POLICIES
-- ============================================
-- Users can manage their own sports
CREATE POLICY "Users can manage own sports"
    ON user_sports FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- ============================================
-- TEAMS POLICIES
-- ============================================
-- Anyone can read teams
CREATE POLICY "Anyone can read teams"
    ON teams FOR SELECT
    USING (true);

-- Team creators can insert teams
CREATE POLICY "Users can create teams"
    ON teams FOR INSERT
    WITH CHECK (auth.uid() = created_by);

-- Team admins/captains can update teams
CREATE POLICY "Team admins can update teams"
    ON teams FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM team_members
            WHERE team_members.team_id = teams.id
              AND team_members.user_id = auth.uid()
              AND team_members.role IN ('admin', 'captain')
        )
    );

-- ============================================
-- TEAM MEMBERS POLICIES
-- ============================================
-- Anyone can read team members
CREATE POLICY "Anyone can read team members"
    ON team_members FOR SELECT
    USING (true);

-- Team admins can insert members
CREATE POLICY "Team admins can add members"
    ON team_members FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM team_members tm
            WHERE tm.team_id = team_members.team_id
              AND tm.user_id = auth.uid()
              AND tm.role IN ('admin', 'captain')
        )
    );

-- Users can leave teams themselves
CREATE POLICY "Users can leave teams"
    ON team_members FOR DELETE
    USING (auth.uid() = user_id);

-- Team admins can remove members
CREATE POLICY "Team admins can remove members"
    ON team_members FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM team_members tm
            WHERE tm.team_id = team_members.team_id
              AND tm.user_id = auth.uid()
              AND tm.role IN ('admin', 'captain')
        )
    );

-- ============================================
-- INSTANT MATCH REQUESTS POLICIES
-- ============================================
-- Anyone can read match requests
CREATE POLICY "Anyone can read match requests"
    ON instant_match_requests FOR SELECT
    USING (true);

-- Authenticated users can create match requests
CREATE POLICY "Users can create match requests"
    ON instant_match_requests FOR INSERT
    WITH CHECK (auth.uid() = created_by OR auth.uid() = creator_id);

-- Creators can update their match requests
CREATE POLICY "Creators can update match requests"
    ON instant_match_requests FOR UPDATE
    USING (auth.uid() = created_by OR auth.uid() = creator_id);

-- ============================================
-- INSTANT REQUEST INVITES POLICIES
-- ============================================
-- Team admins can read invites for their teams
CREATE POLICY "Team admins can read invites"
    ON instant_request_invites FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM team_members
            WHERE team_members.team_id = instant_request_invites.target_team_id
              AND team_members.user_id = auth.uid()
              AND team_members.role IN ('admin', 'captain')
        )
    );

-- System can create invites (via RPC)
-- Note: Invites are typically created via triggers or RPC functions

-- Team admins can update invites for their teams
CREATE POLICY "Team admins can update invites"
    ON instant_request_invites FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM team_members
            WHERE team_members.team_id = instant_request_invites.target_team_id
              AND team_members.user_id = auth.uid()
              AND team_members.role IN ('admin', 'captain')
        )
    );

-- ============================================
-- TEAM MATCH ATTENDANCE POLICIES
-- ============================================
-- Users can read attendance for matches they're involved in
CREATE POLICY "Users can read own attendance"
    ON team_match_attendance FOR SELECT
    USING (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM team_members
            WHERE team_members.team_id = team_match_attendance.team_id
              AND team_members.user_id = auth.uid()
              AND team_members.role IN ('admin', 'captain')
        )
    );

-- Users can update their own attendance
CREATE POLICY "Users can update own attendance"
    ON team_match_attendance FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- System can insert attendance (via RPC)
-- Note: Attendance is typically created via RPC functions

-- ============================================
-- USER HIDDEN GAMES POLICIES
-- ============================================
-- Users can manage their own hidden games
CREATE POLICY "Users can manage own hidden games"
    ON user_hidden_games FOR ALL
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

