-- ============================================================================
-- COMBINED MIGRATIONS 034-041
-- Run this entire file in your SQL editor
-- ============================================================================

-- ============================================================================
-- MIGRATION 034: Allow team admins to join open challenges
-- ============================================================================
-- Allow team admins to create invites when joining open challenge games
-- This enables the "Join" functionality for open challenge public team games

-- Create a SECURITY DEFINER function to check if user can join open challenge
-- This bypasses RLS to avoid infinite recursion
CREATE OR REPLACE FUNCTION can_join_open_challenge_game(
    p_request_id UUID,
    p_target_team_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Check if user is admin of the joining team
    IF NOT EXISTS (
        SELECT 1 FROM team_members
        WHERE team_id = p_target_team_id
          AND user_id = auth.uid()
          AND role IN ('admin', 'captain')
    ) THEN
        RETURN FALSE;
    END IF;
    
    -- Check if the game is public/open challenge and not matched yet
    RETURN EXISTS (
        SELECT 1 FROM instant_match_requests
        WHERE id = p_request_id
          AND mode = 'team_vs_team'
          AND status != 'cancelled'
          AND matched_team_id IS NULL  -- No team has been matched yet (still open)
          AND (
              visibility = 'public'
              OR is_public = true
              OR status = 'open'
          )
    );
END;
$$;

-- Drop existing INSERT policy if it exists
DROP POLICY IF EXISTS "Team admins can create invites to join open challenges" ON instant_request_invites;

-- Create INSERT policy for team admins to join open challenge games
-- Uses SECURITY DEFINER function to avoid infinite recursion
CREATE POLICY "Team admins can create invites to join open challenges"
    ON instant_request_invites FOR INSERT
    WITH CHECK (
        -- Use SECURITY DEFINER function to check permissions (bypasses RLS)
        can_join_open_challenge_game(
            instant_request_invites.request_id,
            instant_request_invites.target_team_id
        )
        AND
        -- Status must be 'pending' (new invites are always pending)
        instant_request_invites.status = 'pending'
    );

COMMENT ON POLICY "Team admins can create invites to join open challenges" ON instant_request_invites IS
'Allows team admins to create invites when joining open challenge public team games. This enables the "Join" functionality where teams can request to join an open challenge game. Uses SECURITY DEFINER function to avoid infinite recursion.';

COMMENT ON FUNCTION can_join_open_challenge_game(UUID, UUID) IS
'Checks if the current user (as admin of target_team_id) can join an open challenge game. Uses SECURITY DEFINER to bypass RLS and avoid infinite recursion.';

-- ============================================================================
-- MIGRATION 035: Fix accept public game
-- ============================================================================
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

-- ============================================================================
-- MIGRATION 036: Fix deny public game
-- ============================================================================
-- Fix deny_pending_admin_match to handle public games correctly
-- For public games: verify actor is admin of creating team, deny responding team's invite
-- For non-public games: verify actor is admin of target team, deny that team's invite

DROP FUNCTION IF EXISTS deny_pending_admin_match(uuid, uuid, uuid);

CREATE OR REPLACE FUNCTION deny_pending_admin_match(
  p_request_id uuid,
  p_target_team_id uuid, -- For public games: responding team ID (Team X). For non-public: target team ID
  p_actor_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_game_team_id uuid;
  v_is_public boolean;
  v_visibility text;
  v_is_admin boolean;
  v_creating_team_id uuid;
BEGIN
  -- Get game details
  SELECT team_id, is_public, visibility INTO v_game_team_id, v_is_public, v_visibility
  FROM instant_match_requests
  WHERE id = p_request_id;
  
  IF v_game_team_id IS NULL THEN
    RAISE EXCEPTION 'Match request not found';
  END IF;
  
  -- Determine which team the actor must be an admin of
  -- For public games: actor must be admin of creating team (Team A)
  -- For non-public games: actor must be admin of target team
  IF (v_is_public = true OR v_visibility = 'public') THEN
    -- PUBLIC GAME: Verify actor is admin of creating team
    v_creating_team_id := v_game_team_id;
    SELECT EXISTS(
      SELECT 1
      FROM team_members
      WHERE team_id = v_creating_team_id
        AND user_id = p_actor_user_id
        AND LOWER(role) IN ('admin', 'captain')
    ) INTO v_is_admin;
    
    IF NOT v_is_admin THEN
      RAISE EXCEPTION 'User is not an admin of the creating team';
    END IF;
    
    -- For public games, p_target_team_id is the responding team (Team X) that requested to join
    -- We need to deny their invite
  ELSE
    -- NON-PUBLIC GAME: Verify actor is admin of target team
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
  END IF;
  
  -- Insert or update the invite to 'denied' status
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
    'denied',
    'team',
    NOW(),
    NOW()
  )
  ON CONFLICT (request_id, target_team_id)
  DO UPDATE SET
    status = 'denied',
    updated_at = NOW();
  
  -- Log the action (optional, for debugging)
  RAISE NOTICE 'Admin match denied: request_id=%, target_team_id=%, actor=%, is_public=%', 
    p_request_id, p_target_team_id, p_actor_user_id, (v_is_public = true OR v_visibility = 'public');
END;
$$;

COMMENT ON FUNCTION deny_pending_admin_match IS 
'Allows team admins to deny/decline pending admin matches. For public games, verifies actor is admin of creating team and denies responding team''s invite. For non-public games, verifies actor is admin of target team. Uses SECURITY DEFINER to bypass RLS.';

GRANT EXECUTE ON FUNCTION deny_pending_admin_match TO authenticated;

-- ============================================================================
-- MIGRATION 037: Add unique constraint invites
-- ============================================================================
-- Add unique constraint on (request_id, target_team_id) for instant_request_invites
-- This allows ON CONFLICT to work properly in the deny function

-- First, check if constraint already exists and drop it if it does
DO $$
BEGIN
    -- Drop the constraint if it exists
    IF EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'instant_request_invites_request_target_unique'
    ) THEN
        ALTER TABLE instant_request_invites 
        DROP CONSTRAINT instant_request_invites_request_target_unique;
    END IF;
END $$;

-- Add unique constraint
ALTER TABLE instant_request_invites
ADD CONSTRAINT instant_request_invites_request_target_unique 
UNIQUE (request_id, target_team_id);

COMMENT ON CONSTRAINT instant_request_invites_request_target_unique ON instant_request_invites IS
'Ensures that each team can only have one invite per game request. This allows ON CONFLICT to work properly when updating invite status.';

-- ============================================================================
-- MIGRATION 038: Ensure teams have admins
-- ============================================================================
-- Migration: Ensure all teams have at least one admin
-- 1. One-time fix: Assign admin role to first member of teams with no admins
-- 2. Add trigger to prevent removing the last admin
-- 3. Add trigger to ensure creator gets admin role when team is created

-- ============================================
-- ONE-TIME FIX: Assign admin to teams with no admins
-- ============================================
-- Temporarily disable ALL UPDATE triggers on team_members to allow the fix
DO $$
DECLARE
    team_record RECORD;
    first_member_id UUID;
    trigger_rec RECORD;
    disabled_triggers TEXT[] := ARRAY[]::TEXT[];
    i INTEGER;
BEGIN
    -- Disable ALL UPDATE triggers on team_members
    FOR trigger_rec IN
        SELECT trigger_name
        FROM information_schema.triggers
        WHERE event_object_table = 'team_members'
          AND event_manipulation = 'UPDATE'
    LOOP
        EXECUTE format('ALTER TABLE team_members DISABLE TRIGGER %I', trigger_rec.trigger_name);
        disabled_triggers := array_append(disabled_triggers, trigger_rec.trigger_name);
        RAISE NOTICE 'Temporarily disabled trigger: %', trigger_rec.trigger_name;
    END LOOP;
    
    -- Find all teams that have no admins
    FOR team_record IN
        SELECT t.id, t.name
        FROM teams t
        WHERE NOT EXISTS (
            SELECT 1
            FROM team_members tm
            WHERE tm.team_id = t.id
              AND LOWER(tm.role) IN ('admin', 'captain')
        )
    LOOP
        -- Get the first member (by id, which represents insertion order)
        SELECT tm.user_id INTO first_member_id
        FROM team_members tm
        WHERE tm.team_id = team_record.id
        ORDER BY tm.id ASC
        LIMIT 1;
        
        -- If team has members, assign first one as admin
        IF first_member_id IS NOT NULL THEN
            UPDATE team_members
            SET role = 'admin'
            WHERE team_id = team_record.id
              AND user_id = first_member_id;
            
            RAISE NOTICE 'Assigned admin role to user % for team % (%)', 
                first_member_id, team_record.id, team_record.name;
        ELSE
            -- Team has no members - this is a data integrity issue
            -- We'll log it but can't fix it automatically
            RAISE WARNING 'Team % (%) has no members and no admin - cannot auto-fix', 
                team_record.id, team_record.name;
        END IF;
    END LOOP;
    
    -- Re-enable all triggers we disabled
    FOR i IN 1..array_length(disabled_triggers, 1)
    LOOP
        EXECUTE format('ALTER TABLE team_members ENABLE TRIGGER %I', disabled_triggers[i]);
        RAISE NOTICE 'Re-enabled trigger: %', disabled_triggers[i];
    END LOOP;
END $$;

-- ============================================
-- TRIGGER FUNCTION: Ensure creator gets admin role
-- ============================================
CREATE OR REPLACE FUNCTION ensure_creator_is_admin()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    creator_id UUID;
BEGIN
    -- Get the creator_id from the teams table
    SELECT created_by INTO creator_id
    FROM teams
    WHERE id = NEW.team_id;
    
    -- If creator exists and this is the creator being added, ensure they're admin
    IF creator_id IS NOT NULL AND NEW.user_id = creator_id THEN
        -- Only set to admin if not already admin/captain
        IF LOWER(NEW.role) NOT IN ('admin', 'captain') THEN
            NEW.role := 'admin';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;

-- Create trigger to ensure creator gets admin role when added as member
DROP TRIGGER IF EXISTS ensure_creator_is_admin_trigger ON team_members;
CREATE TRIGGER ensure_creator_is_admin_trigger
    BEFORE INSERT ON team_members
    FOR EACH ROW
    EXECUTE FUNCTION ensure_creator_is_admin();

-- ============================================
-- TRIGGER FUNCTION: Prevent removing last admin
-- ============================================
CREATE OR REPLACE FUNCTION prevent_remove_last_admin()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    admin_count INTEGER;
    is_removing_admin BOOLEAN;
BEGIN
    -- Check if we're removing an admin
    is_removing_admin := (LOWER(OLD.role) IN ('admin', 'captain'));
    
    IF is_removing_admin THEN
        -- Count remaining admins after this deletion
        SELECT COUNT(*) INTO admin_count
        FROM team_members
        WHERE team_id = OLD.team_id
          AND user_id != OLD.user_id  -- Exclude the one being removed
          AND LOWER(role) IN ('admin', 'captain');
        
        -- If no admins will remain, prevent the deletion
        IF admin_count = 0 THEN
            RAISE EXCEPTION 'Cannot remove the last admin from a team. Please assign another admin first.';
        END IF;
    END IF;
    
    RETURN OLD;
END;
$$;

-- Create trigger to prevent removing last admin
DROP TRIGGER IF EXISTS prevent_remove_last_admin_trigger ON team_members;
CREATE TRIGGER prevent_remove_last_admin_trigger
    BEFORE DELETE ON team_members
    FOR EACH ROW
    EXECUTE FUNCTION prevent_remove_last_admin();

-- ============================================
-- TRIGGER FUNCTION: Prevent demoting last admin
-- ============================================
CREATE OR REPLACE FUNCTION prevent_demote_last_admin()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    admin_count INTEGER;
    was_admin BOOLEAN;
    is_admin BOOLEAN;
BEGIN
    -- Check if we're demoting an admin (changing from admin to non-admin)
    was_admin := (LOWER(OLD.role) IN ('admin', 'captain'));
    is_admin := (LOWER(NEW.role) IN ('admin', 'captain'));
    
    IF was_admin AND NOT is_admin THEN
        -- Count remaining admins after this update
        SELECT COUNT(*) INTO admin_count
        FROM team_members
        WHERE team_id = NEW.team_id
          AND user_id != NEW.user_id  -- Exclude the one being demoted
          AND LOWER(role) IN ('admin', 'captain');
        
        -- If no admins will remain, prevent the demotion
        IF admin_count = 0 THEN
            RAISE EXCEPTION 'Cannot demote the last admin from a team. Please assign another admin first.';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;

-- Create trigger to prevent demoting last admin
DROP TRIGGER IF EXISTS prevent_demote_last_admin_trigger ON team_members;
CREATE TRIGGER prevent_demote_last_admin_trigger
    BEFORE UPDATE ON team_members
    FOR EACH ROW
    WHEN (OLD.role IS DISTINCT FROM NEW.role)
    EXECUTE FUNCTION prevent_demote_last_admin();

-- ============================================
-- COMMENTS
-- ============================================
COMMENT ON FUNCTION ensure_creator_is_admin() IS
'Ensures that when a team creator is added as a member, they automatically get admin role.';

COMMENT ON FUNCTION prevent_remove_last_admin() IS
'Prevents deletion of the last admin from a team. Ensures teams always have at least one admin.';

COMMENT ON FUNCTION prevent_demote_last_admin() IS
'Prevents demoting the last admin from a team. Ensures teams always have at least one admin.';

-- ============================================================================
-- MIGRATION 039: Prioritize creating team in confirmed matches
-- ============================================================================
-- Migration: Prioritize creating team in confirmed matches
-- When a user has attendance records for both creating team and invited team,
-- prioritize the creating team (team_id) over the matched team (matched_team_id)

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

-- ============================================================================
-- MIGRATION 040: Fix accept invite specific game
-- ============================================================================
-- Fix accept_pending_admin_match to properly handle invite-specific games
-- When an admin accepts an invite-specific game, it should:
-- 1. Update/create the invite with status 'accepted'
-- 2. Set matched_team_id to the accepting team
-- 3. Set game status to 'matched'
-- 4. Create attendance records for both teams

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
        -- IMPORTANT: Process accepting team FIRST, then creating team
        -- This ensures that users who are admins of accepting team get records for accepting team
        -- and then are excluded from creating team records
        
        -- Step 1: Team B/C (accepting team): Include ALL members (including admins)
        -- This must be done FIRST so that admins of accepting team get records for accepting team
        -- Use DO UPDATE to ensure status is set to 'pending' even if record already exists
        INSERT INTO team_match_attendance (request_id, team_id, user_id, status)
        SELECT p_request_id, p_target_team_id, user_id, 'pending'
        FROM team_members
        WHERE team_id = p_target_team_id
        ON CONFLICT (request_id, user_id) 
        DO UPDATE SET 
          team_id = EXCLUDED.team_id,  -- Update team_id to accepting team (prioritize accepting team)
          status = 'pending';  -- Ensure status is pending for availability check
        
        -- Step 2: Team A (creating team): Include all members EXCEPT those who are admins of the accepting team
        -- (Admins of accepting team should only be on accepting team's roster - already handled above)
        -- Use DO UPDATE to ensure status is set to 'pending' even if record already exists
        -- BUT: If user is already on accepting team (from Step 1), don't update their team_id
        -- Step 2: Team A (creating team): Include all members EXCEPT those who are admins of the accepting team
        -- Use a CTE to get the list of users to insert/update
        WITH creating_team_users AS (
          SELECT tm_a.user_id
          FROM team_members tm_a
          WHERE tm_a.team_id = v_game_team_id
            -- Exclude users who are admins of the accepting team
            -- (They should only have records for accepting team, not creating team)
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
          -- In DO UPDATE, unqualified column names refer to the existing row
          -- EXCLUDED refers to the new row being inserted
          team_id = EXCLUDED.team_id,  -- Update to creating team
          status = 'pending';  -- Always set to pending for availability check

        RETURN v_invite_id;
    END IF;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION accept_pending_admin_match(UUID, UUID, UUID) TO authenticated;

COMMENT ON FUNCTION accept_pending_admin_match(UUID, UUID, UUID) IS
'Accepts a pending admin match. For public games created by the target team, accepts the existing invite from another team and confirms the game. For invite-specific games, accepts the invite, confirms the game with the accepting team, and creates attendance records for both teams.';

-- ============================================================================
-- MIGRATION 041: Fix duplicate games on team switch
-- ============================================================================
-- Fix duplicate games when user switches teams
-- When a user is the creator of a team game AND has an attendance record,
-- the RPC function was returning the game twice (once from each UNION clause).
-- This migration fixes it by excluding team games with attendance records
-- from the "created by" clause.

-- Drop ALL overloaded versions of the function to avoid ambiguity
DROP FUNCTION IF EXISTS get_all_matches_for_user(UUID);
DROP FUNCTION IF EXISTS get_all_matches_for_user(UUID, INTEGER, INTEGER);

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
    -- Return all match requests where:
    -- 1. User has attendance record (team games with accepted/declined status)
    -- 2. User created the game (any mode, any status except cancelled)
    --    BUT exclude team games where user already has an attendance record
    --    (to prevent duplicates when user switches teams)
    -- 3. User has individual game attendance record (individual games)
    
    RETURN QUERY
    -- Team games where user has attendance
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
        tma.status AS user_attendance_status,
        tma.team_id AS user_team_id,
        imr.expected_players_per_team,
        imr.chat_enabled,
        imr.chat_mode,
        imr.show_team_a_roster,
        imr.show_team_b_roster
    FROM instant_match_requests imr
    INNER JOIN team_match_attendance tma ON tma.request_id = imr.id
    WHERE tma.user_id = p_user_id
      AND tma.status IN ('accepted', 'declined')
      AND imr.mode = 'team_vs_team'
      AND imr.matched_team_id IS NOT NULL
      AND imr.status != 'cancelled'
    
    UNION
    
    -- Games created by user (team or individual)
    -- BUT exclude team games where user already has an attendance record
    -- (those are handled in the first UNION above)
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
        'accepted' AS user_attendance_status, -- Creator is always "accepted"
        imr.team_id AS user_team_id, -- Use creating team for team games
        imr.expected_players_per_team,
        imr.chat_enabled,
        imr.chat_mode,
        imr.show_team_a_roster,
        imr.show_team_b_roster
    FROM instant_match_requests imr
    WHERE imr.created_by = p_user_id
      AND imr.status != 'cancelled'
      -- Exclude team games where user already has an attendance record
      -- (to prevent duplicates when user switches teams)
      AND NOT EXISTS (
          SELECT 1
          FROM team_match_attendance tma
          WHERE tma.request_id = imr.id
            AND tma.user_id = p_user_id
            AND tma.status IN ('accepted', 'declined')
            AND imr.mode = 'team_vs_team'
            AND imr.matched_team_id IS NOT NULL
      )
    
    UNION
    
    -- Individual games where user has attendance record
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
        iga.status AS user_attendance_status,
        NULL::UUID AS user_team_id, -- Individual games don't have team_id
        imr.expected_players_per_team,
        imr.chat_enabled,
        imr.chat_mode,
        NULL::BOOLEAN AS show_team_a_roster, -- Not applicable for individual games
        NULL::BOOLEAN AS show_team_b_roster -- Not applicable for individual games
    FROM instant_match_requests imr
    INNER JOIN individual_game_attendance iga ON iga.request_id = imr.id
    WHERE iga.user_id = p_user_id
      AND imr.mode != 'team_vs_team'
      AND imr.status != 'cancelled';
    
    -- Note: We include cancelled matches only if user created them (handled in second UNION)
END;
$$;

GRANT EXECUTE ON FUNCTION get_all_matches_for_user(UUID) TO authenticated;

COMMENT ON FUNCTION get_all_matches_for_user(UUID) IS
'Returns all match requests for a user. Prevents duplicates when user is creator and has attendance record by excluding team games with attendance from the "created by" clause.';

-- ============================================================================
-- ALL MIGRATIONS COMPLETE
-- ============================================================================

