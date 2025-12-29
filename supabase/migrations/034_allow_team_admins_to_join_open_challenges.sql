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

