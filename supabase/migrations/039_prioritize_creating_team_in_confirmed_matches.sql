-- Migration: Prioritize creating team in confirmed matches
-- When a user has attendance records for both creating team and invited team,
-- prioritize the creating team (team_id) over the matched team (matched_team_id)

-- Drop all overloaded versions to avoid PostgREST ambiguity
DROP FUNCTION IF EXISTS get_confirmed_matches_for_user(UUID, INTEGER, INTEGER);
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
    -- Prioritize creating team (team_id) over matched team (matched_team_id) for user_team_id
    -- This bypasses RLS due to SECURITY DEFINER
    RETURN QUERY
    WITH user_attendance AS (
        -- Get all accepted attendance records for the user
        SELECT DISTINCT ON (tma.request_id)
            tma.request_id,
            tma.team_id,
            tma.status,
            -- Prioritize creating team: if user has attendance for creating team, use that
            -- Otherwise use matched team attendance
            CASE 
                WHEN tma.team_id = imr.team_id THEN 0  -- Creating team priority
                ELSE 1  -- Matched team priority
            END AS priority
        FROM team_match_attendance tma
        INNER JOIN instant_match_requests imr ON imr.id = tma.request_id
        WHERE tma.user_id = p_user_id
          AND tma.status = 'accepted'
          AND imr.mode = 'team_vs_team'
          AND imr.matched_team_id IS NOT NULL
          AND imr.status != 'cancelled'
        ORDER BY tma.request_id, 
                 CASE WHEN tma.team_id = imr.team_id THEN 0 ELSE 1 END
    )
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
        ua.status AS user_attendance_status,
        -- Use the prioritized team_id (creating team if available, otherwise matched team)
        COALESCE(ua.team_id, imr.team_id) AS user_team_id,
        imr.expected_players_per_team,
        imr.chat_enabled,
        imr.chat_mode,
        imr.show_team_a_roster,
        imr.show_team_b_roster
    FROM instant_match_requests imr
    INNER JOIN user_attendance ua ON ua.request_id = imr.id
    WHERE imr.mode = 'team_vs_team'
      AND imr.matched_team_id IS NOT NULL
      AND imr.status != 'cancelled';
END;
$$;

GRANT EXECUTE ON FUNCTION get_confirmed_matches_for_user(UUID) TO authenticated;

COMMENT ON FUNCTION get_confirmed_matches_for_user(UUID) IS 
'Returns confirmed team matches for a user. Prioritizes the creating team (team_id) over the matched team when user has attendance records for both teams.';

