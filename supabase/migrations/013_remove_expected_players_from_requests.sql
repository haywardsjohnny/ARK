-- Remove expected_players_per_team column from instant_match_requests
-- This column is no longer needed as we're using the sport_expected_players lookup table

ALTER TABLE instant_match_requests
DROP COLUMN IF EXISTS expected_players_per_team;

