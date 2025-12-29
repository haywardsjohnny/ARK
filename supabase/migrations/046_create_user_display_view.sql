-- Create a function to get display names for multiple users
-- This function can access auth.users because it runs with SECURITY DEFINER
CREATE OR REPLACE FUNCTION get_user_display_names(p_user_ids UUID[])
RETURNS TABLE (
  user_id UUID,
  display_name TEXT,
  full_name TEXT,
  photo_url TEXT,
  email TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    u.id AS user_id,
    COALESCE(
      NULLIF(TRIM(u.full_name), ''),
      SPLIT_PART(au.email::TEXT, '@', 1),
      'User'
    ) AS display_name,
    u.full_name,
    u.photo_url,
    au.email::TEXT AS email
  FROM public.users u
  LEFT JOIN auth.users au ON u.id = au.id
  WHERE u.id = ANY(p_user_ids);
END;
$$;

GRANT EXECUTE ON FUNCTION get_user_display_names(UUID[]) TO authenticated;

