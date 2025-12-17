-- ============================================
-- RPC Functions for Business Logic
-- ============================================

-- ============================================
-- APPROVE TEAM VS TEAM INVITE
-- ============================================
-- This function handles the approval of a team vs team invite
-- It creates attendance records for both teams
CREATE OR REPLACE FUNCTION approve_team_vs_team_invite(
    p_invite_id UUID,
    p_request_id UUID,
    p_target_team_id UUID,
    p_actor_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_request_team_id UUID;
    v_request_team_members UUID[];
    v_target_team_members UUID[];
BEGIN
    -- Get the requesting team ID
    SELECT team_id INTO v_request_team_id
    FROM instant_match_requests
    WHERE id = p_request_id;
    
    IF v_request_team_id IS NULL THEN
        RAISE EXCEPTION 'Match request not found';
    END IF;
    
    -- Update invite status
    UPDATE instant_request_invites
    SET status = 'accepted',
        updated_at = NOW()
    WHERE id = p_invite_id
      AND request_id = p_request_id
      AND target_team_id = p_target_team_id
      AND status = 'pending';
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invite not found or already processed';
    END IF;
    
    -- Update match request status
    UPDATE instant_match_requests
    SET status = 'matched',
        matched_team_id = p_target_team_id,
        last_updated_at = NOW()
    WHERE id = p_request_id;
    
    -- Get all members from both teams
    SELECT ARRAY_AGG(user_id) INTO v_request_team_members
    FROM team_members
    WHERE team_id = v_request_team_id;
    
    SELECT ARRAY_AGG(user_id) INTO v_target_team_members
    FROM team_members
    WHERE team_id = p_target_team_id;
    
    -- Create attendance records for requesting team members
    IF v_request_team_members IS NOT NULL THEN
        INSERT INTO team_match_attendance (request_id, user_id, team_id, status, created_at, updated_at)
        SELECT 
            p_request_id,
            user_id,
            v_request_team_id,
            'pending',
            NOW(),
            NOW()
        FROM UNNEST(v_request_team_members) AS user_id
        ON CONFLICT (request_id, user_id) DO NOTHING;
    END IF;
    
    -- Create attendance records for target team members
    IF v_target_team_members IS NOT NULL THEN
        INSERT INTO team_match_attendance (request_id, user_id, team_id, status, created_at, updated_at)
        SELECT 
            p_request_id,
            user_id,
            p_target_team_id,
            'pending',
            NOW(),
            NOW()
        FROM UNNEST(v_target_team_members) AS user_id
        ON CONFLICT (request_id, user_id) DO NOTHING;
    END IF;
    
    -- Auto-accept for the actor (the person who approved)
    UPDATE team_match_attendance
    SET status = 'accepted',
        updated_at = NOW()
    WHERE request_id = p_request_id
      AND user_id = p_actor_user_id;
    
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION approve_team_vs_team_invite(UUID, UUID, UUID, UUID) TO authenticated;

-- ============================================
-- ACCEPT PENDING ADMIN MATCH
-- ============================================
-- This function creates an invite for a pending admin match
-- It verifies the user is an admin of the target team before creating the invite
CREATE OR REPLACE FUNCTION accept_pending_admin_match(
    p_request_id UUID,
    p_target_team_id UUID,
    p_actor_user_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_invite_id UUID;
    v_is_admin BOOLEAN;
BEGIN
    -- Verify the actor is an admin of the target team
    SELECT EXISTS(
        SELECT 1
        FROM team_members
        WHERE team_id = p_target_team_id
          AND user_id = p_actor_user_id
          AND LOWER(role) = 'admin'
    ) INTO v_is_admin;
    
    IF NOT v_is_admin THEN
        RAISE EXCEPTION 'User is not an admin of the target team';
    END IF;
    
    -- Check if request exists and is valid
    IF NOT EXISTS(
        SELECT 1
        FROM instant_match_requests
        WHERE id = p_request_id
          AND status IN ('pending', 'open')
          AND mode = 'team_vs_team'
    ) THEN
        RAISE EXCEPTION 'Match request not found or invalid';
    END IF;
    
    -- Check if invite already exists
    IF EXISTS(
        SELECT 1
        FROM instant_request_invites
        WHERE request_id = p_request_id
          AND target_team_id = p_target_team_id
    ) THEN
        RAISE EXCEPTION 'Invite already exists for this team';
    END IF;
    
    -- Create the invite
    INSERT INTO instant_request_invites (
        request_id,
        target_team_id,
        status,
        target_type,
        created_at,
        updated_at
    )
    VALUES (
        p_request_id,
        p_target_team_id,
        'pending',
        'team',
        NOW(),
        NOW()
    )
    RETURNING id INTO v_invite_id;
    
    RETURN v_invite_id;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION accept_pending_admin_match(UUID, UUID, UUID) TO authenticated;

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

-- ============================================
-- GET CONFIRMED MATCHES FOR USER
-- ============================================
-- This function returns confirmed team matches where the user has responded (accepted or declined)
-- It bypasses RLS to ensure all users can see their confirmed matches
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
    user_team_id UUID
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
        tma.team_id AS user_team_id
    FROM instant_match_requests imr
    INNER JOIN team_match_attendance tma ON tma.request_id = imr.id
    WHERE tma.user_id = p_user_id
      AND tma.status IN ('accepted', 'declined')
      AND imr.mode = 'team_vs_team'
      AND imr.status != 'cancelled'
      AND imr.matched_team_id IS NOT NULL;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION get_confirmed_matches_for_user(UUID) TO authenticated;

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

