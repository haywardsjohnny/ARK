-- Add expected_players_per_team column to instant_match_requests
-- This allows organizers to specify how many players are needed per team for the match

ALTER TABLE instant_match_requests
ADD COLUMN IF NOT EXISTS expected_players_per_team INTEGER;

-- Add comment for documentation
COMMENT ON COLUMN instant_match_requests.expected_players_per_team IS 
'Number of players expected per team for this match. Used to calculate availability percentage. If NULL, defaults to sport-specific values.';

