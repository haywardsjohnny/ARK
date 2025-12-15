-- ============================================
-- Fixes and Optimizations
-- Based on the error we fixed earlier
-- ============================================

-- Ensure time_slot columns don't exist (they were removed)
-- This migration ensures the schema matches the app code

-- If time_slot_1 or time_slot_2 columns exist, remove them
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'instant_match_requests' 
        AND column_name = 'time_slot_1'
    ) THEN
        ALTER TABLE instant_match_requests DROP COLUMN time_slot_1;
    END IF;
    
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'instant_match_requests' 
        AND column_name = 'time_slot_2'
    ) THEN
        ALTER TABLE instant_match_requests DROP COLUMN time_slot_2;
    END IF;
END $$;

-- Add any missing indexes that might improve performance
CREATE INDEX IF NOT EXISTS idx_match_requests_created_at 
    ON instant_match_requests(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_match_requests_start_time_1 
    ON instant_match_requests(start_time_1) 
    WHERE start_time_1 IS NOT NULL;

-- Add composite index for common queries
CREATE INDEX IF NOT EXISTS idx_match_requests_sport_zip_status 
    ON instant_match_requests(sport, zip_code, status) 
    WHERE status != 'cancelled';

