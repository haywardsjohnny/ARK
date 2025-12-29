-- Fix accept_pending_admin_match to properly handle public games
-- For public games where another team has already created an invite,
-- we need to accept that invite and confirm the game

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
    v_game_team_id UUID;
    v_is_public BOOLEAN;
    v_visibility TEXT;
    v_existing_invite_id UUID;
    v_existing_invite_team_id UUID;
BEGIN
    -- Verify the actor is an admin of the target team
    SELECT EXISTS(
        SELECT 1
        FROM team_members
        WHERE team_id = p_target_team_id
          AND user_id = p_actor_user_id
          AND LOWER(role) IN ('admin', 'captain')
    ) INTO v_is_admin;
    
    IF NOT v_is_admin THEN
        RAISE EXCEPTION 'User is not an admin of the target team';
    END IF;
    
    -- Get game details
    SELECT team_id, is_public, visibility INTO v_game_team_id, v_is_public, v_visibility
    FROM instant_match_requests
    WHERE id = p_request_id
      AND status IN ('pending', 'open')
      AND mode = 'team_vs_team';
    
    IF v_game_team_id IS NULL THEN
        RAISE EXCEPTION 'Match request not found or invalid';
    END IF;
    
    -- Check if this is a public game created by the target team
    -- (i.e., another team has requested to join)
    IF (v_is_public = true OR v_visibility = 'public') AND v_game_team_id = p_target_team_id THEN
        -- PUBLIC GAME: Find the existing invite from another team and accept it
        SELECT id, target_team_id INTO v_existing_invite_id, v_existing_invite_team_id
        FROM instant_request_invites
        WHERE request_id = p_request_id
          AND target_team_id != p_target_team_id  -- Invite from another team (not the creating team)
          AND status = 'pending'
        LIMIT 1;
        
        IF v_existing_invite_id IS NULL THEN
            RAISE EXCEPTION 'No pending invite found from another team';
        END IF;
        
        -- Accept the invite (update status to 'accepted')
        UPDATE instant_request_invites
        SET status = 'accepted',
            updated_at = NOW()
        WHERE id = v_existing_invite_id;
        
        -- Confirm the game: set matched_team_id and update status
        UPDATE instant_match_requests
        SET matched_team_id = v_existing_invite_team_id,
            status = 'matched',
            last_updated_at = NOW()
        WHERE id = p_request_id;
        
        -- Create attendance records for both teams
        -- Team A (creating team)
        INSERT INTO team_match_attendance (request_id, team_id, user_id, status)
        SELECT p_request_id, v_game_team_id, user_id, 'pending'
        FROM team_members
        WHERE team_id = v_game_team_id
        ON CONFLICT (request_id, user_id) DO NOTHING;
        
        -- Team X (joining team)
        INSERT INTO team_match_attendance (request_id, team_id, user_id, status)
        SELECT p_request_id, v_existing_invite_team_id, user_id, 'pending'
        FROM team_members
        WHERE team_id = v_existing_invite_team_id
        ON CONFLICT (request_id, user_id) DO NOTHING;
        
        RETURN v_existing_invite_id;
    ELSE
        -- INVITE-SPECIFIC TEAM LOGIC: Create invite from target team to the game
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
    END IF;
END;
$$;

COMMENT ON FUNCTION accept_pending_admin_match(UUID, UUID, UUID) IS
'Accepts a pending admin match. For public games created by the target team, accepts the existing invite from another team and confirms the game. For invite-specific games, creates a new invite from the target team.';

