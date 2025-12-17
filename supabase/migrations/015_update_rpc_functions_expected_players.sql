-- Update RPC functions to include expected_players_per_team in return types
-- This migration drops and recreates the functions with the updated return types

-- ============================================
-- UPDATE get_match_requests_for_attendance
-- ============================================
-- Drop and recreate to add expected_players_per_team
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
    expected_players_per_team INTEGER
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
        imr.expected_players_per_team
    FROM instant_match_requests imr
    WHERE imr.id = ANY(p_request_ids)
      AND imr.mode = 'team_vs_team';
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_match_requests_for_attendance(UUID, UUID[]) TO authenticated;

-- ============================================
-- UPDATE get_confirmed_matches_for_user
-- ============================================
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
    status TEXT,
    created_by UUID,
    creator_id UUID,
    user_attendance_status TEXT,
    user_team_id UUID,
    expected_players_per_team INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Return confirmed match requests where user has responded (accepted or declined)
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
        imr.status,
        imr.created_by,
        imr.creator_id,
        tma.status AS user_attendance_status,
        tma.team_id AS user_team_id,
        imr.expected_players_per_team
    FROM instant_match_requests imr
    INNER JOIN team_match_attendance tma ON tma.request_id = imr.id
    WHERE tma.user_id = p_user_id
      AND tma.status IN ('accepted', 'declined')
      AND imr.mode = 'team_vs_team'
      AND imr.status != 'cancelled'
      AND imr.matched_team_id IS NOT NULL;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_confirmed_matches_for_user(UUID) TO authenticated;

-- ============================================
-- UPDATE get_all_matches_for_user
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
    status TEXT,
    created_by UUID,
    creator_id UUID,
    user_attendance_status TEXT,
    user_team_id UUID,
    expected_players_per_team INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Return all match requests where user has responded (accepted or declined)
    -- This includes cancelled matches. This bypasses RLS due to SECURITY DEFINER
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
        imr.created_by,
        imr.creator_id,
        tma.status AS user_attendance_status,
        tma.team_id AS user_team_id,
        imr.expected_players_per_team
    FROM instant_match_requests imr
    INNER JOIN team_match_attendance tma ON tma.request_id = imr.id
    WHERE tma.user_id = p_user_id
      AND tma.status IN ('accepted', 'declined')
      AND imr.mode = 'team_vs_team'
      AND imr.matched_team_id IS NOT NULL;
    -- Note: We include cancelled matches here (no status filter)
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_all_matches_for_user(UUID) TO authenticated;

