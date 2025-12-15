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

