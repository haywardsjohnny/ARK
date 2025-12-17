-- Debug query to check public game visibility
-- Run this in Supabase SQL Editor to verify the data

-- 1. Check the game created by User A (ramjaxkumar@gmail.com)
SELECT 
  imr.id,
  imr.sport,
  imr.mode,
  imr.status,
  imr.visibility,
  imr.is_public,
  imr.radius_miles,
  imr.zip_code,
  imr.created_by,
  imr.creator_id,
  t.name as team_name,
  t.sport as team_sport,
  u.email as creator_email
FROM instant_match_requests imr
LEFT JOIN teams t ON t.id = imr.team_id
LEFT JOIN auth.users u ON u.id = imr.creator_id
WHERE u.email = 'ramjaxkumar@gmail.com'
  AND imr.mode = 'team_vs_team'
  AND imr.sport = 'tennis'
ORDER BY imr.created_at DESC
LIMIT 5;

-- 2. Check if User B (user4@gmail.com) has admin teams in Tennis
SELECT 
  tm.team_id,
  t.name as team_name,
  t.sport,
  tm.role,
  u.email as user_email
FROM team_members tm
JOIN teams t ON t.id = tm.team_id
JOIN auth.users u ON u.id = tm.user_id
WHERE u.email = 'user4@gmail.com'
  AND tm.role = 'admin'
  AND t.sport = 'tennis';

-- 3. Check existing invites for User B's admin teams
SELECT 
  iri.id,
  iri.request_id,
  iri.target_team_id,
  iri.status,
  t.name as target_team_name,
  imr.sport,
  imr.visibility,
  imr.is_public
FROM instant_request_invites iri
JOIN teams t ON t.id = iri.target_team_id
JOIN instant_match_requests imr ON imr.id = iri.request_id
WHERE iri.target_team_id IN (
  SELECT tm.team_id
  FROM team_members tm
  JOIN auth.users u ON u.id = tm.user_id
  WHERE u.email = 'user4@gmail.com'
    AND tm.role = 'admin'
)
AND imr.sport = 'tennis'
ORDER BY iri.created_at DESC;

-- 4. Check all pending/open tennis team games
SELECT 
  imr.id,
  imr.sport,
  imr.status,
  imr.visibility,
  imr.is_public,
  imr.radius_miles,
  imr.zip_code,
  t.name as team_name,
  u.email as creator_email
FROM instant_match_requests imr
LEFT JOIN teams t ON t.id = imr.team_id
LEFT JOIN auth.users u ON u.id = imr.creator_id
WHERE imr.mode = 'team_vs_team'
  AND imr.sport = 'tennis'
  AND imr.status IN ('pending', 'open')
  AND imr.status != 'cancelled'
ORDER BY imr.created_at DESC;

