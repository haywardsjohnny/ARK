-- Fix friends_group_members RLS policy to allow members to see all members of their groups
-- Current issue: Members can only see themselves, not all members of the group

-- Create a SECURITY DEFINER function to check if user is a member of a group (bypasses RLS)
CREATE OR REPLACE FUNCTION is_group_member(group_id_param UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM friends_group_members
    WHERE group_id = group_id_param
    AND user_id = auth.uid()
  );
END;
$$;

-- Drop the existing policy
DROP POLICY IF EXISTS "Users can view members of their groups" ON friends_group_members;

-- Create a new policy that allows:
-- 1. Users who are members of a group can see ALL members of that group
-- 2. Users who created a group can see ALL members of that group
CREATE POLICY "Users can view members of their groups"
  ON friends_group_members FOR SELECT
  USING (
    -- User is a member of this group (can see all members)
    is_group_member(group_id)
    OR
    -- User created the group (can see all members)
    is_group_creator(group_id)
  );

