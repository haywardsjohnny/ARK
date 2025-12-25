-- Fix circular reference in individual_game_attendance SELECT policy
-- The third condition causes infinite recursion and is redundant
-- Users can see their own records (first condition) and organizers can see all records for their games (second condition)

DROP POLICY IF EXISTS "Users can view attendance for games they're part of" ON individual_game_attendance;

CREATE POLICY "Users can view attendance for games they're part of"
  ON individual_game_attendance FOR SELECT
  USING (
    user_id = auth.uid()
    OR request_id IN (
      SELECT id FROM instant_match_requests WHERE created_by = auth.uid()
    )
  );

