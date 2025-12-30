-- Add critical composite indexes for 100K+ user scalability
-- These indexes optimize common query patterns
--
-- ⚠️ SAFE TO APPLY: Indexes are read-only optimizations and cannot break functionality
-- If needed, indexes can be dropped with: DROP INDEX IF EXISTS idx_name;
--
-- Testing Checklist After Applying:
-- [ ] Load user teams
-- [ ] Load friends
-- [ ] Load matches (My Games)
-- [ ] Create games
-- [ ] Accept/decline invites
-- [ ] View team members
-- [ ] Discovery search
--
-- If anything breaks, see SAFE_SCALABILITY_PLAN.md for rollback instructions

-- ============================================
-- ATTENDANCE TABLE OPTIMIZATIONS
-- ============================================

-- For: WHERE user_id = X AND status = 'accepted'
CREATE INDEX IF NOT EXISTS idx_attendance_user_status 
ON team_match_attendance(user_id, status);

-- For: WHERE team_id = X AND status = 'pending'
CREATE INDEX IF NOT EXISTS idx_attendance_team_status 
ON team_match_attendance(team_id, status);

-- For: WHERE request_id = X AND user_id = Y
CREATE INDEX IF NOT EXISTS idx_attendance_request_user 
ON team_match_attendance(request_id, user_id);

-- For: WHERE user_id = X AND status = 'accepted' ORDER BY created_at DESC
CREATE INDEX IF NOT EXISTS idx_attendance_user_status_created 
ON team_match_attendance(user_id, status, created_at DESC);

-- Partial index for pending attendance (most common query)
CREATE INDEX IF NOT EXISTS idx_attendance_pending 
ON team_match_attendance(request_id, user_id) 
WHERE status = 'pending';

-- ============================================
-- MATCH REQUESTS OPTIMIZATIONS
-- ============================================

-- For: WHERE sport = X AND zip_code = Y AND status = 'pending' AND mode = 'team_vs_team'
CREATE INDEX IF NOT EXISTS idx_match_requests_sport_zip_status_mode 
ON instant_match_requests(sport, zip_code, status, mode) 
WHERE status != 'cancelled';

-- For: WHERE created_by = X AND status != 'cancelled'
CREATE INDEX IF NOT EXISTS idx_match_requests_creator_status 
ON instant_match_requests(created_by, status) 
WHERE status != 'cancelled';

-- Partial index for active matches (most common query)
-- Note: Removed NOW() check as it's not IMMUTABLE and can't be used in index predicates
-- The index will still be useful for querying active matches, filtering by time can be done in the query
CREATE INDEX IF NOT EXISTS idx_match_requests_active 
ON instant_match_requests(sport, zip_code, start_time_1) 
WHERE status IN ('pending', 'matched');

-- For: WHERE matched_team_id = X AND status = 'matched'
CREATE INDEX IF NOT EXISTS idx_match_requests_matched_status 
ON instant_match_requests(matched_team_id, status) 
WHERE matched_team_id IS NOT NULL;

-- ============================================
-- FRIENDS TABLE OPTIMIZATIONS
-- ============================================

-- For: WHERE user_id = X AND status = 'accepted'
CREATE INDEX IF NOT EXISTS idx_friends_user_status 
ON friends(user_id, status);

-- For: WHERE friend_id = X AND status = 'accepted'
CREATE INDEX IF NOT EXISTS idx_friends_friend_status 
ON friends(friend_id, status);

-- ============================================
-- TEAM MEMBERS OPTIMIZATIONS
-- ============================================

-- For: WHERE team_id = X AND role = 'admin'
CREATE INDEX IF NOT EXISTS idx_team_members_team_role 
ON team_members(team_id, role);

-- For: WHERE user_id = X AND role = 'admin'
CREATE INDEX IF NOT EXISTS idx_team_members_user_role 
ON team_members(user_id, role);

-- ============================================
-- INDIVIDUAL GAME ATTENDANCE OPTIMIZATIONS
-- ============================================

-- For: WHERE request_id = X AND status = 'pending'
CREATE INDEX IF NOT EXISTS idx_individual_attendance_request_status 
ON individual_game_attendance(request_id, status);

-- For: WHERE user_id = X AND status = 'accepted'
CREATE INDEX IF NOT EXISTS idx_individual_attendance_user_status 
ON individual_game_attendance(user_id, status);

-- ============================================
-- COMMENTS
-- ============================================
-- These indexes significantly improve query performance at scale
-- They optimize the most common query patterns in the application

