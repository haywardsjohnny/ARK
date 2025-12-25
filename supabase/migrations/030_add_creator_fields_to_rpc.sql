-- Add created_by and creator_id to get_match_requests_for_attendance RPC function
-- This ensures we can display creator names without needing a separate query that might fail due to RLS

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
    creator_id UUID
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
        RAISE EXCEPTION 'User does not have attendance records for these requests';
    END IF;

    -- Return match requests that the user has attendance records for
    -- This bypasses RLS to ensure all members (not just admins) can see games
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
        imr.creator_id
    FROM instant_match_requests imr
    WHERE imr.id = ANY(p_request_ids);
END;
$$;

GRANT EXECUTE ON FUNCTION get_match_requests_for_attendance(UUID, UUID[]) TO authenticated;

COMMENT ON FUNCTION get_match_requests_for_attendance(UUID, UUID[]) IS
'Returns match requests for which the user has attendance records. Includes created_by and creator_id fields for displaying creator names.';

