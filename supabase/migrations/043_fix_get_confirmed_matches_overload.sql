-- Fix function overloading issue for get_confirmed_matches_for_user
-- PostgREST cannot resolve between the single-parameter and three-parameter versions
-- Drop the overloaded version with p_limit and p_offset to keep only the single-parameter version

DROP FUNCTION IF EXISTS get_confirmed_matches_for_user(UUID, INTEGER, INTEGER);

-- Ensure only the single-parameter version exists
-- This is already defined in migration 039, but we need to make sure
-- the overloaded version is dropped

COMMENT ON FUNCTION get_confirmed_matches_for_user(UUID) IS 
'Returns confirmed team matches for a user. Prioritizes the creating team (team_id) over the matched team when user has attendance records for both teams.';

