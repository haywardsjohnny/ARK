-- Add last_known_zip_code column to users table
-- This stores the user's last successfully retrieved ZIP code
-- Used as fallback when current location fails to load

ALTER TABLE users
ADD COLUMN IF NOT EXISTS last_known_zip_code TEXT;

-- Add comment for documentation
COMMENT ON COLUMN users.last_known_zip_code IS 
'Stores the user''s last successfully retrieved ZIP code. Used as fallback when current location fails to load.';

