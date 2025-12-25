-- Allow users to see individual games where they have pending attendance records
-- This fixes the issue where users can't see games they've been invited to via friends groups
-- Use SECURITY DEFINER function to avoid circular references

-- Create a SECURITY DEFINER function to check if user has pending attendance (bypasses RLS)
CREATE OR REPLACE FUNCTION user_has_pending_attendance(request_id_param UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM individual_game_attendance
    WHERE request_id = request_id_param
    AND user_id = auth.uid()
    AND status = 'pending'
  );
END;
$$;

-- Drop policy if it exists (for idempotency)
DROP POLICY IF EXISTS "Users can see games with pending attendance" ON instant_match_requests;

-- Create a policy that allows users to see games where they have pending attendance
-- Using the SECURITY DEFINER function to avoid circular references
CREATE POLICY "Users can see games with pending attendance"
  ON instant_match_requests FOR SELECT
  USING (
    -- User has a pending attendance record for this game (using function to bypass RLS)
    user_has_pending_attendance(id)
  );

