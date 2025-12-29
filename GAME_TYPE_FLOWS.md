# Game Type Flows - What Happens for Each Type

## 1. Individual Game - Public

### **Creation Flow:**
1. User fills out form (sport, date, time, venue, num_players, skill level, details)
2. Sets `visibility = 'public'` and `is_public = true`
3. Game is created in `instant_match_requests` table with:
   - `status = 'open'`
   - `radius_miles = 100` (for public games)
   - `match_type = 'pickup'`
   - `zip_code` = user's current device location ZIP
4. **Attendance Record Created:**
   - Creates ONE attendance record in `individual_game_attendance`:
     - `user_id` = creator's ID
     - `status = 'accepted'` (creator is automatically accepted)
     - This ensures the game appears in creator's "My Games" immediately

### **Where It Appears:**
- **Creator's "My Games" → Individual tab:** ✅ YES (via attendance record with status='accepted')
- **Creator's "Home → Pending Approval":** ❌ NO (creator is already accepted)
- **Other Users' "Discover" tab:** ✅ YES (if within 100 miles from their location)
- **Other Users' "Home → Pending Approval":** ❌ NO (they must request to join first)

### **Discovery & Joining:**
- Other users see it in "Discover" tab if:
  - Game is `is_public = true` AND `visibility = 'public'`
  - Game is within 100 miles from their location ZIP code
  - Game matches their notification preferences (sport, radius)
- When another user clicks "Request to Join":
  - Creates attendance record in `individual_game_attendance` with `status = 'pending'`
  - Game appears in creator's "Home → Pending Approval" for acceptance
  - Once creator accepts, the requester's status changes to `'accepted'` and game appears in their "My Games"

---

## 2. Individual Game - Friends Group

### **Creation Flow:**
1. User selects a friends group (must exist for that sport)
2. Sets `visibility = 'friends_group'` and `is_public = false`
3. Sets `friends_group_id` in the game record
4. Game is created in `instant_match_requests` table with:
   - `status = 'open'`
   - `radius_miles = 75` (for non-public games)
   - `match_type = 'pickup'`
   - `zip_code` = user's current device location ZIP
5. **Attendance Records Created:**
   - For **ALL members** of the selected friends group (including the organizer):
     - Creates attendance record in `individual_game_attendance`:
       - `user_id` = each group member's ID
       - `status = 'pending'` (all members, including organizer, start as pending)
       - `invited_by` = organizer's ID

### **Where It Appears:**
- **All Group Members' "My Games" → Individual tab:** ✅ YES (immediately after creation, via attendance records)
- **All Group Members' "Home → Pending Approval":** ✅ YES (all members see it, including organizer)
- **Other Users' "Discover" tab:** ❌ NO (friends group games are NOT public)
- **Non-group members:** ❌ NO (cannot see the game at all)

### **Response Flow:**
- When a group member clicks "Available" or "Not Available":
  - Their attendance record status changes to `'accepted'` or `'denied'`
  - Game remains in "My Games" (even if denied)
  - Game is removed from "Pending Approval" once they respond

---

## 3. Team Game - Public (Open Challenge)

### **Creation Flow:**
1. Admin selects team, sport, date, time, venue, details
2. Chooses "Open Challenge" (no specific teams invited)
3. Sets `visibility = 'public'` and `is_public = true`
4. Game is created in `instant_match_requests` table with:
   - `status = 'open'`
   - `radius_miles = 75`
   - `match_type = 'team_vs_team'`
   - `team_id` = creating team's ID
   - `zip_code` = admin's current device location ZIP
5. **NO invites created** in `instant_request_invites` (it's an open challenge)
6. **Attendance Records Created:**
   - For **ALL members** of the creating team:
     - Creates attendance record in `team_match_attendance`:
       - `user_id` = each team member's ID
       - `team_id` = creating team's ID
       - `status = 'pending'` (all members start as pending)

### **Where It Appears:**
- **All Creating Team Members' "My Games" → Team tab → "Games Awaiting confirmation":** ✅ YES (immediately after creation)
- **All Creating Team Members' "Home → Pending Approval":** ❌ NO (not yet - waiting for opponent)
- **Other Team Admins' "Discover" tab:** ✅ YES (if within 100 miles, same sport, admin of a team)
- **Other Team Admins' "Home → Pending Admin Approval":** ❌ NO (they must click "Join" first)

### **Discovery & Joining:**
- Other team admins see it in "Discover" tab if:
  - Game is `is_public = true` AND `visibility = 'public'`
  - Game is within 100 miles from their location
  - They are an admin of a team in the same sport
- When another team admin clicks "Join":
  - Creates invite record in `instant_request_invites` with `status = 'pending'`
  - Creates attendance records for ALL members of the joining team with `status = 'pending'`
  - Game appears in creating team admin's "Home → Pending Admin Approval"
  - Once creating team admin accepts, game becomes confirmed and both teams see it in "My Games" with pending availability

---

## 4. Team Game - Invited Specific Teams

### **Creation Flow:**
1. Admin selects team, sport, date, time, venue, details
2. Chooses "Invite Specific Teams" and selects one or more opponent teams
3. Sets `visibility = 'invited'` and `is_public = false`
4. Game is created in `instant_match_requests` table with:
   - `status = 'open'`
   - `radius_miles = 75`
   - `match_type = 'team_vs_team'`
   - `team_id` = creating team's ID
   - `zip_code` = admin's current device location ZIP
5. **Invites Created:**
   - For each selected opponent team:
     - Creates invite record in `instant_request_invites`:
       - `request_id` = game ID
       - `target_team_id` = opponent team's ID
       - `status = 'pending'`
       - `target_type = 'team'`
6. **Attendance Records Created:**
   - For **ALL members** of the creating team:
     - Creates attendance record in `team_match_attendance`:
       - `user_id` = each team member's ID
       - `team_id` = creating team's ID
       - `status = 'pending'`
   - For **ALL members** of each invited team:
     - Creates attendance record in `team_match_attendance`:
       - `user_id` = each team member's ID
       - `team_id` = invited team's ID
       - `status = 'pending'`

### **Where It Appears:**
- **All Creating Team Members' "My Games" → Team tab → "Games Awaiting confirmation":** ✅ YES (immediately after creation)
- **All Invited Team Members' "My Games" → Team tab → "Games Awaiting confirmation":** ✅ YES (immediately after creation)
- **All Creating Team Members' "Home → Pending Approval":** ❌ NO (not yet - waiting for opponent team admin to accept)
- **Invited Team Admins' "Home → Pending Admin Approval":** ✅ YES (they see the invite to accept/deny)
- **Other Users' "Discover" tab:** ❌ NO (invite-specific games are NOT public)

### **Acceptance Flow:**
- When an invited team admin clicks "Accept":
  - Invite status changes to `'accepted'`
  - Game `status` changes to `'matched'`
  - Game `matched_team_id` is set to the accepting team
  - **All members of BOTH teams** get attendance records with `status = 'pending'` (if not already created)
  - Game moves from "Games Awaiting confirmation" to confirmed games in "My Games"
  - **All members of BOTH teams** see the game in "Home → Pending Approval" for availability
- When an invited team admin clicks "Deny":
  - Invite status changes to `'denied'`
  - Game is removed from that team's "Games Awaiting confirmation"
  - If all invited teams deny, game can become public (if configured)

---

## Summary Table

| Game Type | Created In | Attendance Created | Invites Created | Appears in "My Games" | Appears in "Pending Approval" | Appears in "Discover" |
|-----------|------------|-------------------|-----------------|---------------------|------------------------------|----------------------|
| **IND Public** | `instant_match_requests` | Creator only (`accepted`) | None | Creator immediately | Others after requesting | All users (within 100mi) |
| **IND Friends Group** | `instant_match_requests` | All group members (`pending`) | None | All members immediately | All members immediately | No (private) |
| **Team Public** | `instant_match_requests` | Creating team members (`pending`) | None (open challenge) | Creating team immediately | After opponent joins | Team admins (within 100mi) |
| **Team Invited** | `instant_match_requests` | All team members (`pending`) | Yes (per invited team) | All teams immediately | After opponent accepts | No (private) |

---

## Key Differences:

1. **Individual Public:** Only creator gets attendance record initially; others must request to join
2. **Individual Friends Group:** All group members get attendance records immediately with pending status
3. **Team Public:** Only creating team gets attendance records; opponent team gets records when they join
4. **Team Invited:** Both creating and invited teams get attendance records immediately; game awaits admin acceptance

