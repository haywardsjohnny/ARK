-- ============================================
-- ADD NOTIFICATION PREFERENCES
-- ============================================
-- Add notification preference fields to users and teams tables
-- Default: Users - 25 miles for all sports, Teams - 50 miles for team sport

-- Add notification preferences to users table
ALTER TABLE users 
  ADD COLUMN IF NOT EXISTS notification_radius_miles INTEGER DEFAULT 25,
  ADD COLUMN IF NOT EXISTS notification_sports TEXT[] DEFAULT ARRAY[]::TEXT[]; -- Empty array = all sports

-- Add notification preferences to teams table
ALTER TABLE teams 
  ADD COLUMN IF NOT EXISTS notification_radius_miles INTEGER DEFAULT 50;

-- Set default values for existing users (25 miles, all sports = empty array)
UPDATE users 
SET notification_radius_miles = 25,
    notification_sports = ARRAY[]::TEXT[]
WHERE notification_radius_miles IS NULL;

-- Set default values for existing teams (50 miles)
UPDATE teams 
SET notification_radius_miles = 50
WHERE notification_radius_miles IS NULL;

-- Add comments for documentation
COMMENT ON COLUMN users.notification_radius_miles IS 'Radius in miles for public game notifications. Default: 25 miles.';
COMMENT ON COLUMN users.notification_sports IS 'Array of sports to get notified about. Empty array = all sports. Default: all sports.';
COMMENT ON COLUMN teams.notification_radius_miles IS 'Radius in miles for team game notifications. Default: 50 miles. Based on team sport.';

