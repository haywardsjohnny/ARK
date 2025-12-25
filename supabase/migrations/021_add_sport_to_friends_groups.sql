-- Add sport column to friends_groups table
ALTER TABLE friends_groups
ADD COLUMN IF NOT EXISTS sport TEXT;

-- Create index for sport
CREATE INDEX IF NOT EXISTS idx_friends_groups_sport ON friends_groups(sport);

