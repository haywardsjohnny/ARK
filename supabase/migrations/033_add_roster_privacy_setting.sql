-- Add privacy settings to hide team rosters by default
-- Each team admin can control their own team's roster visibility to the opponent
-- When false (default), opponent team can only see counts (available, not available, pending)
-- When true, opponent team can see individual player names

ALTER TABLE instant_match_requests
ADD COLUMN IF NOT EXISTS show_team_a_roster BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS show_team_b_roster BOOLEAN DEFAULT false;

COMMENT ON COLUMN instant_match_requests.show_team_a_roster IS 
'Controlled by Team A admin. When false (default), Team B can only see attendance counts for Team A, not individual player names. When true, Team B can see Team A full roster.';

COMMENT ON COLUMN instant_match_requests.show_team_b_roster IS 
'Controlled by Team B admin. When false (default), Team A can only see attendance counts for Team B, not individual player names. When true, Team A can see Team B full roster.';

-- Update RPC functions to include this field
DROP FUNCTION IF EXISTS get_match_requests_for_attendance(UUID, UUID[]);

CREATE OR REPLACE FUNCTION get_match_requests_for_attendance(
    p_user_id UUID,
    p_request_ids UUID[]
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
    status TEXT,
    expected_players_per_team INTEGER,
    created_by UUID,
    creator_id UUID,
    show_team_a_roster BOOLEAN,
    show_team_b_roster BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Verify user has attendance records for these requests
    IF NOT EXISTS (
        SELECT 1
        FROM team_match_attendance
        WHERE user_id = p_user_id
          AND request_id = ANY(p_request_ids)
    ) THEN
        -- Return empty result if user has no attendance records
        RETURN;
    END IF;

    -- Return match requests (bypasses RLS due to SECURITY DEFINER)
    RETURN QUERY
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
        imr.status,
        imr.expected_players_per_team,
        imr.created_by,
        imr.creator_id,
        imr.show_team_a_roster,
        imr.show_team_b_roster
    FROM instant_match_requests imr
    WHERE imr.id = ANY(p_request_ids)
      AND imr.mode = 'team_vs_team';
END;
$$;

GRANT EXECUTE ON FUNCTION get_match_requests_for_attendance(UUID, UUID[]) TO authenticated;

COMMENT ON FUNCTION get_match_requests_for_attendance(UUID, UUID[]) IS
'Returns match requests for which the user has attendance records. Includes show_team_a_roster and show_team_b_roster fields for privacy settings.';

-- Update get_all_matches_for_user to include show_team_a_roster and show_team_b_roster
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

-- Update get_confirmed_matches_for_user to include show_team_a_roster and show_team_b_roster
DROP FUNCTION IF EXISTS get_confirmed_matches_for_user(UUID);

CREATE OR REPLACE FUNCTION get_confirmed_matches_for_user(
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
    -- Return only confirmed (accepted) match requests
    -- This bypasses RLS due to SECURITY DEFINER
    RETURN QUERY
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
      AND tma.status = 'accepted'
      AND imr.mode = 'team_vs_team'
      AND imr.matched_team_id IS NOT NULL
      AND imr.status != 'cancelled';
END;
$$;

GRANT EXECUTE ON FUNCTION get_confirmed_matches_for_user(UUID) TO authenticated;

