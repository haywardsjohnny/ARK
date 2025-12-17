-- Add expected_players_per_team column back to instant_match_requests
-- This allows per-match customization of expected players (overrides sport default)

ALTER TABLE instant_match_requests
ADD COLUMN IF NOT EXISTS expected_players_per_team INTEGER;

-- Add comment for documentation
COMMENT ON COLUMN instant_match_requests.expected_players_per_team IS 
'Number of players expected per team for this specific match. If NULL, uses the default from sport_expected_players table.';

