-- Fix missing updated_at column in instant_request_invites table
-- This ensures the approve function can update the updated_at timestamp

-- Add updated_at column if it doesn't exist
ALTER TABLE instant_request_invites
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- Create trigger for updated_at if it doesn't exist
DROP TRIGGER IF EXISTS update_invites_updated_at ON instant_request_invites;
CREATE TRIGGER update_invites_updated_at 
    BEFORE UPDATE ON instant_request_invites
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

