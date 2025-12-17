-- ============================================
-- Team Admin Requests Table
-- Allows users to request admin rights for teams they're members of
-- ============================================

-- Create table if it doesn't exist
CREATE TABLE IF NOT EXISTS team_admin_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    team_id UUID NOT NULL REFERENCES teams(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reason TEXT,
    status TEXT DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add missing columns if they don't exist
DO $$
BEGIN
    -- Add approved_by column if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'team_admin_requests' 
        AND column_name = 'approved_by'
    ) THEN
        ALTER TABLE team_admin_requests 
        ADD COLUMN approved_by UUID REFERENCES users(id) ON DELETE SET NULL;
    END IF;
    
    -- Add reviewed_at column if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'team_admin_requests' 
        AND column_name = 'reviewed_at'
    ) THEN
        ALTER TABLE team_admin_requests 
        ADD COLUMN reviewed_at TIMESTAMPTZ;
    END IF;
    
    -- Add unique constraint if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'team_admin_requests_team_id_user_id_key'
    ) THEN
        ALTER TABLE team_admin_requests 
        ADD CONSTRAINT team_admin_requests_team_id_user_id_key 
        UNIQUE(team_id, user_id);
    END IF;
    
    -- Add status check constraint if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'team_admin_requests_status_check'
    ) THEN
        ALTER TABLE team_admin_requests 
        ADD CONSTRAINT team_admin_requests_status_check 
        CHECK (status IN ('pending', 'approved', 'denied'));
    END IF;
END $$;

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_team_admin_requests_team_id ON team_admin_requests(team_id);
CREATE INDEX IF NOT EXISTS idx_team_admin_requests_user_id ON team_admin_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_team_admin_requests_status ON team_admin_requests(status);
CREATE INDEX IF NOT EXISTS idx_team_admin_requests_approved_by ON team_admin_requests(approved_by);

-- Trigger for updated_at (drop and recreate to ensure it's correct)
DROP TRIGGER IF EXISTS update_team_admin_requests_updated_at ON team_admin_requests;
CREATE TRIGGER update_team_admin_requests_updated_at BEFORE UPDATE ON team_admin_requests
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- Row Level Security (RLS) Policies
-- ============================================

-- Enable RLS
ALTER TABLE team_admin_requests ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist (to allow re-running migration)
DROP POLICY IF EXISTS "Anyone can read team admin requests" ON team_admin_requests;
DROP POLICY IF EXISTS "Users can create admin requests" ON team_admin_requests;
DROP POLICY IF EXISTS "Team admins can update admin requests" ON team_admin_requests;
DROP POLICY IF EXISTS "Users can delete their own pending requests" ON team_admin_requests;

-- Anyone can read team admin requests (for transparency)
CREATE POLICY "Anyone can read team admin requests"
    ON team_admin_requests FOR SELECT
    USING (true);

-- Users can create their own admin requests
CREATE POLICY "Users can create admin requests"
    ON team_admin_requests FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Team admins can update (approve/deny) requests for their teams
CREATE POLICY "Team admins can update admin requests"
    ON team_admin_requests FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM team_members
            WHERE team_members.team_id = team_admin_requests.team_id
            AND team_members.user_id = auth.uid()
            AND team_members.role = 'admin'
        )
    );

-- Users can delete their own pending requests
CREATE POLICY "Users can delete their own pending requests"
    ON team_admin_requests FOR DELETE
    USING (
        auth.uid() = user_id 
        AND status = 'pending'
    );

-- ============================================
-- RPC Function: Approve/Deny Admin Request
-- ============================================

CREATE OR REPLACE FUNCTION approve_team_admin_request(
    request_id_param UUID,
    approve BOOLEAN
)
RETURNS BOOLEAN AS $$
DECLARE
    request_record RECORD;
    is_admin BOOLEAN;
BEGIN
    -- Get the request
    SELECT * INTO request_record
    FROM team_admin_requests
    WHERE id = request_id_param
    AND status = 'pending';
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Request not found or already processed';
    END IF;
    
    -- Check if current user is an admin of the team
    SELECT EXISTS (
        SELECT 1 FROM team_members
        WHERE team_id = request_record.team_id
        AND user_id = auth.uid()
        AND role = 'admin'
    ) INTO is_admin;
    
    IF NOT is_admin THEN
        RAISE EXCEPTION 'Only team admins can approve/deny requests';
    END IF;
    
    -- Update the request status
    UPDATE team_admin_requests
    SET 
        status = CASE WHEN approve THEN 'approved' ELSE 'denied' END,
        approved_by = auth.uid(),
        reviewed_at = NOW()
    WHERE id = request_id_param;
    
    -- If approved, update the user's role in team_members
    IF approve THEN
        -- Use INSERT ... ON CONFLICT to handle both cases:
        -- 1. User is already a member -> update role to admin
        -- 2. User is not a member -> insert as admin
        INSERT INTO team_members (team_id, user_id, role)
        VALUES (request_record.team_id, request_record.user_id, 'admin')
        ON CONFLICT (team_id, user_id) 
        DO UPDATE SET role = 'admin';
    END IF;
    
    RETURN TRUE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION approve_team_admin_request(UUID, BOOLEAN) TO authenticated;

