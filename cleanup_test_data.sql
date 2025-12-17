-- ⚠️ DANGER: This will delete ALL match data and invites
-- Only run this on a development/test database
-- DO NOT run on production

-- Step 1: Delete in correct order to respect foreign key constraints

-- Delete hidden games
DELETE FROM user_hidden_games;

-- Delete team match attendance records
DELETE FROM team_match_attendance;

-- Delete match invites
DELETE FROM instant_request_invites;

-- Delete match requests
DELETE FROM instant_match_requests;

-- Optional: If you want to start completely fresh with teams too, uncomment below:
-- DELETE FROM team_members;
-- DELETE FROM team_admin_requests;
-- DELETE FROM teams;

-- Optional: If you want to clean friendships too, uncomment below:
-- DELETE FROM friends;

-- Reset sequences (optional, to start IDs from 1 again)
-- This is not necessary but makes IDs cleaner for testing
-- No sequences to reset as we use UUIDs

-- Verify deletion
SELECT 'instant_match_requests' as table_name, COUNT(*) as remaining_rows FROM instant_match_requests
UNION ALL
SELECT 'instant_request_invites', COUNT(*) FROM instant_request_invites
UNION ALL
SELECT 'team_match_attendance', COUNT(*) FROM team_match_attendance
UNION ALL
SELECT 'user_hidden_games', COUNT(*) FROM user_hidden_games
UNION ALL
SELECT 'teams', COUNT(*) FROM teams
UNION ALL
SELECT 'team_members', COUNT(*) FROM team_members
UNION ALL
SELECT 'friends', COUNT(*) FROM friends;

-- Success message
SELECT 'Test data cleaned successfully! You can now create fresh test data from the app.' as status;

