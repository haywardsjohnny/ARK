-- Allow users to insert their own attendance records when requesting to join individual games
-- This enables the "Request to Join" functionality for public individual games

-- Drop existing insert policy if it exists (we'll recreate it with additional conditions)
DROP POLICY IF EXISTS "Organizers can insert attendance records" ON individual_game_attendance;

-- Create policy that allows:
-- 1. Organizers to insert attendance records for their games
-- 2. Users to insert their own attendance records (for requesting to join public games)
CREATE POLICY "Organizers and users can insert attendance records"
  ON individual_game_attendance FOR INSERT
  WITH CHECK (
    -- Organizers can insert for their games
    request_id IN (
      SELECT id FROM instant_match_requests WHERE created_by = auth.uid()
    )
    OR
    -- Users can insert their own attendance records (for requesting to join)
    (
      user_id = auth.uid()
      AND status = 'pending'
      AND request_id IN (
        SELECT id FROM instant_match_requests 
        WHERE visibility = 'public' OR is_public = true
      )
    )
  );

-- Add comment for documentation
COMMENT ON POLICY "Organizers and users can insert attendance records" ON individual_game_attendance IS 
  'Allows organizers to create attendance records for their games, and users to request to join public games by creating their own pending attendance records.';

