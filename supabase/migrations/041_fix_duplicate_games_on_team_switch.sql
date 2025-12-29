-- Fix duplicate games when user switches teams
-- When a user is the creator of a team game AND has an attendance record,
-- the RPC function was returning the game twice (once from each UNION clause).
-- This migration fixes it by excluding team games with attendance records
-- from the "created by" clause.

-- Drop ALL overloaded versions of the function to avoid ambiguity
DROP FUNCTION IF EXISTS get_all_matches_for_user(UUID);
DROP FUNCTION IF EXISTS get_all_matches_for_user(UUID, INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION get_all_matches_for_user(
    p_user_id UUID
)
RETURNS TABLE (
    id UUID,
    sport TEXT,
    mode TEXT,
    zip_code TEXT,
    team_id UUID,
    matched_team_id UUID,
    start_time_1 TIMESTAMPTZ,
    start_time_2 TIMESTAMPTZ,
    venue TEXT,
    details TEXT,
    status TEXT,
    created_by UUID,
    creator_id UUID,
    user_attendance_status TEXT,
    user_team_id UUID,
    expected_players_per_team INTEGER,
    chat_enabled BOOLEAN,
    chat_mode TEXT,
    show_team_a_roster BOOLEAN,
    show_team_b_roster BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Return all match requests where:
    -- 1. User has attendance record (team games with accepted/declined status)
    -- 2. User created the game (any mode, any status except cancelled)
    --    BUT exclude team games where user already has an attendance record
    --    (to prevent duplicates when user switches teams)
    -- 3. User has individual game attendance record (individual games)
    
    RETURN QUERY
    -- Team games where user has attendance
    SELECT 
        imr.id,
        imr.sport,
        imr.mode,
        imr.zip_code,
        imr.team_id,
        imr.matched_team_id,
        imr.start_time_1,
        imr.start_time_2,
        imr.venue,
        imr.details,
        imr.status,
        imr.created_by,
        imr.creator_id,
        tma.status AS user_attendance_status,
        tma.team_id AS user_team_id,
        imr.expected_players_per_team,
        imr.chat_enabled,
        imr.chat_mode,
        imr.show_team_a_roster,
        imr.show_team_b_roster
    FROM instant_match_requests imr
    INNER JOIN team_match_attendance tma ON tma.request_id = imr.id
    WHERE tma.user_id = p_user_id
      AND tma.status IN ('accepted', 'declined')
      AND imr.mode = 'team_vs_team'
      AND imr.matched_team_id IS NOT NULL
      AND imr.status != 'cancelled'
    
    UNION
    
    -- Games created by user (team or individual)
    -- BUT exclude team games where user already has an attendance record
    -- (those are handled in the first UNION above)
    SELECT 
        imr.id,
        imr.sport,
        imr.mode,
        imr.zip_code,
        imr.team_id,
        imr.matched_team_id,
        imr.start_time_1,
        imr.start_time_2,
        imr.venue,
        imr.details,
        imr.status,
        imr.created_by,
        imr.creator_id,
        'accepted' AS user_attendance_status, -- Creator is always "accepted"
        imr.team_id AS user_team_id, -- Use creating team for team games
        imr.expected_players_per_team,
        imr.chat_enabled,
        imr.chat_mode,
        imr.show_team_a_roster,
        imr.show_team_b_roster
    FROM instant_match_requests imr
    WHERE imr.created_by = p_user_id
      AND imr.status != 'cancelled'
      -- Exclude team games where user already has an attendance record
      -- (to prevent duplicates when user switches teams)
      AND NOT EXISTS (
          SELECT 1
          FROM team_match_attendance tma
          WHERE tma.request_id = imr.id
            AND tma.user_id = p_user_id
            AND tma.status IN ('accepted', 'declined')
            AND imr.mode = 'team_vs_team'
            AND imr.matched_team_id IS NOT NULL
      )
    
    UNION
    
    -- Individual games where user has attendance record
    SELECT 
        imr.id,
        imr.sport,
        imr.mode,
        imr.zip_code,
        imr.team_id,
        imr.matched_team_id,
        imr.start_time_1,
        imr.start_time_2,
        imr.venue,
        imr.details,
        imr.status,
        imr.created_by,
        imr.creator_id,
        iga.status AS user_attendance_status,
        NULL::UUID AS user_team_id, -- Individual games don't have team_id
        imr.expected_players_per_team,
        imr.chat_enabled,
        imr.chat_mode,
        NULL::BOOLEAN AS show_team_a_roster, -- Not applicable for individual games
        NULL::BOOLEAN AS show_team_b_roster -- Not applicable for individual games
    FROM instant_match_requests imr
    INNER JOIN individual_game_attendance iga ON iga.request_id = imr.id
    WHERE iga.user_id = p_user_id
      AND imr.mode != 'team_vs_team'
      AND imr.status != 'cancelled';
    
    -- Note: We include cancelled matches only if user created them (handled in second UNION)
END;
$$;

GRANT EXECUTE ON FUNCTION get_all_matches_for_user(UUID) TO authenticated;

COMMENT ON FUNCTION get_all_matches_for_user(UUID) IS
'Returns all match requests for a user. Prevents duplicates when user is creator and has attendance record by excluding team games with attendance from the "created by" clause.';

