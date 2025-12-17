-- Migration: Add RPC function to deny pending admin matches
-- This allows admins to decline public game invites

-- Drop the function if it exists (for idempotency)
DROP FUNCTION IF EXISTS deny_pending_admin_match(uuid, uuid, uuid);

-- Create RPC function to deny a pending admin match
-- This bypasses RLS to create a "denied" invite
CREATE OR REPLACE FUNCTION deny_pending_admin_match(
  p_request_id uuid,
  p_target_team_id uuid,
  p_actor_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Insert a denied invite (or update if exists)
  INSERT INTO instant_request_invites (
    request_id,
    target_team_id,
    status,
    created_at,
    updated_at
  )
  VALUES (
    p_request_id,
    p_target_team_id,
    'denied',
    NOW(),
    NOW()
  )
  ON CONFLICT (request_id, target_team_id)
  DO UPDATE SET
    status = 'denied',
    updated_at = NOW();
  
  -- Log the action (optional, for debugging)
  RAISE NOTICE 'Admin match denied: request_id=%, target_team_id=%, actor=%', 
    p_request_id, p_target_team_id, p_actor_user_id;
END;
$$;

-- Add comment for documentation
COMMENT ON FUNCTION deny_pending_admin_match IS 
'Allows team admins to deny/decline pending admin matches by creating a denied invite. Uses SECURITY DEFINER to bypass RLS.';

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION deny_pending_admin_match TO authenticated;

