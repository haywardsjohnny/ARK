-- ============================================
-- DELETE TEST GAME DATA
-- ============================================
-- This script deletes all game-related test data while preserving:
-- - User profiles (users table)
-- - Teams (teams table)
-- - Team members (team_members table)
-- - Friends (friends table)
-- - Friends groups (friends_groups table)
-- - Friends group members (friends_group_members table)
-- - User sports (user_sports table)
--
-- Tables that WILL be deleted:
-- - All games (instant_match_requests)
-- - Game invites (instant_request_invites)
-- - Team game attendance (team_match_attendance)
-- - Individual game attendance (individual_game_attendance)
-- - Game messages/chat (game_messages)
--
-- IMPORTANT: Run these queries in order due to foreign key constraints
-- ============================================

-- 1. Delete all game messages/chat
DELETE FROM game_messages;

-- 2. Delete all individual game attendance records
DELETE FROM individual_game_attendance;

-- 3. Delete all team game attendance records
DELETE FROM team_match_attendance;

-- 4. Delete all game invites
DELETE FROM instant_request_invites;

-- 5. Delete all game/match requests (this will cascade to any remaining child records)
DELETE FROM instant_match_requests;

-- ============================================
-- VERIFICATION QUERIES (Optional - run to verify deletion)
-- ============================================

-- Check remaining game data (should all return 0)
-- SELECT COUNT(*) as remaining_games FROM instant_match_requests;
-- SELECT COUNT(*) as remaining_invites FROM instant_request_invites;
-- SELECT COUNT(*) as remaining_team_attendance FROM team_match_attendance;
-- SELECT COUNT(*) as remaining_individual_attendance FROM individual_game_attendance;
-- SELECT COUNT(*) as remaining_messages FROM game_messages;

-- ============================================
-- ALTERNATIVE: Delete only specific test data
-- ============================================
-- If you want to keep some games and only delete test data, you can use WHERE clauses:

-- Example: Delete games created by specific test users
-- DELETE FROM game_messages WHERE request_id IN (
--   SELECT id FROM instant_match_requests WHERE created_by IN (
--     SELECT id FROM users WHERE email LIKE '%test%' OR email LIKE '%example%'
--   )
-- );
-- DELETE FROM individual_game_attendance WHERE request_id IN (
--   SELECT id FROM instant_match_requests WHERE created_by IN (
--     SELECT id FROM users WHERE email LIKE '%test%' OR email LIKE '%example%'
--   )
-- );
-- DELETE FROM team_match_attendance WHERE request_id IN (
--   SELECT id FROM instant_match_requests WHERE created_by IN (
--     SELECT id FROM users WHERE email LIKE '%test%' OR email LIKE '%example%'
--   )
-- );
-- DELETE FROM instant_request_invites WHERE request_id IN (
--   SELECT id FROM instant_match_requests WHERE created_by IN (
--     SELECT id FROM users WHERE email LIKE '%test%' OR email LIKE '%example%'
--   )
-- );
-- DELETE FROM instant_match_requests WHERE created_by IN (
--   SELECT id FROM users WHERE email LIKE '%test%' OR email LIKE '%example%'
-- );

-- Example: Delete games created before a specific date
-- DELETE FROM game_messages WHERE request_id IN (
--   SELECT id FROM instant_match_requests WHERE created_at < '2024-01-01'
-- );
-- DELETE FROM individual_game_attendance WHERE request_id IN (
--   SELECT id FROM instant_match_requests WHERE created_at < '2024-01-01'
-- );
-- DELETE FROM team_match_attendance WHERE request_id IN (
--   SELECT id FROM instant_match_requests WHERE created_at < '2024-01-01'
-- );
-- DELETE FROM instant_request_invites WHERE request_id IN (
--   SELECT id FROM instant_match_requests WHERE created_at < '2024-01-01'
-- );
-- DELETE FROM instant_match_requests WHERE created_at < '2024-01-01';

