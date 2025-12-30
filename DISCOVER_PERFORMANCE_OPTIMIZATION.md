# Discover Tab Performance Optimization for 100K+ Users

## Current Performance Issues

### 🔴 Critical Issues Found:

1. **N+1 Query Problem** (Lines 1000-1046):
   - Team name lookup: **1 query per team game** (potentially 50+ queries)
   - Invites check: **1 query per team game** (potentially 50+ queries)
   - Distance calculation: **Sequential await** inside loop (slow)

2. **Multiple Sequential Queries**:
   - Friends query (lines 745-757)
   - Friends groups query (lines 760-771)
   - Non-admin teams query (line 790)
   - All executed sequentially

3. **No Pagination**:
   - Loads up to 100 matches upfront
   - Processes ALL matches even if user only sees first 10

4. **No Caching**:
   - Results recalculated every refresh
   - Distance calculations repeated unnecessarily

5. **Client-Side Filtering**:
   - All 100 matches fetched, then filtered in Dart code
   - Should filter at database level

## Recommended Solutions (Priority Order)

### ✅ Solution 1: Create Optimized RPC Function (HIGHEST PRIORITY)

**Create a single RPC function** that does all the heavy lifting server-side:

```sql
-- supabase/migrations/049_optimize_discovery_matches.sql
CREATE OR REPLACE FUNCTION get_discovery_matches_optimized(
  p_user_id UUID,
  p_user_zip_code TEXT,
  p_limit INTEGER DEFAULT 30,
  p_offset INTEGER DEFAULT 0,
  p_sport_filter TEXT DEFAULT NULL,
  p_max_distance_miles INTEGER DEFAULT 100
)
RETURNS TABLE (
  request_id UUID,
  sport TEXT,
  mode TEXT,
  zip_code TEXT,
  start_time_1 TIMESTAMPTZ,
  start_time_2 TIMESTAMPTZ,
  venue TEXT,
  num_players INTEGER,
  created_by UUID,
  proficiency_level TEXT,
  team_id UUID,
  team_name TEXT,
  is_open_challenge BOOLEAN,
  can_accept BOOLEAN,
  distance_miles NUMERIC,
  user_team_invite_statuses JSONB,
  accepted_count INTEGER,
  spots_left INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_teams UUID[];
  v_user_sports TEXT[];
BEGIN
  -- Get user's team IDs (admin + non-admin)
  SELECT array_agg(DISTINCT team_id) INTO v_user_teams
  FROM team_members
  WHERE user_id = p_user_id;
  
  -- Get user's sports
  SELECT array_agg(sport) INTO v_user_sports
  FROM user_sports
  WHERE user_id = p_user_id;
  
  RETURN QUERY
  WITH ranked_matches AS (
    SELECT DISTINCT
      imr.id AS request_id,
      imr.sport,
      imr.mode,
      imr.zip_code,
      imr.start_time_1,
      imr.start_time_2,
      imr.venue,
      imr.num_players,
      imr.created_by,
      imr.proficiency_level,
      imr.team_id,
      -- Get team name with LEFT JOIN (no N+1)
      t.name AS team_name,
      -- Check if open challenge (no accepted invites)
      NOT EXISTS (
        SELECT 1 FROM instant_request_invites iri
        WHERE iri.request_id = imr.id
        AND iri.status = 'accepted'
      ) AS is_open_challenge,
      -- Check if user can accept (is admin of team in same sport)
      EXISTS (
        SELECT 1 FROM team_members tm
        JOIN teams t2 ON t2.id = tm.team_id
        WHERE tm.user_id = p_user_id
        AND tm.role = 'admin'
        AND t2.sport = imr.sport
      ) AS can_accept,
      -- Calculate distance (requires extension or use approximate calculation)
      CASE 
        WHEN p_user_zip_code IS NOT NULL AND imr.zip_code IS NOT NULL
        THEN calculate_zip_distance(p_user_zip_code, imr.zip_code)
        ELSE NULL
      END AS distance_miles,
      -- Get user's invite statuses as JSONB
      COALESCE(
        (
          SELECT jsonb_agg(
            jsonb_build_object(
              'status', iri.status,
              'target_team_id', iri.target_team_id,
              'team_name', t3.name
            )
          )
          FROM instant_request_invites iri
          LEFT JOIN teams t3 ON t3.id = iri.target_team_id
          WHERE iri.request_id = imr.id
          AND iri.target_team_id = ANY(v_user_teams)
        ),
        '[]'::jsonb
      ) AS user_team_invite_statuses
    FROM instant_match_requests imr
    LEFT JOIN teams t ON t.id = imr.team_id
    WHERE imr.status != 'cancelled'
    AND imr.created_by != p_user_id
    AND imr.matched_team_id IS NULL
    AND (imr.visibility = 'public' OR imr.is_public = true)
    AND (imr.team_id IS NULL OR imr.team_id != ALL(v_user_teams))
    AND (p_sport_filter IS NULL OR imr.sport = p_sport_filter)
    AND (p_user_zip_code IS NULL OR imr.zip_code IS NOT NULL)
    ORDER BY imr.created_at DESC
    LIMIT p_limit
    OFFSET p_offset
  ),
  individual_counts AS (
    SELECT 
      request_id,
      COUNT(*)::INTEGER AS accepted_count
    FROM individual_game_attendance
    WHERE request_id IN (SELECT request_id FROM ranked_matches)
    AND status = 'accepted'
    GROUP BY request_id
  )
  SELECT 
    rm.request_id,
    rm.sport,
    rm.mode,
    rm.zip_code,
    rm.start_time_1,
    rm.start_time_2,
    rm.venue,
    rm.num_players,
    rm.created_by,
    rm.proficiency_level,
    rm.team_id,
    rm.team_name,
    rm.is_open_challenge,
    rm.can_accept,
    rm.distance_miles,
    rm.user_team_invite_statuses,
    COALESCE(ic.accepted_count, 0),
    CASE 
      WHEN rm.mode != 'team_vs_team' AND rm.num_players IS NOT NULL
      THEN rm.num_players - COALESCE(ic.accepted_count, 0)
      ELSE NULL
    END AS spots_left
  FROM ranked_matches rm
  LEFT JOIN individual_counts ic ON ic.request_id = rm.request_id
  WHERE rm.distance_miles IS NULL OR rm.distance_miles <= p_max_distance_miles
  ORDER BY rm.created_at DESC;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_discovery_matches_optimized(UUID, TEXT, INTEGER, INTEGER, TEXT, INTEGER) TO authenticated;

-- Note: Requires a zip_distance calculation function (can use PostGIS or approximate)
```

**Benefits:**
- ✅ Single query instead of 100+ queries
- ✅ Server-side JOINs (faster)
- ✅ Built-in pagination
- ✅ Filtering at database level
- ✅ 10-50x faster at scale

### ✅ Solution 2: Add Critical Indexes

```sql
-- Composite index for discovery queries
CREATE INDEX IF NOT EXISTS idx_match_requests_discovery 
ON instant_match_requests(status, visibility, is_public, matched_team_id, created_at DESC)
WHERE status != 'cancelled' AND matched_team_id IS NULL;

-- Index for team lookups
CREATE INDEX IF NOT EXISTS idx_teams_id_name ON teams(id, name);

-- Index for invite status checks
CREATE INDEX IF NOT EXISTS idx_invites_request_status 
ON instant_request_invites(request_id, status) 
WHERE status = 'accepted';

-- Index for user team lookups
CREATE INDEX IF NOT EXISTS idx_team_members_user_role 
ON team_members(user_id, role, team_id);
```

### ✅ Solution 3: Implement Client-Side Caching

```dart
// Add to HomeTabsController
DateTime? _discoveryCacheTime;
List<Map<String, dynamic>>? _cachedDiscoveryMatches;
static const _cacheTTL = Duration(seconds: 30); // Cache for 30 seconds

Future<void> loadDiscoveryPickupMatches({bool forceRefresh = false}) async {
  // Use cache if available and not expired
  if (!forceRefresh && 
      _cachedDiscoveryMatches != null && 
      _discoveryCacheTime != null &&
      DateTime.now().difference(_discoveryCacheTime!) < _cacheTTL) {
    discoveryPickupMatches = _cachedDiscoveryMatches!;
    notifyListeners();
    return;
  }
  
  // ... existing loading logic ...
  
  // Cache results
  _cachedDiscoveryMatches = discoveryPickupMatches;
  _discoveryCacheTime = DateTime.now();
}
```

### ✅ Solution 4: Implement Pagination/Lazy Loading

```dart
// Initial load: Only 20 matches
int _discoveryOffset = 0;
static const _discoveryPageSize = 20;

Future<void> loadDiscoveryPickupMatches({bool loadMore = false}) async {
  if (!loadMore) {
    _discoveryOffset = 0;
    discoveryPickupMatches = [];
  }
  
  // Load next page
  final newMatches = await repo.getDiscoveryMatchesPaginated(
    userId: currentUserId!,
    userZipCode: baseZip,
    limit: _discoveryPageSize,
    offset: _discoveryOffset,
  );
  
  if (loadMore) {
    discoveryPickupMatches.addAll(newMatches);
  } else {
    discoveryPickupMatches = newMatches;
  }
  
  _discoveryOffset += _discoveryPageSize;
}

// Load more when user scrolls near bottom
void loadMoreDiscoveryMatches() {
  loadDiscoveryPickupMatches(loadMore: true);
}
```

### ✅ Solution 5: Optimize Distance Calculation

**Option A: Pre-calculate distances** (if user ZIP changes rarely):
- Store calculated distances in a materialized view
- Refresh periodically (e.g., every 5 minutes)

**Option B: Batch distance calculations** (current approach improved):
```dart
// Calculate all distances in parallel instead of sequential
final distances = await Future.wait(
  matches.map((m) => LocationService.calculateDistanceBetweenZipCodes(
    zip1: userZipCode,
    zip2: m['zip_code'],
  ))
);
```

**Option C: Use database function** (if PostGIS available):
- Calculate distance in SQL query directly
- Much faster than client-side API calls

### ✅ Solution 6: Defer Non-Critical Data Loading

```dart
// Load essential data first (sport, mode, time, venue)
// Load additional data (team names, invite statuses) after UI renders

Future<void> loadDiscoveryPickupMatchesFast() async {
  // Phase 1: Load essential fields quickly
  loadingDiscoveryMatches = true;
  notifyListeners();
  
  final essentialMatches = await repo.getDiscoveryMatchesEssential(
    limit: 20,
    offset: 0,
  );
  
  discoveryPickupMatches = essentialMatches;
  loadingDiscoveryMatches = false;
  notifyListeners(); // Show UI immediately
  
  // Phase 2: Load additional data in background
  await _enrichDiscoveryMatches();
}

Future<void> _enrichDiscoveryMatches() async {
  // Load team names, invite statuses, etc. in background
  // Update UI progressively
}
```

## Implementation Priority

1. **Phase 1 (Immediate - 1-2 hours)**:
   - Add critical indexes
   - Implement client-side caching (30s TTL)
   - Reduce initial limit from 100 to 20-30

2. **Phase 2 (Short-term - 1 day)**:
   - Create optimized RPC function
   - Implement pagination
   - Move filtering to database

3. **Phase 3 (Medium-term - 3-5 days)**:
   - Optimize distance calculations
   - Add materialized views if needed
   - Implement progressive loading

## Expected Performance Improvement

- **Current**: 2-5 seconds for 100 matches (with N+1 queries)
- **After Phase 1**: 0.5-1 second for 20 matches (with caching)
- **After Phase 2**: 0.2-0.5 seconds for 20 matches (with RPC)
- **After Phase 3**: <0.3 seconds consistently (fully optimized)

## Monitoring

Add performance logging:
```dart
final stopwatch = Stopwatch()..start();
await loadDiscoveryPickupMatches();
stopwatch.stop();
if (kDebugMode) {
  print('[PERF] Discovery load took ${stopwatch.elapsedMilliseconds}ms');
}
```

