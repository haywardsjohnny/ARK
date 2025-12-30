-- Add home location columns to users table
-- This allows users to set their home city/state/zip during profile setup
-- Instead of relying on device location, which is slow and requires permissions
-- This will significantly improve app startup and discovery loading performance

ALTER TABLE users
ADD COLUMN IF NOT EXISTS home_city TEXT,
ADD COLUMN IF NOT EXISTS home_state TEXT,
ADD COLUMN IF NOT EXISTS home_zip_code TEXT;

-- Add comments for documentation
COMMENT ON COLUMN users.home_city IS 'User''s home city, set during profile setup for faster app loading';
COMMENT ON COLUMN users.home_state IS 'User''s home state, set during profile setup for faster app loading';
COMMENT ON COLUMN users.home_zip_code IS 'User''s home ZIP code, set during profile setup. Used for game discovery distance calculations without device location.';

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_users_home_zip_code ON users(home_zip_code);

-- Populate home_zip_code from last_known_zip_code for existing users (backward compatibility)
-- This ensures existing users have a home location without requiring them to set it manually
UPDATE users
SET home_zip_code = last_known_zip_code
WHERE home_zip_code IS NULL 
  AND last_known_zip_code IS NOT NULL 
  AND last_known_zip_code != '';

-- If base_zip_code exists and home_zip_code is still null, use that
UPDATE users
SET home_zip_code = base_zip_code
WHERE home_zip_code IS NULL 
  AND base_zip_code IS NOT NULL 
  AND base_zip_code != '';

