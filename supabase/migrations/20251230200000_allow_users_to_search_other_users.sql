-- Allow authenticated users to search and view other users' profiles
-- This enables search functionality and viewing team member profiles

-- Drop the restrictive policy that only allows users to see their own profile
DROP POLICY IF EXISTS "Users can read own profile" ON users;

-- Create a new policy that allows all authenticated users to see other users
-- This is needed for:
-- 1. Search functionality (finding players by name, email, phone, ZIP)
-- 2. Viewing team member profiles
-- 3. Viewing friend profiles
-- 4. General user discovery

CREATE POLICY "Authenticated users can view all user profiles"
    ON users FOR SELECT
    TO authenticated
    USING (true);

-- Keep the update policy that only allows users to update their own profile
-- (This should already exist, but we'll ensure it's there)
DROP POLICY IF EXISTS "Users can update own profile" ON users;

CREATE POLICY "Users can update own profile"
    ON users FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- Add comment for documentation
COMMENT ON POLICY "Authenticated users can view all user profiles" ON users IS 
'Allows all authenticated users to view other users profiles. This enables search functionality, viewing team members, and user discovery. Users can still only update their own profiles.';

