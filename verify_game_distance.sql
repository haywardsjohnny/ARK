-- Query to get the game's ZIP code and verify distance
-- Run this in your Supabase SQL editor or psql

SELECT 
  id,
  sport,
  mode,
  zip_code as game_zip_code,
  created_by,
  created_at
FROM instant_match_requests
WHERE id = '81994b3a-9453-4317-ac85-6b1da4d9a439';
