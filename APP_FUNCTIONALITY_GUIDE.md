# SportsDug App Functionality Guide

This document provides detailed functionality documentation for three key game types in the SportsDug app.

---

## 1. Individual Game with Friends Group (IND FRIENDS GAME)

### Overview
An individual game created within a friends group. Only members of that specific friends group can see and participate in the game.

### Prerequisites
- User must have created or be a member of a friends group for the selected sport
- Friends groups are sport-specific (e.g., a volleyball group cannot be used for a basketball game)

### Game Creation Flow

#### Step 1: Access Create Game
- Navigate to **Home** tab → Click **"Create Game"** button
- Select **"Individual Game"** option

#### Step 2: Fill Game Details
- **Sport**: Select from dropdown (must match friends group sport)
- **Number of Players**: Enter required player count (e.g., 4 for pickleball doubles)
- **Skill Level**: Select (Recreational, Intermediate, Competitive)
- **Date & Time**: Choose start and end times
- **Venue**: Enter location name/address
- **Game Details** (optional): Add any additional information

#### Step 3: Select Visibility
- Choose **"Friends Group"** option
- **If no friends groups exist**:
  - Message displays: "You currently do not have friends group"
  - Click **"Create friends group"** hyperlink
  - Redirects to Profile → Friends Groups section
  - Create group, add members, then return to game creation
- **If friends groups exist**:
  - Dropdown shows: "Group Name (Sport)" (e.g., "Greens (Volleyball)")
  - Select desired group

#### Step 4: Create Game
- Click **"Create Game"** button
- Game is created with:
  - `visibility = 'friends_group'`
  - `is_public = false`
  - `friends_group_id = selected group ID`
  - Attendance records created for **ALL group members** (including organizer) with `status = 'pending'`

### Where Game Appears After Creation

#### For Organizer (Game Creator)
1. **My Games → Individual Tab**
   - Game appears immediately
   - Shows: Sport, Date/Time, Venue, Number of players, Spots left
   - Status: "Waiting for availability responses"

2. **Home → Pending Approval Section**
   - Game appears with **"Available"** and **"Not Available"** buttons
   - Organizer must mark their own availability (same as other members)

3. **Discover Tab**
   - ❌ **NOT visible** (friends group games are private)

#### For Group Members (Non-Organizer)
1. **My Games → Individual Tab**
   - Game appears immediately
   - Shows same details as organizer view

2. **Home → Pending Approval Section**
   - Game appears with **"Available"** and **"Not Available"** buttons
   - User must mark their availability

3. **Discover Tab**
   - ❌ **NOT visible**

### User Actions

#### Marking Availability
1. Navigate to **Home → Pending Approval**
2. Find the game card
3. Click either:
   - **"Available"**: User is counted in game attendance, game moves to "My Games"
   - **"Not Available"**: User is not counted, but game still appears in "My Games"

#### After Marking Availability
- Game moves from "Pending Approval" to "My Games → Individual"
- If "Available": User is included in attendance count
- If "Not Available": Game still visible in "My Games" but user not counted

#### Auto-Friending Feature
- When multiple users mark "Available" for the same game, friendships are automatically created between them
- This happens via a database trigger (`auto_friend_on_game_accept`)

### Game Display in "My Games"

#### Collapsed View
- Sport name (e.g., "Pickleball Individual Game")
- Date and time
- Venue
- Status bar showing attendance percentage
- "X spots left" indicator

#### Expanded View
- Full game details
- Creator name (marked as "Admin")
- List of all players with:
  - Player name
  - "Admin" badge next to creator
  - Availability status (Available/Not Available)
- Game details (if provided)
- Action buttons:
  - **Open Map**: View location on map
  - **Reminder**: Set game reminder
  - **Chat**: Access game chat (if enabled)
  - **Leave**: Leave the game

### Key Database Tables
- `instant_match_requests`: Main game record
- `individual_game_attendance`: User attendance records
- `friends_groups`: Friends group definitions
- `friends_group_members`: Group membership

### Key Features
- ✅ Private to group members only
- ✅ All members (including organizer) start with pending status
- ✅ Auto-friending when users accept
- ✅ Game appears in "My Games" immediately for all members
- ✅ Organizer approval not required (members self-select availability)

---

## 2. Individual Public Game (IND PUB GAME)

### Overview
An individual game visible to all users within 100 miles. Anyone can discover and request to join the game.

### Prerequisites
- None (any authenticated user can create a public game)

### Game Creation Flow

#### Step 1: Access Create Game
- Navigate to **Home** tab → Click **"Create Game"** button
- Select **"Individual Game"** option

#### Step 2: Fill Game Details
- **Sport**: Select from dropdown
- **Number of Players**: Enter required player count
- **Skill Level**: Select (Recreational, Intermediate, Competitive)
- **Date & Time**: Choose start and end times
- **Venue**: Enter location name/address
- **Game Details** (optional): Add any additional information

#### Step 3: Select Visibility
- Choose **"Public"** option
- Game will be visible to all users within 100 miles

#### Step 4: Create Game
- Click **"Create Game"** button
- Game is created with:
  - `visibility = 'public'`
  - `is_public = true`
  - `radius_miles = 100`
  - Attendance record created for **creator only** with `status = 'accepted'`

### Where Game Appears After Creation

#### For Creator
1. **My Games → Individual Tab**
   - Game appears immediately
   - Shows: Sport, Date/Time, Venue, Number of players, Spots left
   - Status: "Active - X spots left"

2. **Home → Pending Approval**
   - ❌ **NOT visible** (creator is already accepted)

3. **Discover Tab**
   - ✅ Visible to all users within 100 miles
   - Shows: Sport, Date/Time, Venue, Distance, Spots left
   - Displays "Request to Join" button for other users

#### For Other Users
1. **Discover Tab**
   - ✅ Visible if:
     - Game is within 100 miles of user's location
     - User's notification preferences match (sport and radius)
   - Shows: Sport, Date/Time, Venue, Distance from user, Spots left
   - Displays **"Request to Join"** button

2. **My Games**
   - ❌ **NOT visible** until user requests to join

3. **Pending Approval**
   - ❌ **NOT visible** until user requests to join

### User Actions

#### Request to Join (For Other Users)
1. Navigate to **Discover** tab
2. Find the public game
3. Click **"Request to Join"** button
4. Attendance record is created:
   - `request_id = game ID`
   - `user_id = requester ID`
   - `status = 'pending'` (requires organizer approval)
5. Game now appears in:
   - **My Games → Individual Tab**: Shows "Waiting for organizer approval • X spots left"
   - **Home → Pending Approval**: Shows for the requester

#### Organizer Approval (For Creator)
1. Navigate to **Home → Pending Approval**
2. Find pending requests (games where others have requested to join)
3. For each request, click:
   - **"Approve"**: User is added to game, counted in attendance
   - **"Deny"**: User is not added, game removed from their view

#### After Approval/Denial
- **If Approved**:
  - User's attendance status changes to `'accepted'`
  - User is counted in game attendance
  - Game appears in "My Games" for the user
  - Auto-friending occurs (friendship created between organizer and user)

- **If Denied**:
  - User's attendance status changes to `'denied'`
  - Game still appears in "My Games" but user is not counted
  - No friendship is created

### Game Display in "My Games"

#### For Creator (Accepted Status)
- Collapsed view shows full game details
- Expanded view shows:
  - All accepted players
  - Pending requests (if any)
  - Action buttons (Map, Reminder, Chat, Leave)

#### For Requesters (Pending Status)
- Collapsed view shows: "Waiting for organizer approval • X spots left"
- Expanded view shows:
  - Game details
  - Status: "Pending approval"
  - No action buttons (until approved)

### Key Database Tables
- `instant_match_requests`: Main game record
- `individual_game_attendance`: User attendance records
- `friends`: Auto-created friendships

### Key Features
- ✅ Visible to all users within 100 miles
- ✅ Creator automatically accepted
- ✅ Others must request to join
- ✅ Organizer must approve requests
- ✅ Auto-friending when organizer approves
- ✅ "Spots left" indicator shows available slots
- ✅ Users can still request even if game is full

### Distance Calculation
- Games are filtered by distance from user's current location
- Uses ZIP code-based distance calculation (Haversine formula)
- Maximum visibility: 100 miles
- Distance displayed in game details (e.g., "3.2 miles away")

---

## 3. Team Game with Specific Team Invites (TEAM INVITE SPECIFIC TEAM GAME)

### Overview
A team vs team game where an admin invites specific opponent teams. Only invited teams can accept the challenge.

### Prerequisites
- User must be an admin of a team
- Team must be in the same sport as the game
- Opponent teams must exist and be in the same sport

### Game Creation Flow

#### Step 1: Access Create Game
- Navigate to **Home** tab → Click **"Create Game"** button
- Select **"Team vs Team"** option

#### Step 2: Fill Game Details
- **Sport**: Select from dropdown
- **Your Team**: Select from user's admin teams (dropdown)
- **Opponent Type**: Select **"Invite specific teams"**
- **Opponent Teams**: Select one or more teams from dropdown
- **Date & Time**: Choose start and end times
- **Venue**: Enter location name/address
- **Expected Players per Team**: Enter number (e.g., 11 for cricket/soccer, 5 for basketball)
- **Game Details** (optional): Add any additional information

#### Step 3: Create Game
- Click **"Create Game"** button
- Game is created with:
  - `mode = 'team_vs_team'`
  - `visibility = 'invited'`
  - `is_public = false`
  - `status = 'open'`
  - `matched_team_id = null` (awaiting opponent acceptance)
- **Team Invites Created**:
  - One `instant_request_invites` record per invited team
  - `status = 'pending'`
  - `target_team_id = invited team ID`
- **Attendance Records Created**:
  - For **ALL members** of creating team: `team_match_attendance` with `status = 'pending'`
  - For **ALL members** of each invited team: `team_match_attendance` with `status = 'pending'`
  - These records allow all members to see the game in "Awaiting Opponent Confirmation"

### Where Game Appears After Creation

#### For Creating Team (All Members)
1. **My Games → Team Games → "Awaiting Opponent Confirmation" Section**
   - Game appears immediately
   - Shows:
     - Date and time
     - Venue
     - Opponent team names (e.g., "Opponent: Team B, Team C")
     - Game type: "Specific team invite"
   - **Cancel Game** button: Only visible to admins of creating team

2. **Home → Pending Admin Approval**
   - ❌ **NOT visible** (this is for invited teams only)

3. **Discover Tab**
   - ❌ **NOT visible** (visibility = 'invited', not public)

4. **Confirmed Games**
   - ❌ **NOT visible** until opponent accepts

#### For Invited Teams (Admins Only Initially)
1. **Home → Pending Admin Approval**
   - Game appears with:
     - Creating team name
     - Date, time, venue
     - **"Accept"** and **"Deny"** buttons
   - Only admins of invited teams see this

2. **My Games**
   - ❌ **NOT visible** until admin accepts

3. **Discover Tab**
   - ❌ **NOT visible**

#### For Invited Teams (All Members After Admin Accepts)
1. **My Games → Team Games → Confirmed**
   - Game appears after admin accepts
   - Shows full game details

2. **Home → Pending Approval**
   - Game appears for all members to mark availability

### User Actions

#### Admin Accepts Invite (For Invited Team Admin)
1. Navigate to **Home → Pending Admin Approval**
2. Find the game invite
3. Click **"Accept"** button
4. **What Happens**:
   - `instant_request_invites.status` changes to `'accepted'`
   - `instant_match_requests.status` changes to `'matched'`
   - `instant_match_requests.matched_team_id` set to accepting team ID
   - Attendance records created/updated for **both teams**:
     - Creating team: All members get `team_match_attendance` with `status = 'pending'`
     - Accepting team: All members get `team_match_attendance` with `status = 'pending'`
   - Accepting admin's attendance auto-set to `'accepted'`
5. **Game Now Appears**:
   - **My Games → Team Games → Confirmed**: For all members of both teams
   - **Home → Pending Approval**: For all members of both teams (to mark availability)
   - **Awaiting Opponent Confirmation**: Removed (game is now confirmed)

#### Admin Denies Invite (For Invited Team Admin)
1. Navigate to **Home → Pending Admin Approval**
2. Find the game invite
3. Click **"Deny"** button
4. **What Happens**:
   - `instant_request_invites.status` changes to `'denied'`
   - Game removed from "Pending Admin Approval" for that team
   - Game removed from "Awaiting Opponent Confirmation" for that team's members
   - **If ALL invited teams deny**:
     - Game becomes public: `visibility = 'public'`, `is_public = true`, `status = 'open'`
     - Game now appears in **Discover tab** for all users
     - Creating team members still see it in "Awaiting Opponent Confirmation"

#### Team Members Mark Availability (After Acceptance)
1. Navigate to **Home → Pending Approval**
2. Find the confirmed game
3. Click either:
   - **"Available"**: Member is counted in team attendance
   - **"Not Available"**: Member is not counted, but game still visible

#### Cancel Game (For Creating Team Admin)
1. Navigate to **My Games → Team Games → Awaiting Opponent Confirmation**
2. Find the game
3. Click **"Cancel Game"** button (only visible to admins)
4. **What Happens**:
   - `instant_match_requests.status` changes to `'cancelled'`
   - Game removed from "Awaiting Opponent Confirmation" for creating team
   - Game removed from "Pending Admin Approval" for invited teams
   - Game removed from "Awaiting Opponent Confirmation" for invited team members
   - Game appears in **My Games → Cancelled** tab

### Game Display in "My Games"

#### Awaiting Opponent Confirmation (Before Acceptance)
- **Collapsed View**:
  - Sport name (e.g., "Cricket Team Game")
  - Date and time
  - Venue
  - Opponent: "Team B, Team C" or "Open challenge"
  - Status: "Awaiting opponent confirmation"

- **Expanded View**:
  - Full game details
  - Creator name (marked as "Admin")
  - Opponent team names
  - **Cancel Game** button (admins only)

#### Confirmed Game (After Acceptance)
- **Collapsed View**:
  - Sport name
  - Date and time
  - Venue
  - Status bar showing attendance percentage (game level and team level)
  - Opponent team name

- **Expanded View**:
  - Full game details
  - Creator name
  - **Your Team** section:
    - Team name
    - List of players with availability status
    - "Admin" badges for team admins
    - Status bar showing team attendance percentage
  - **Opponent Team** section:
    - Opponent team name
    - List of players (if visible)
    - Status bar showing opponent attendance percentage
  - Action buttons:
    - **Open Map**: View location on map
    - **Reminder**: Set game reminder
    - **Chat**: Access game chat (if enabled by admins)
    - **Leave**: Leave the game

### Key Database Tables
- `instant_match_requests`: Main game record
- `instant_request_invites`: Team invite records
- `team_match_attendance`: Team member attendance records
- `team_members`: Team membership and roles

### Key Features
- ✅ Only invited teams can accept
- ✅ All members of creating team see game immediately
- ✅ All members of invited teams see game after admin accepts
- ✅ If all teams deny, game becomes public
- ✅ Admins can cancel game (removes from all views)
- ✅ Status bars show attendance at game and team levels
- ✅ Game moves from "Awaiting" to "Confirmed" after acceptance

### Status Bar Logic
- **Game Level**: Shows overall attendance percentage
  - 100% = Green (all required players available)
  - 0% = Red (no players available)
  - Gradual color transition based on percentage
- **Team Level**: Shows each team's attendance percentage
  - Based on `expected_players_per_team` setting
  - Sport-specific defaults (e.g., 11 for cricket/soccer, 5 for basketball)
  - Can be edited by organizer per game

### Filtering Logic
- **Pending Approval**: Only shows games where:
  - User's team is the creating team OR the matched team
  - Game has `matched_team_id` set (confirmed)
  - User has pending attendance record
- **Awaiting Opponent Confirmation**: Only shows games where:
  - User is a member of the creating team OR an invited team
  - Game has `matched_team_id = null` (not yet confirmed)
  - User's team has not denied the invite
  - Game is not cancelled

---

## Summary Comparison

| Feature | IND FRIENDS GAME | IND PUB GAME | TEAM INVITE SPECIFIC |
|---------|------------------|--------------|----------------------|
| **Visibility** | Friends group only | Public (100 miles) | Invited teams only |
| **Who Can See** | Group members | All users | Creating team + Invited teams |
| **Creation Attendance** | All members (pending) | Creator only (accepted) | All members (pending) |
| **Approval Required** | Self-select (no approval) | Organizer approval | Admin acceptance first, then self-select |
| **Appears in Discover** | ❌ No | ✅ Yes | ❌ No (unless all deny) |
| **Auto-Friending** | ✅ Yes | ✅ Yes | ❌ No |
| **Cancel Option** | ❌ No | ❌ No | ✅ Yes (admins only) |

---

## Common User Flows

### Flow 1: Create and Participate in Friends Group Game
1. User creates friends group (if needed)
2. User creates individual game with friends group
3. All group members see game in "My Games" and "Pending Approval"
4. Members mark availability
5. Game appears in "My Games" with attendance count
6. Auto-friending occurs between members who accepted

### Flow 2: Discover and Join Public Game
1. User browses Discover tab
2. User finds public game within 100 miles
3. User clicks "Request to Join"
4. Game appears in "My Games" with "Waiting for approval" status
5. Organizer approves request
6. User is added to game, friendship created
7. Game appears in "My Games" with full details

### Flow 3: Create and Accept Team Game
1. Team A admin creates game inviting Team B and Team C
2. All Team A members see game in "Awaiting Opponent Confirmation"
3. Team B and Team C admins see invite in "Pending Admin Approval"
4. Team B admin accepts
5. All Team A and Team B members see game in "Confirmed" and "Pending Approval"
6. Team C members no longer see the game (Team C didn't accept)
7. Members mark availability
8. Game shows attendance status bars for both teams

---

## Technical Notes

### RLS (Row Level Security) Policies
- `024_allow_users_to_see_games_with_pending_attendance.sql`: Allows users to see games with pending attendance
- `027_allow_all_users_to_see_public_games.sql`: Allows all users to see public games
- `029_allow_users_to_request_individual_games.sql`: Allows users to request to join public games
- `031_fix_invites_rls_for_creating_team.sql`: Allows team members to see invites for their teams

### RPC Functions
- `get_all_matches_for_user`: Returns all games for a user (team and individual)
- `get_match_requests_for_attendance`: Returns match requests for which user has attendance records
- `approve_team_vs_team_invite`: Handles team invite acceptance and attendance creation

### Distance Calculation
- Uses ZIP code-based Haversine formula
- Calculated between user's current ZIP and game's ZIP
- 100-mile limit for public games
- Distance displayed in game details

---

*Last Updated: Based on current implementation as of latest codebase review*

