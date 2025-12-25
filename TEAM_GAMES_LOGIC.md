# Team Games Logic - Implementation Summary

## Overview
Team games allow teams to challenge other teams in organized matches. The flow involves admins creating games, sending invites, and team members providing availability.

---

## 1. Game Creation Flow

### A. Admin Creates Team Game
**Location:** `lib/screens/create_game_screen.dart` - `_TeamVsTeamFormState._submit()`

**Flow:**
1. Admin selects:
   - Sport
   - Their team (must be admin of that team)
   - Opponent type: "Specific Team(s)" or "Open Challenge"
   - Date & time
   - Venue (optional)
   - Game details (optional)
   - Visibility: "Invited", "Nearby", or "Public"
   - Expected players per team (optional)

2. Game is created with:
   - `mode: 'team_vs_team'`
   - `status: 'open'` (for admin-created games)
   - `team_id`: Admin's team ID
   - `radius_miles: 75` (default for all match types)

3. If "Specific Team(s)" selected:
   - Creates invites in `instant_request_invites` table
   - Each invite has `status: 'pending'` and `target_team_id`

4. If "Open Challenge" selected:
   - No invites created
   - Other teams discover via visibility + radius filters

### B. Non-Admin Requests Team Game
**Location:** `lib/screens/create_game_screen.dart` - `_TeamVsTeamFormState._submit()`

**Flow:**
1. Non-admin fills same form
2. Game is created with:
   - `status: 'pending'` (not 'open')
   - Requires admin approval before becoming active

---

## 2. Admin Approval Flow

### A. Pending Admin Matches
**Location:** `lib/screens/home_tabs/home_tabs_controller.dart` - `loadPendingGamesForAdmin()`

**What it shows:**
- Games created by non-admins that need admin approval
- Games where user is admin of a team in the same sport
- Within 75 miles radius from user/admin location

**Display:**
- Shows in "Pending Admin Approval" section on Home screen
- Admin can Accept or Deny

### B. Accept/Deny Actions
**Location:** 
- `lib/screens/home_tabs/home_tabs_controller.dart` - `acceptPendingAdminMatch()`, `denyPendingAdminMatch()`
- `lib/data/home_repository.dart` - `acceptPendingAdminMatch()`, `denyPendingAdminMatch()`

**Accept Flow:**
1. Calls RPC: `accept_pending_admin_match`
2. Updates game status to 'open'
3. Creates invite in `instant_request_invites` if needed
4. Refreshes pending games list

**Deny Flow:**
1. Calls RPC: `deny_pending_admin_match`
2. Updates game status to 'cancelled' or removes it
3. Refreshes pending games list

---

## 3. Team Invite Flow

### A. Invite Creation
**Location:** `lib/screens/create_game_screen.dart` - `_TeamVsTeamFormState._submit()`

When admin creates game with "Specific Team(s)":
- Inserts records into `instant_request_invites`:
  ```dart
  {
    'request_id': requestId,
    'target_team_id': teamId,
    'status': 'pending',
    'target_type': 'team',
  }
  ```

### B. Invite Display
**Location:** `lib/screens/home_tabs/home_tabs_controller.dart` - `loadAdminTeamsAndInvites()`

**What it shows:**
- Invites sent to teams where user is admin
- Shows in "Pending Admin Approval" section
- Admin can Accept or Deny

### C. Accept/Deny Invite
**Location:**
- `lib/data/home_repository.dart` - `approveTeamVsTeamInvite()`, `denyTeamVsTeamInvite()`

**Accept Flow:**
1. Calls RPC: `approve_team_vs_team_invite`
2. Updates invite status to 'accepted'
3. Creates attendance records for both teams in `team_match_attendance`
4. Game appears in "My Games" for both teams

**Deny Flow:**
1. Calls RPC: `deny_team_vs_team_invite`
2. Updates invite status to 'declined'
3. Game is removed from pending list

---

## 4. Team Member Availability Flow

### A. Pending Availability
**Location:** 
- `lib/data/home_repository.dart` - `loadPendingAvailabilityForUser()`
- `lib/screens/home_tabs/home_tabs_controller.dart` - `loadPendingAvailabilityForUser()`

**What it shows:**
- Confirmed team games (status = 'open', invite accepted)
- User is member of one of the teams
- User's attendance status is 'pending' in `team_match_attendance`

**Display:**
- Shows in "Pending Approval" section on Home screen
- User can mark "Available" or "Not Available"

### B. Update Availability
**Location:** `lib/screens/home_tabs/home_tabs_screen.dart` - `_buildPendingAvailabilityTeamCard()`

**Flow:**
1. User clicks "Available" or "Not Available"
2. Updates `team_match_attendance`:
   - `status: 'accepted'` or `'declined'`
3. Game remains in "My Games" (shows user's status)
4. Removed from "Pending Approval" (no longer pending)

---

## 5. My Games Display

### A. Team Games in My Games
**Location:** `lib/data/home_repository.dart` - `loadMyAcceptedTeamMatches()`

**What it shows:**
- Games where user is member of one of the teams
- User has attendance record (accepted, declined, or pending)
- Games are confirmed (status = 'open', invite accepted)

**Display:**
- Shows in "My Games" → "Team games" tab
- Displays:
  - Team A vs Team B
  - Date & time
  - Percentage bar (based on accepted attendance)
  - Player lists with admin badges
  - Creator name
  - Game details
  - Action buttons (Map, Reminder, Chat, Leave)

### B. Game Status Calculation
**Location:** `lib/screens/home_tabs/home_tabs_screen.dart` - Status bar logic

**Percentage calculation:**
- Based on `expected_players_per_team` from `sport_expected_players` table
- Defaults by sport (Cricket/Soccer/Football: 11, Basketball: 5, Volleyball: 6, etc.)
- Counts accepted attendance records per team
- Displays as percentage bar (0% = red, 100% = green)

---

## 6. Discover Tab - Public Team Games

### A. Public Team Games
**Location:** `lib/screens/discover_screen.dart` - `_loadDiscoveryMatches()`

**What it shows:**
- Team games with `visibility: 'public'` or `is_public: true`
- Within 100 miles radius (for individual games) or 75 miles (for team games)
- User must be admin of a team in the same sport to accept

**Display:**
- Shows "TEAM GAME" badge
- Shows "Request to Join" button (if user is admin of matching sport team)
- Shows info message if user is not eligible

---

## 7. Database Tables

### `instant_match_requests`
- Stores game/match requests
- Key fields: `mode`, `status`, `team_id`, `visibility`, `is_public`

### `instant_request_invites`
- Stores invites sent to teams
- Key fields: `request_id`, `target_team_id`, `status`, `target_type`

### `team_match_attendance`
- Stores individual player attendance for team games
- Key fields: `request_id`, `user_id`, `team_id`, `status` ('pending', 'accepted', 'declined')

### `sport_expected_players`
- Stores expected player count per sport
- Used for percentage bar calculation

---

## 8. Key Differences from Individual Games

1. **Admin Requirement:** Only team admins can create team games
2. **Two-Step Approval:**
   - Admin approval (if created by non-admin)
   - Invite acceptance (if specific team selected)
3. **Team-Based:** Games are tied to teams, not individual players
4. **Attendance Tracking:** Each team member has separate attendance record
5. **Public Visibility:** Public team games can only be accepted by admins of teams in the same sport

---

## 9. RPC Functions Used

1. `accept_pending_admin_match` - Accept non-admin game request
2. `deny_pending_admin_match` - Deny non-admin game request
3. `approve_team_vs_team_invite` - Accept team invite
4. `deny_team_vs_team_invite` - Deny team invite
5. `get_all_matches_for_user` - Get all team games for user
6. `get_confirmed_matches_for_user` - Get confirmed team games for user

---

## 10. Status Flow Diagram

```
[Non-Admin Creates Game]
    ↓
status: 'pending'
    ↓
[Admin Sees in "Pending Admin Approval"]
    ↓
[Admin Accepts] → status: 'open'
    ↓
[If Specific Team Selected]
    ↓
[Invite Created] → status: 'pending'
    ↓
[Opponent Admin Sees Invite]
    ↓
[Opponent Admin Accepts] → invite status: 'accepted'
    ↓
[Attendance Records Created for Both Teams]
    ↓
[Team Members See in "Pending Approval"]
    ↓
[Members Mark Availability]
    ↓
[Game Shows in "My Games" with Status]
```

---

## Summary

Team games follow a multi-step approval process:
1. **Creation:** Admin or non-admin creates game
2. **Admin Approval:** If non-admin, requires admin approval
3. **Invite Acceptance:** If specific team, opponent admin must accept
4. **Member Availability:** Team members mark their availability
5. **Game Display:** Confirmed games appear in "My Games" with attendance status

The system ensures proper authorization at each step and tracks individual player availability separately from team acceptance.

