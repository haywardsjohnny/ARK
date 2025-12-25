-- Allow team admins to update games created by their team
-- Currently, only creators can update games, but team admins should also be able to cancel games

-- Drop the existing policy
DROP POLICY IF EXISTS "Creators can update match requests" ON instant_match_requests;

-- Create a new policy that allows:
-- 1. Creators (created_by or creator_id matches auth.uid())
-- 2. Team admins of the creating team (team_id matches their admin team)
CREATE POLICY "Creators and team admins can update match requests"
    ON instant_match_requests FOR UPDATE
    USING (
        -- Allow if user is the creator
        auth.uid() = created_by OR auth.uid() = creator_id
        OR
        -- Allow if user is an admin of the creating team
        EXISTS (
            SELECT 1 FROM team_members tm
            WHERE tm.team_id = instant_match_requests.team_id
              AND tm.user_id = auth.uid()
              AND tm.role IN ('admin', 'captain')
        )
    );

COMMENT ON POLICY "Creators and team admins can update match requests" ON instant_match_requests IS
'Allows creators and team admins of the creating team to update games (e.g., cancel games).';

