-- Fix get_all_matches_for_user to include games created by user and individual games
-- ============================================
DROP FUNCTION IF EXISTS get_all_matches_for_user(UUID);

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
    chat_mode TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Return all match requests where:
    -- 1. User has attendance record (team games with accepted/declined status)
    -- 2. User created the game (any mode, any status except cancelled)
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
        imr.chat_mode
    FROM instant_match_requests imr
    INNER JOIN team_match_attendance tma ON tma.request_id = imr.id
    WHERE tma.user_id = p_user_id
      AND tma.status IN ('accepted', 'declined')
      AND imr.mode = 'team_vs_team'
      AND imr.matched_team_id IS NOT NULL
      AND imr.status != 'cancelled'
    
    UNION
    
    -- Games created by user (team or individual)
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
        imr.chat_mode
    FROM instant_match_requests imr
    WHERE imr.created_by = p_user_id
      AND imr.status != 'cancelled'
    
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
        imr.chat_mode
    FROM instant_match_requests imr
    INNER JOIN individual_game_attendance iga ON iga.request_id = imr.id
    WHERE iga.user_id = p_user_id
      AND imr.mode != 'team_vs_team'
      AND imr.status != 'cancelled';
    
    -- Note: We include cancelled matches only if user created them (handled in second UNION)
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_all_matches_for_user(UUID) TO authenticated;

