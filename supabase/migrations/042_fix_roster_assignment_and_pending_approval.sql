-- Fix roster assignment and pending approval logic for invite-specific games
-- Rules:
-- 1. Admins always stay on their admin team side (if they're admin of one of the teams in the game)
-- 2. Members on both teams take precedence towards creating team
-- 3. Pending approval should be sent to:
--    - All creating team admins/members (except those who are admins of accepting team)
--    - All accepting team members (except those who are on creating team side)

CREATE OR REPLACE FUNCTION accept_pending_admin_match(
    p_request_id UUID,
    p_target_team_id UUID,
    p_actor_user_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_invite_id UUID;
    v_is_admin BOOLEAN;
    v_game_team_id UUID;
    v_is_public BOOLEAN;
    v_visibility TEXT;
    v_game_status TEXT;
    v_existing_invite_id UUID;
    v_existing_invite_team_id UUID;
    v_existing_invite_status TEXT;
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
    SELECT team_id, is_public, visibility, status INTO v_game_team_id, v_is_public, v_visibility, v_game_status
    FROM instant_match_requests
    WHERE id = p_request_id;

    -- Check if request exists and is valid
    IF v_game_team_id IS NULL THEN
        RAISE EXCEPTION 'Match request not found or invalid';
    END IF;
    
    -- If game is already matched/cancelled, don't allow further accepts
    IF v_game_status IN ('matched', 'confirmed', 'cancelled') THEN
        RAISE EXCEPTION 'Game is already matched, confirmed, or cancelled';
    END IF;

    -- Case 1: Public game where p_target_team_id is the CREATING team (Team A)
    -- This means another team (Team X) has clicked "Join" and created a pending invite
    IF v_game_team_id = p_target_team_id AND (v_visibility = 'public' OR v_is_public = true) THEN
        -- Find the pending invite from the responding team (Team X)
        SELECT id, target_team_id, status INTO v_existing_invite_id, v_existing_invite_team_id, v_existing_invite_status
        FROM instant_request_invites
        WHERE request_id = p_request_id
          AND target_team_id != p_target_team_id -- Must be from another team
          AND status = 'pending'
        LIMIT 1;

        IF v_existing_invite_id IS NULL THEN
            RAISE EXCEPTION 'No pending invite found from another team for this public game.';
        END IF;

        -- Update the invite status to 'accepted'
        UPDATE instant_request_invites
        SET status = 'accepted', updated_at = NOW()
        WHERE id = v_existing_invite_id;

        -- Update the instant_match_requests to set matched_team_id and status to 'matched'
        UPDATE instant_match_requests
        SET matched_team_id = v_existing_invite_team_id,
            status = 'matched',
            last_updated_at = NOW()
        WHERE id = p_request_id;

        -- Create/update attendance records for both teams
        -- IMPORTANT: Process joining team FIRST, then creating team
        -- This ensures that users who are admins of joining team get records for joining team
        -- and then are excluded from creating team records
        
        -- Step 1: Team X (joining team): Include ALL members (including admins)
        -- This must be done FIRST so that admins of joining team get records for joining team
        -- Use DO UPDATE to ensure status is set to 'pending' even if record already exists
        INSERT INTO team_match_attendance (request_id, team_id, user_id, status)
        SELECT p_request_id, v_existing_invite_team_id, user_id, 'pending'
        FROM team_members
        WHERE team_id = v_existing_invite_team_id
        ON CONFLICT (request_id, user_id) 
        DO UPDATE SET 
          team_id = EXCLUDED.team_id,  -- Update team_id to joining team (prioritize joining team)
          status = 'pending';  -- Ensure status is pending for availability check
        
        -- Step 2: Team A (creating team): Include all members EXCEPT those who are admins of the joining team
        -- Use a CTE to get the list of users to insert/update
        WITH creating_team_users AS (
          SELECT tm_a.user_id
          FROM team_members tm_a
          WHERE tm_a.team_id = v_game_team_id
            -- Exclude users who are admins of the joining team
            -- (They should only have records for joining team, not creating team)
            AND NOT EXISTS (
                SELECT 1
                FROM team_members tm_joining
                WHERE tm_joining.team_id = v_existing_invite_team_id
                  AND tm_joining.user_id = tm_a.user_id
                  AND LOWER(tm_joining.role) IN ('admin', 'captain')
            )
        )
        INSERT INTO team_match_attendance (request_id, team_id, user_id, status)
        SELECT p_request_id, v_game_team_id, user_id, 'pending'
        FROM creating_team_users
        ON CONFLICT (request_id, user_id) 
        DO UPDATE SET 
          -- Update to creating team's values
          -- Note: Admins of joining team are excluded by the WHERE clause in the CTE,
          -- so if we reach here, the user should be on the creating team
          -- In DO UPDATE, unqualified column names refer to the existing row
          -- EXCLUDED refers to the new row being inserted
          team_id = EXCLUDED.team_id,  -- Update to creating team
          status = 'pending';  -- Always set to pending for availability check

        RETURN v_existing_invite_id;

    -- Case 2: Invite-specific game OR public game where p_target_team_id is an INVITED team (Team B/C)
    ELSE
        -- Check if invite already exists for this specific target team
        SELECT id, status INTO v_invite_id, v_existing_invite_status
        FROM instant_request_invites
        WHERE request_id = p_request_id
          AND target_team_id = p_target_team_id;
        
        -- If invite already exists and is accepted, return it (idempotent operation)
        IF v_invite_id IS NOT NULL AND v_existing_invite_status = 'accepted' THEN
            RETURN v_invite_id;
        END IF;

        -- If invite exists but is pending/denied, update it to accepted
        IF v_invite_id IS NOT NULL THEN
            UPDATE instant_request_invites
            SET status = 'accepted', updated_at = NOW()
            WHERE id = v_invite_id;
        ELSE
            -- Create a new invite with 'accepted' status
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
                'accepted', -- Directly set to accepted for invite-specific games
                'team',
                NOW(),
                NOW()
            )
            RETURNING id INTO v_invite_id;
        END IF;

        -- Update the instant_match_requests to set matched_team_id and status to 'matched'
        -- This confirms the game with the first accepting team
        UPDATE instant_match_requests
        SET matched_team_id = p_target_team_id,
            status = 'matched',
            last_updated_at = NOW()
        WHERE id = p_request_id
          AND matched_team_id IS NULL; -- Only update if not already matched

        -- Create/update attendance records for both teams
        -- RULES:
        -- 1. Admins always stay on their admin team side (if they're admin of one of the teams in the game)
        -- 2. Members on both teams take precedence towards creating team
        -- 3. Process accepting team FIRST, then creating team
        
        -- Step 1: Team B/C (accepting team): Include ALL members
        -- Rule: Admins always stay on their admin team side
        -- Members who are also on creating team will be handled in Step 2 (creating team takes precedence)
        INSERT INTO team_match_attendance (request_id, team_id, user_id, status)
        SELECT p_request_id, p_target_team_id, user_id, 'pending'
        FROM team_members
        WHERE team_id = p_target_team_id
        ON CONFLICT (request_id, user_id) 
        DO UPDATE SET 
          -- If user is admin of accepting team, keep them on accepting team
          -- Otherwise, they'll be updated to creating team in Step 2
          team_id = CASE 
            WHEN EXISTS (
              SELECT 1 FROM team_members tm
              WHERE tm.team_id = p_target_team_id
                AND tm.user_id = EXCLUDED.user_id
                AND LOWER(tm.role) IN ('admin', 'captain')
            ) THEN EXCLUDED.team_id  -- Keep on accepting team (admin priority)
            ELSE EXCLUDED.team_id  -- For now, keep on accepting team (will be overridden in Step 2 if user is also on creating team)
          END,
          status = 'pending';
        
        -- Step 2: Team A (creating team): Include ALL members EXCEPT admins of accepting team
        -- Rule: Members on both teams take precedence towards creating team
        -- This includes:
        -- - All members of creating team who are NOT admins of accepting team
        -- - Members who are on both teams (creating team takes precedence)
        -- - Admins of other teams (not involved in this game) who are members of creating team
        WITH creating_team_users AS (
          SELECT tm_a.user_id
          FROM team_members tm_a
          WHERE tm_a.team_id = v_game_team_id
            -- Exclude users who are admins of the accepting team
            -- (They should only have records for accepting team, not creating team)
            -- Rule: Admins always stay on their admin team side
            AND NOT EXISTS (
                SELECT 1
                FROM team_members tm_accepting
                WHERE tm_accepting.team_id = p_target_team_id
                  AND tm_accepting.user_id = tm_a.user_id
                  AND LOWER(tm_accepting.role) IN ('admin', 'captain')
            )
        )
        INSERT INTO team_match_attendance (request_id, team_id, user_id, status)
        SELECT p_request_id, v_game_team_id, user_id, 'pending'
        FROM creating_team_users
        ON CONFLICT (request_id, user_id) 
        DO UPDATE SET 
          -- Update to creating team's values
          -- Note: Admins of accepting team are excluded by the WHERE clause in the CTE,
          -- so if we reach here, the user should be on the creating team
          -- Creating team takes precedence for members who are on both teams
          -- This will override the team_id set in Step 1 for members who are on both teams
          team_id = EXCLUDED.team_id,  -- Update to creating team (creating team takes precedence)
          status = 'pending';  -- Always set to pending for availability check

        RETURN v_invite_id;
    END IF;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION accept_pending_admin_match(UUID, UUID, UUID) TO authenticated;

COMMENT ON FUNCTION accept_pending_admin_match(UUID, UUID, UUID) IS
'Accepts a pending admin match. For public games created by the target team, accepts the existing invite from another team and confirms the game. For invite-specific games, accepts the invite, confirms the game with the accepting team, and creates attendance records for both teams. Roster assignment rules: 1) Admins always stay on their admin team side, 2) Members on both teams take precedence towards creating team.';

