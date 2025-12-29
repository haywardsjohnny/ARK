-- Add unique constraint on (request_id, target_team_id) for instant_request_invites
-- This allows ON CONFLICT to work properly in the deny function

-- First, check if constraint already exists and drop it if it does
DO $$
BEGIN
    -- Drop the constraint if it exists
    IF EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'instant_request_invites_request_target_unique'
    ) THEN
        ALTER TABLE instant_request_invites 
        DROP CONSTRAINT instant_request_invites_request_target_unique;
    END IF;
END $$;

-- Add unique constraint
ALTER TABLE instant_request_invites
ADD CONSTRAINT instant_request_invites_request_target_unique 
UNIQUE (request_id, target_team_id);

COMMENT ON CONSTRAINT instant_request_invites_request_target_unique ON instant_request_invites IS
'Ensures that each team can only have one invite per game request. This allows ON CONFLICT to work properly when updating invite status.';

