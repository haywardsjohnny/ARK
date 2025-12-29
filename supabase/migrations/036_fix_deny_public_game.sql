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

