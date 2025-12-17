-- Check why games 7f2eb47e and 41d08c1f are not showing in the app

-- 1. Check if these games exist and their details
SELECT 
  id,
  sport,
  mode,
  status,
  visibility,
  is_public,
  team_id,
  created_at
FROM instant_match_requests
WHERE id IN (
  '7f2eb47e-eb09-4715-adae-fefb778cbd9f',
  '41d08c1f-aa5f-4d11-ab7f-a2e38d1ac303'
);

-- 2. Check if invites exist for User B's team (Manor: 540bab34-42c0-462b-80c4-3e4d25b74633)
SELECT 
  iri.id,
  iri.request_id,
  iri.target_team_id,
  iri.status,
  iri.created_at,
  imr.sport,
  t.name as target_team_name
FROM instant_request_invites iri
JOIN instant_match_requests imr ON imr.id = iri.request_id
LEFT JOIN teams t ON t.id = iri.target_team_id
WHERE iri.request_id IN (
  '7f2eb47e-eb09-4715-adae-fefb778cbd9f',
  '41d08c1f-aa5f-4d11-ab7f-a2e38d1ac303',
  '509b3876-fd76-4053-b824-ae64fe6b8a85'
)
ORDER BY iri.created_at DESC;

-- 3. Check all invites for User B's Manor team
SELECT 
  iri.id,
  iri.request_id,
  iri.status,
  imr.sport,
  imr.status as request_status,
  t_req.name as requesting_team_name
FROM instant_request_invites iri
JOIN instant_match_requests imr ON imr.id = iri.request_id
LEFT JOIN teams t_req ON t_req.id = imr.team_id
WHERE iri.target_team_id = '540bab34-42c0-462b-80c4-3e4d25b74633'
  AND imr.sport = 'tennis'
ORDER BY iri.created_at DESC;

