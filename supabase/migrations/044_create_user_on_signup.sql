-- Create a trigger function to automatically create a users record when a new auth user is created
-- This ensures that every user in auth.users has a corresponding record in the users table

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (id, full_name, created_at, updated_at)
  VALUES (
    NEW.id,
    COALESCE(
      NEW.raw_user_meta_data->>'full_name',
      SPLIT_PART(NEW.email, '@', 1),
      'User'
    ),
    NOW(),
    NOW()
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger on auth.users
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Update existing users in auth.users who don't have a users record
INSERT INTO public.users (id, full_name, created_at, updated_at)
SELECT 
  au.id,
  COALESCE(
    au.raw_user_meta_data->>'full_name',
    SPLIT_PART(au.email, '@', 1),
    'User'
  ),
  au.created_at,
  NOW()
FROM auth.users au
LEFT JOIN public.users u ON u.id = au.id
WHERE u.id IS NULL
ON CONFLICT (id) DO NOTHING;

-- Update existing users who have NULL or empty full_name
UPDATE public.users u
SET full_name = COALESCE(
  u.full_name,
  SPLIT_PART(au.email, '@', 1),
  'User'
),
updated_at = NOW()
FROM auth.users au
WHERE u.id = au.id
  AND (u.full_name IS NULL OR TRIM(u.full_name) = '');

