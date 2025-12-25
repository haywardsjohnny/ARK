-- Fix RLS policy on instant_request_invites to allow creating team admins to see invites
-- Currently, only invited team admins can see invites, but creating team admins also need access
-- Use SECURITY DEFINER function to avoid circular RLS dependencies

-- Create a SECURITY DEFINER function to check if user is member of creating team (bypasses RLS)
CREATE OR REPLACE FUNCTION is_member_of_creating_team(request_id_param UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 
    FROM instant_match_requests imr
    INNER JOIN team_members tm ON tm.team_id = imr.team_id
    WHERE imr.id = request_id_param
      AND tm.user_id = auth.uid()
  );
END;
$$;

-- Create a SECURITY DEFINER function to check if user is admin of creating team (bypasses RLS)
CREATE OR REPLACE FUNCTION is_admin_of_creating_team(request_id_param UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 
    FROM instant_match_requests imr
    INNER JOIN team_members tm ON tm.team_id = imr.team_id
    WHERE imr.id = request_id_param
      AND tm.user_id = auth.uid()
      AND tm.role IN ('admin', 'captain')
  );
END;
$$;

-- Drop the existing policy
DROP POLICY IF EXISTS "Team admins can view invites" ON instant_request_invites;
DROP POLICY IF EXISTS "Team admins can read invites" ON instant_request_invites;

-- Create a new policy that allows:
-- 1. Members of the creating team (where instant_match_requests.team_id matches their team)
-- 2. Members of invited teams (where target_team_id matches their team) - not just admins
-- Using SECURITY DEFINER function to avoid circular RLS dependencies
CREATE POLICY "Team admins can view invites"
    ON instant_request_invites FOR SELECT
    USING (
        -- Allow if user is a member of the creating team (using function to bypass RLS)
        -- This allows all team members (not just admins) to see invites for games their team created
        is_member_of_creating_team(request_id)
        OR
        -- Allow if user is a member of an invited team (not just admins)
        -- This allows team members to see invites (including denied status) for their team
        EXISTS (
            SELECT 1 FROM team_members
            WHERE team_members.team_id = instant_request_invites.target_team_id
              AND team_members.user_id = auth.uid()
        )
    );

COMMENT ON POLICY "Team admins can view invites" ON instant_request_invites IS
'Allows team members to view invites for games where their team is either the creating team or an invited team. This enables team members to see denied invites so they can be filtered out. Uses SECURITY DEFINER function to avoid circular RLS dependencies.';

COMMENT ON FUNCTION is_member_of_creating_team(UUID) IS
'Checks if the current user is a member of the team that created the game. Uses SECURITY DEFINER to bypass RLS and avoid circular dependencies.';

COMMENT ON FUNCTION is_admin_of_creating_team(UUID) IS
'Checks if the current user is an admin of the team that created the game. Uses SECURITY DEFINER to bypass RLS and avoid circular dependencies.';

