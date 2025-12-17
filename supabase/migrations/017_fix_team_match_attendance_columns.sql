-- Fix missing created_at and updated_at columns in team_match_attendance table
-- This ensures the approve function can create attendance records properly

-- Add created_at column if it doesn't exist
ALTER TABLE team_match_attendance
ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();

-- Add updated_at column if it doesn't exist
ALTER TABLE team_match_attendance
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- Create trigger for updated_at if it doesn't exist
DROP TRIGGER IF EXISTS update_attendance_updated_at ON team_match_attendance;
CREATE TRIGGER update_attendance_updated_at 
    BEFORE UPDATE ON team_match_attendance
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

