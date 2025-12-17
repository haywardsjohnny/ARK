-- ============================================
-- ACCEPT PENDING ADMIN MATCH RPC Function
-- ============================================
-- This function creates an invite for a pending admin match
-- It verifies the user is an admin of the target team before creating the invite
-- ============================================

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
    
    -- Check if invite already exists - if so, return the existing invite ID
    SELECT id INTO v_invite_id
    FROM instant_request_invites
    WHERE request_id = p_request_id
      AND target_team_id = p_target_team_id;
    
    -- If invite already exists, return it (idempotent operation)
    IF v_invite_id IS NOT NULL THEN
        RETURN v_invite_id;
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

