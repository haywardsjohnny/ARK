# End-to-End Game Flow Documentation

This document outlines the complete flow for each game type from creation to completion.

## 1. Individual Game Created with Friends Group

### Creation Flow (`create_game_screen.dart` - `_IndividualsFormState._submit()`)

1. **User Input**:
   - Selects sport, number of players, skill level, date/time, venue, details
   - Chooses visibility: "Friends Group"
   - Selects a friends group from dropdown

2. **Database Insert** (`instant_match_requests` table):
   ```dart
   {
     'creator_id': userId,
     'created_by': userId,
     'mode': 'pickup',
     'match_type': 'pickup',
     'sport': _selectedSport,
     'zip_code': deviceLocationZip,
     'radius_miles': 75,
     'num_players': _numPlayers,
     'proficiency_level': _skillLevel,
     'status': 'open',
     'visibility': 'friends_group',
     'is_public': false,
     'friends_group_id': _selectedFriendsGroupId,
     'start_time_1': startUtc,
     'start_time_2': endUtc,
     'venue': _venueText,
     'details': _gameDetails,
   }
   ```

3. **Attendance Records Creation** (`individual_game_attendance` table):
   - For ALL members of the friends group (including organizer):
     ```dart
     {
       'request_id': requestId,
       'user_id': memberId,
       'status': 'pending',  // All members start with pending
       'invited_by': userId,
     }
     ```
   - **Key Point**: Even the organizer gets a `pending` status initially

4. **Post-Creation Actions**:
   - `loadAllMyIndividualMatches()` - Refreshes individual games list
   - `loadDiscoveryPickupMatches()` - Refreshes Discover tab
   - `loadAllMyMatches()` - Refreshes My Games tab

### Where Game Appears After Creation

1. **For Organizer**:
   - ✅ **My Games → Individual tab**: Game appears immediately (via `get_all_matches_for_user` RPC)
   - ✅ **Home → Pending Approval**: Game appears with "Available" / "Not Available" buttons
   - ❌ **Discover tab**: NOT visible (friends_group visibility is private)

2. **For Group Members**:
   - ✅ **My Games → Individual tab**: Game appears immediately (via RLS policy allowing users with pending attendance)
   - ✅ **Home → Pending Approval**: Game appears with "Available" / "Not Available" buttons
   - ❌ **Discover tab**: NOT visible

### User Actions

1. **Marking Availability**:
   - User clicks "Available" or "Not Available" in Pending Approval
   - Updates `individual_game_attendance.status` to `'accepted'` or `'denied'`
   - Game moves from "Pending Approval" to "My Games → Individual"
   - If "Available": User is counted in game attendance
   - If "Not Available": Game still appears in "My Games" but user is not counted

2. **Auto-Friending** (Database Trigger):
   - When users accept the same game (`status = 'accepted'`), a database trigger automatically creates friendships between them

### Database Queries Used

- **My Games**: `get_all_matches_for_user` RPC function (includes games where user has attendance record)
- **Pending Approval**: `getPendingIndividualGameRequests()` in `home_repository.dart` (queries `individual_game_attendance` with `status = 'pending'`)
- **RLS Policies**: 
  - `024_allow_users_to_see_games_with_pending_attendance.sql` - Allows users to see games with pending attendance
  - `023_fix_individual_game_attendance_rls.sql` - Allows users to view their own attendance records

---

## 2. Individual Game Created as Public

### Creation Flow (`create_game_screen.dart` - `_IndividualsFormState._submit()`)

1. **User Input**:
   - Selects sport, number of players, skill level, date/time, venue, details
   - Chooses visibility: "Public"

2. **Database Insert** (`instant_match_requests` table):
   ```dart
   {
     'creator_id': userId,
     'created_by': userId,
     'mode': 'pickup',
     'match_type': 'pickup',
     'sport': _selectedSport,
     'zip_code': deviceLocationZip,
     'radius_miles': 100,  // Public games have 100-mile radius
     'num_players': _numPlayers,
     'proficiency_level': _skillLevel,
     'status': 'open',
     'visibility': 'public',
     'is_public': true,  // Key flag for public games
     'start_time_1': startUtc,
     'start_time_2': endUtc,
     'venue': _venueText,
     'details': _gameDetails,
   }
   ```

3. **Attendance Records Creation** (`individual_game_attendance` table):
   - For the **creator only**:
     ```dart
     {
       'request_id': requestId,
       'user_id': userId,
       'status': 'accepted',  // Creator is automatically accepted
     }
     ```
   - **Key Point**: Only creator gets an attendance record initially

4. **Post-Creation Actions**:
   - `loadAllMyIndividualMatches()` - Refreshes individual games list
   - `loadDiscoveryPickupMatches()` - Refreshes Discover tab
   - `loadAllMyMatches()` - Refreshes My Games tab

### Where Game Appears After Creation

1. **For Creator**:
   - ✅ **My Games → Individual tab**: Game appears immediately (creator has `accepted` attendance)
   - ❌ **Home → Pending Approval**: NOT visible (creator is already accepted)
   - ✅ **Discover tab**: Visible to all users within 100 miles

2. **For Other Users**:
   - ✅ **Discover tab**: Visible if:
     - Game is within 100 miles of user's location
     - User's notification preferences match (sport and radius)
   - ❌ **My Games**: NOT visible until user requests to join
   - ❌ **Pending Approval**: NOT visible until user requests to join

### User Actions

1. **Request to Join** (from Discover tab):
   - User clicks "Request to Join" button
   - Creates attendance record:
     ```dart
     {
       'request_id': requestId,
       'user_id': userId,
       'status': 'pending',  // Requires organizer approval
     }
     ```
   - Game now appears in:
     - **My Games → Individual tab**: Shows "Waiting for organizer approval"
     - **Home → Pending Approval**: Shows for the requester

2. **Organizer Approval**:
   - Organizer sees pending requests in "Home → Pending Approval"
   - Clicks "Approve" or "Deny"
   - Updates `individual_game_attendance.status` to `'accepted'` or `'denied'`
   - If approved: User is counted in game attendance
   - If denied: Game still appears in "My Games" but user is not counted

3. **Auto-Friending** (Database Trigger):
   - When users accept the same game, friendships are automatically created

### Database Queries Used

- **Discover Tab**: `loadDiscoveryPickupMatches()` in `home_tabs_controller.dart`
  - Filters: `visibility = 'public' OR is_public = true`
  - Distance calculation: Uses `LocationService.calculateDistanceBetweenZipCodes()` (100-mile limit)
  - RLS Policy: `027_allow_all_users_to_see_public_games.sql` - Allows all authenticated users to see public games
- **My Games**: `get_all_matches_for_user` RPC function
- **Pending Approval**: `getPendingIndividualGameRequests()` - Shows games where user has `pending` attendance
- **Request to Join**: RLS Policy `029_allow_users_to_request_individual_games.sql` - Allows users to insert their own pending attendance

---

## 3. Team Game Created with Specific Teams

### Creation Flow (`create_game_screen.dart` - `_TeamVsTeamFormState._submit()`)

1. **User Input** (Admin only):
   - Selects sport, team, opponent type: "Invite specific teams"
   - Selects one or more opponent teams
   - Sets date/time, venue, expected players per team, details
   - Visibility is auto-set to `'invited'`

2. **Database Insert** (`instant_match_requests` table):
   ```dart
   {
     'creator_id': userId,
     'created_by': userId,
     'mode': 'team_vs_team',
     'match_type': 'team_vs_team',
     'sport': _selectedSport,
     'zip_code': deviceLocationZip,
     'radius_miles': 75,
     'expected_players_per_team': _expectedPlayersPerTeam,
     'proficiency_level': _skillLevel,
     'status': 'open',
     'visibility': 'invited',  // Auto-set for specific team invites
     'is_public': false,
     'start_time_1': startUtc,
     'start_time_2': endUtc,
     'venue': _venueText,
     'details': _gameDetails,
   }
   ```

3. **Team Invites Creation** (`instant_request_invites` table):
   - For each selected opponent team:
     ```dart
     {
       'request_id': requestId,
       'target_team_id': opponentTeamId,
       'status': 'pending',
       'target_type': 'team',
     }
     ```

4. **Post-Creation Actions**:
   - `loadAwaitingOpponentConfirmationGames()` - Loads games awaiting opponent acceptance
   - `loadAllMyMatches()` - Refreshes My Games tab
   - `loadDiscoveryPickupMatches()` - Refreshes Discover tab

### Where Game Appears After Creation

1. **For Creating Team (All Members)**:
   - ✅ **My Games → Team games → "Awaiting Opponent Confirmation" section**: Game appears immediately
   - ✅ Shows: Date, Venue, Time, Opponent team names (or "Open challenge")
   - ✅ **Cancel Game** button: Only visible to admins of the creating team
   - ❌ **Discover tab**: NOT visible (visibility = 'invited')
   - ❌ **Confirmed games**: NOT visible until opponent accepts

2. **For Invited Teams (Admins Only)**:
   - ✅ **Home → Pending Admin Approval**: Game appears with "Accept" / "Deny" buttons
   - ❌ **My Games**: NOT visible until admin accepts
   - ❌ **Discover tab**: NOT visible

### User Actions

1. **Admin Accepts Invite**:
   - Invited team admin clicks "Accept" in "Pending Admin Approval"
   - Updates `instant_request_invites.status` to `'accepted'`
   - Updates `instant_match_requests.status` to `'confirmed'`
   - Creates attendance records for **both teams**:
     - `team_match_attendance` records with `status = 'pending'` for all members of both teams
   - Game now appears in:
     - **My Games → Team games → Confirmed**: For all members of both teams
     - **Home → Pending Confirmation**: For all members of both teams (to mark availability)

2. **Admin Denies Invite**:
   - Invited team admin clicks "Deny"
   - Updates `instant_request_invites.status` to `'denied'`
   - **If ALL invited teams deny**:
     - Game becomes public: `visibility = 'public'`, `is_public = true`, `status = 'open'`
     - Game now appears in **Discover tab** for all users

3. **Team Members Mark Availability**:
   - Members see game in "Home → Pending Confirmation"
   - Click "Available" or "Not Available"
   - Updates `team_match_attendance.status` to `'accepted'` or `'denied'`
   - Game moves to "My Games → Team games → Confirmed"

4. **Cancel Game** (Admin of creating team only):
   - Admin clicks "Cancel Game" in "Awaiting Opponent Confirmation"
   - Updates `instant_match_requests.status` to `'cancelled'`
   - Game moves to "My Games → Cancelled" tab

### Database Queries Used

- **Awaiting Opponent Confirmation**: `getAwaitingOpponentConfirmationGames()` in `home_repository.dart`
  - Queries games where:
    - User is a member of the creating team
    - Game status is `'open'`
    - Game has pending invites (`instant_request_invites.status = 'pending'`)
- **Pending Admin Approval**: `getPendingTeamMatchesForAdmin()` in `home_repository.dart`
  - Queries games where:
    - User is an admin of a team
    - Team has a pending invite (`instant_request_invites.status = 'pending'`)
    - Game is within team's notification radius
- **Confirmed Games**: `get_confirmed_matches_for_user` RPC function
- **Deny Logic**: `denyInvite()` in `home_repository.dart` - Checks if all teams denied, makes game public

---

## 4. Team Game Created as Public (Open Challenge)

### Creation Flow (`create_game_screen.dart` - `_TeamVsTeamFormState._submit()`)

1. **User Input** (Admin only):
   - Selects sport, team, opponent type: "Open challenge"
   - Sets date/time, venue, expected players per team, details
   - Visibility is auto-set to `'public'`

2. **Database Insert** (`instant_match_requests` table):
   ```dart
   {
     'creator_id': userId,
     'created_by': userId,
     'mode': 'team_vs_team',
     'match_type': 'team_vs_team',
     'sport': _selectedSport,
     'zip_code': deviceLocationZip,
     'radius_miles': 75,
     'expected_players_per_team': _expectedPlayersPerTeam,
     'proficiency_level': _skillLevel,
     'status': 'open',
     'visibility': 'public',  // Auto-set for open challenge
     'is_public': true,  // Key flag for public games
     'start_time_1': startUtc,
     'start_time_2': endUtc,
     'venue': _venueText,
     'details': _gameDetails,
   }
   ```

3. **No Team Invites Created**:
   - Open challenge games don't create `instant_request_invites` records
   - Other teams discover the game via Discover tab

4. **Post-Creation Actions**:
   - `loadAwaitingOpponentConfirmationGames()` - Loads games awaiting opponent acceptance
   - `loadAllMyMatches()` - Refreshes My Games tab
   - `loadDiscoveryPickupMatches()` - Refreshes Discover tab

### Where Game Appears After Creation

1. **For Creating Team (All Members)**:
   - ✅ **My Games → Team games → "Awaiting Opponent Confirmation" section**: Game appears immediately
   - ✅ Shows: Date, Venue, Time, "Open challenge"
   - ✅ **Cancel Game** button: Only visible to admins of the creating team
   - ✅ **Discover tab**: Visible to all users within 100 miles (if they have a team in the same sport)
   - ❌ **Confirmed games**: NOT visible until opponent accepts

2. **For Other Teams (Admins Only)**:
   - ✅ **Discover tab**: Visible if:
     - User is an admin of a team in the same sport
     - Game is within 100 miles of user's location
     - Team's notification preferences match (sport and radius)
   - ❌ **My Games**: NOT visible until admin accepts
   - ❌ **Pending Admin Approval**: NOT visible until admin accepts

### User Actions

1. **Admin Accepts Open Challenge** (from Discover tab):
   - Admin clicks "Accept" or "Request to Join" in Discover tab
   - Creates `instant_request_invites` record:
     ```dart
     {
       'request_id': requestId,
       'target_team_id': adminTeamId,
       'status': 'accepted',  // Auto-accepted for open challenges
       'target_type': 'team',
     }
     ```
   - Updates `instant_match_requests.status` to `'confirmed'`
   - Creates attendance records for **both teams**:
     - `team_match_attendance` records with `status = 'pending'` for all members of both teams
   - Game now appears in:
     - **My Games → Team games → Confirmed**: For all members of both teams
     - **Home → Pending Confirmation**: For all members of both teams (to mark availability)
   - **Discover tab**: Game is removed (no longer accepting new teams)

2. **Team Members Mark Availability**:
   - Members see game in "Home → Pending Confirmation"
   - Click "Available" or "Not Available"
   - Updates `team_match_attendance.status` to `'accepted'` or `'denied'`
   - Game moves to "My Games → Team games → Confirmed"

3. **Cancel Game** (Admin of creating team only):
   - Admin clicks "Cancel Game" in "Awaiting Opponent Confirmation"
   - Updates `instant_match_requests.status` to `'cancelled'`
   - Game moves to "My Games → Cancelled" tab

### Database Queries Used

- **Awaiting Opponent Confirmation**: `getAwaitingOpponentConfirmationGames()` in `home_repository.dart`
- **Discover Tab**: `loadDiscoveryPickupMatches()` in `home_tabs_controller.dart`
  - Filters: `visibility = 'public' OR is_public = true`
  - Filters: `match_type = 'team_vs_team'`
  - Distance calculation: Uses `LocationService.calculateDistanceBetweenZipCodes()` (100-mile limit)
  - RLS Policy: `027_allow_all_users_to_see_public_games.sql`
- **Accept Open Challenge**: `approveInvite()` in `home_repository.dart` - Creates invite record and confirms game

---

## Summary Table

| Game Type | Visibility | Where It Appears After Creation | Who Can See It | Next Steps |
|-----------|-----------|--------------------------------|----------------|------------|
| **Individual + Friends Group** | `friends_group` | My Games (Individual), Pending Approval | Organizer + Group Members | Members mark availability |
| **Individual + Public** | `public` | My Games (Individual) for creator, Discover for others | All users within 100 miles | Others request to join, organizer approves |
| **Team + Specific Teams** | `invited` | My Games (Awaiting Confirmation) for creating team, Pending Admin Approval for invited teams | Creating team members + Invited team admins | Invited admins accept/deny, then members mark availability |
| **Team + Public** | `public` | My Games (Awaiting Confirmation) for creating team, Discover for others | All team admins within 100 miles (same sport) | Other admins accept, then members mark availability |

---

## Key Database Tables

1. **`instant_match_requests`**: Main game record
   - `visibility`: `'friends_group'`, `'public'`, `'invited'`
   - `is_public`: Boolean flag for public games
   - `status`: `'open'`, `'confirmed'`, `'cancelled'`
   - `friends_group_id`: For friends group games

2. **`individual_game_attendance`**: Individual game attendance
   - `status`: `'pending'`, `'accepted'`, `'denied'`

3. **`team_match_attendance`**: Team game attendance
   - `status`: `'pending'`, `'accepted'`, `'denied'`

4. **`instant_request_invites`**: Team game invites
   - `status`: `'pending'`, `'accepted'`, `'denied'`
   - `target_type`: `'team'`

5. **`friends_groups`**: Friends groups
6. **`friends_group_members`**: Friends group membership

---

## Key RLS Policies

- `024_allow_users_to_see_games_with_pending_attendance.sql`: Allows users to see games where they have pending attendance
- `027_allow_all_users_to_see_public_games.sql`: Allows all authenticated users to see public games
- `029_allow_users_to_request_individual_games.sql`: Allows users to request to join public individual games

---

## Key RPC Functions

- `get_all_matches_for_user`: Returns all games for a user (team and individual, including games with attendance records)
- `get_confirmed_matches_for_user`: Returns confirmed team games for a user

