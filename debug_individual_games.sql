-- Debug: Check individual games visibility
-- Run this in Supabase SQL Editor to see what's in the database

-- 1. Check all recent individual/pickup games
SELECT 
  id,
  sport,
  mode,
  status,
  visibility,
  is_public,
  created_by,
  created_at,
  zip_code
FROM instant_match_requests
WHERE mode != 'team_vs_team'
  AND status != 'cancelled'
ORDER BY created_at DESC
LIMIT 10;

-- 2. Check if the pickleball game exists
SELECT 
  id,
  sport,
  mode,
  status,
  visibility,
  is_public,
  created_by,
  created_at
FROM instant_match_requests
WHERE sport ILIKE '%pickleball%'
ORDER BY created_at DESC
LIMIT 5;

-- 3. Check what the discovery query would return (replace USER_ID with actual user ID)
-- This simulates what loadDiscoveryPickupMatches() fetches
SELECT 
  id,
  sport,
  mode,
  visibility,
  is_public,
  created_by,
  status
FROM instant_match_requests
WHERE status != 'cancelled'
  AND created_by != 'USER_ID_HERE' -- Replace with checking user ID
ORDER BY created_at DESC
LIMIT 20;

