-- Fix infinite recursion in friends_group_members RLS policy
-- The issue: friends_group_members policy checks friends_groups, which checks friends_group_members

-- Create a SECURITY DEFINER function to check if user created a group (bypasses RLS)
CREATE OR REPLACE FUNCTION is_group_creator(group_id_param UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM friends_groups
    WHERE id = group_id_param
    AND created_by = auth.uid()
  );
END;
$$;

-- Drop the problematic policy
DROP POLICY IF EXISTS "Users can view members of their groups" ON friends_group_members;

-- Create a new policy that avoids circular dependency
-- Users can view members if:
-- 1. They are a member themselves (user_id = auth.uid())
-- 2. They created the group (using SECURITY DEFINER function to bypass RLS)
CREATE POLICY "Users can view members of their groups"
  ON friends_group_members FOR SELECT
  USING (
    -- Direct check: user is a member
    user_id = auth.uid()
    OR
    -- User created the group (using function to bypass RLS recursion)
    is_group_creator(group_id)
  );

-- Also fix the INSERT policy to avoid the same issue
DROP POLICY IF EXISTS "Group creators can add members" ON friends_group_members;

CREATE POLICY "Group creators can add members"
  ON friends_group_members FOR INSERT
  WITH CHECK (
    -- Use function to check if user created the group (bypasses RLS)
    is_group_creator(group_id)
  );

