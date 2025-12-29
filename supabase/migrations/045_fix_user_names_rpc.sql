-- Create an RPC function to update user full_name from auth.users email
-- This function can access auth.users because it runs with SECURITY DEFINER

CREATE OR REPLACE FUNCTION update_user_names_from_email()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  updated_count INTEGER := 0;
BEGIN
  -- Update users who have NULL or empty full_name with their email username
  UPDATE public.users u
  SET full_name = COALESCE(
    u.full_name,
    SPLIT_PART(au.email, '@', 1),
    'User'
  ),
  updated_at = NOW()
  FROM auth.users au
  WHERE u.id = au.id
    AND (u.full_name IS NULL OR TRIM(u.full_name) = '')
    AND au.email IS NOT NULL;
  
  GET DIAGNOSTICS updated_count = ROW_COUNT;
  RETURN updated_count;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION update_user_names_from_email() TO authenticated;

-- Run the function to update existing users
SELECT update_user_names_from_email();

