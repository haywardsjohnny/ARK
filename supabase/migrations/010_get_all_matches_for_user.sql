-- ============================================
-- GET ALL MATCHES FOR USER (including cancelled)
-- ============================================
-- This function returns all team matches where the user has responded (accepted or declined)
-- including cancelled matches. It bypasses RLS to ensure all users can see their matches
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
    user_team_id UUID
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
        tma.team_id AS user_team_id
    FROM instant_match_requests imr
    INNER JOIN team_match_attendance tma ON tma.request_id = imr.id
    WHERE tma.user_id = p_user_id
      AND tma.status IN ('accepted', 'declined')
      AND imr.mode = 'team_vs_team'
      AND imr.matched_team_id IS NOT NULL;
    -- Note: We include cancelled matches here (no status filter)
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_all_matches_for_user(UUID) TO authenticated;

