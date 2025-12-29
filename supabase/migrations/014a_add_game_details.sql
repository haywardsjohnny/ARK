-- Add details/notes field to instant_match_requests
-- This allows game creators to add additional information about the game

ALTER TABLE instant_match_requests
ADD COLUMN IF NOT EXISTS details TEXT;

-- Add comment for documentation
COMMENT ON COLUMN instant_match_requests.details IS 'Optional details/notes about the game provided by the organizer';

