-- ============================================
-- GET MATCH REQUESTS FOR ATTENDANCE
-- ============================================
-- This function returns match requests for which the user has attendance records
-- It bypasses RLS to ensure users can see requests they're involved in
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
    status TEXT
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
        imr.status
    FROM instant_match_requests imr
    WHERE imr.id = ANY(p_request_ids)
      AND imr.mode = 'team_vs_team';
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_match_requests_for_attendance(UUID, UUID[]) TO authenticated;

