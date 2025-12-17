-- Migration: Allow admins to discover public games of the same sport
-- This enables the "Discover" functionality for public team games

-- Drop the policy if it exists (for idempotency)
DROP POLICY IF EXISTS "Public games discoverable by admins" ON instant_match_requests;

-- Create a new policy that allows admins to see public games of sports they admin
CREATE POLICY "Public games discoverable by admins"
ON instant_match_requests
FOR SELECT
TO authenticated
USING (
  -- Allow if visibility is public or is_public flag is true
  (visibility = 'public' OR is_public = true)
  AND
  -- AND the user is an admin of a team in the same sport
  EXISTS (
    SELECT 1
    FROM team_members tm
    JOIN teams t ON t.id = tm.team_id
    WHERE tm.user_id = auth.uid()
      AND tm.role = 'admin'
      AND LOWER(t.sport) = LOWER(instant_match_requests.sport)
  )
);

-- Add comment for documentation
COMMENT ON POLICY "Public games discoverable by admins" ON instant_match_requests IS 
'Allows team admins to discover public games in the same sport, enabling the public game discovery feature.';

