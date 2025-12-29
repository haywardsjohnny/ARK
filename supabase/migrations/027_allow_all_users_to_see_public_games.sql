-- Allow ALL authenticated users to see public games (individual and team)
-- This enables public game discovery for all users, not just team admins
-- Individual public games should be visible to everyone

-- Drop the existing restrictive policy if it exists (it only allowed team admins)
DROP POLICY IF EXISTS "Public games discoverable by admins" ON instant_match_requests;

-- Drop the policy if it already exists (for idempotency)
DROP POLICY IF EXISTS "All users can see public games" ON instant_match_requests;

-- Create a new policy that allows ALL authenticated users to see public games
-- This ensures public games (both individual and team) are visible to everyone
CREATE POLICY "All users can see public games"
ON instant_match_requests
FOR SELECT
TO authenticated
USING (
  -- Allow if visibility is public or is_public flag is true
  (visibility = 'public' OR is_public = true)
  -- No additional restrictions - all authenticated users can see public games
);

-- Add comment for documentation
COMMENT ON POLICY "All users can see public games" ON instant_match_requests IS 
'Allows all authenticated users to discover and view public games (both individual and team games). This replaces the previous policy that only allowed team admins to see public games.';
