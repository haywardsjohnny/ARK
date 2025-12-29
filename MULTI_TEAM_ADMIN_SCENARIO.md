# Multi-Team Admin Scenario Analysis

## Scenario
User is admin of **Team X** and **Team M** (both same sport, e.g., Cricket)
**Team A** creates a public game in the same sport

## Current Behavior

### 1. When User Clicks "Join" on Team A's Public Game

**Code Location:** `lib/screens/home_tabs/home_tabs_controller.dart:595-614`

```dart
// Find admin team for this sport
final matchingTeam = adminTeams.firstWhere(
  (t) => (t['sport'] as String? ?? '').toLowerCase() == sport.toLowerCase(),
  orElse: () => <String, dynamic>{},
);
```

**Issue:** Uses `firstWhere` which picks the **first** matching team in the list. The order depends on how teams are loaded from the database.

**Result:**
- If Team X appears first → Creates invite with `target_team_id = Team X`
- If Team M appears first → Creates invite with `target_team_id = Team M`
- **No way for user to choose which team to use**

### 2. Status Display in Discover Tab

**Code Location:** `lib/screens/home_tabs/home_tabs_controller.dart:806-833`

```dart
final userTeamInvites = <String, Map<String, dynamic>>{}; // request_id -> {status, target_team_id}
// ...
userTeamInvites[reqId] = {
  'status': status,
  'target_team_id': teamId,
};
```

**Issue:** Only stores ONE status per `request_id`. If user joins as Team X, then Team M's status (if any) is not tracked separately.

**Result:**
- If Team X has pending invite → Shows "Request has been sent..." for Team X
- If user tries to join as Team M later → Error: "You have already requested to join this game"
- Status message only reflects the first team that joined

### 3. "Pending Admin Approval" Visibility

**Code Location:** `lib/data/home_repository.dart:187-196` (getPendingInvitesForTeams)

**Current Fix:** Filters out public games where user's team is the responding team.

**Result:**
- ✅ User (as Team X/M admin) does NOT see Team A's game in "Pending Admin Approval"
- ✅ Only Team A admins see pending requests from Team X/M
- ✅ This is correct behavior

### 4. What Happens if User Joins as Both Teams?

**Current Limitation:**
- User clicks "Join" → Uses first team (e.g., Team X)
- Creates invite for Team X
- User cannot join again as Team M because:
  - Code checks: `existingInvite` where `target_team_id = joiningTeamId`
  - But the check is per team, so...
  - Actually, user CAN join as Team M if they manually change the team selection

**Wait, let me check the invite check logic...**

**Code Location:** `lib/data/home_repository.dart:445-461`

```dart
final existingInvite = await supa
    .from('instant_request_invites')
    .select('id, status')
    .eq('request_id', requestId)
    .eq('target_team_id', joiningTeamId)  // Checks per team
    .maybeSingle();
```

**Result:**
- If user joins as Team X → Creates invite for Team X
- If user tries to join as Team M → Checks if Team M already has invite
- Since Team M doesn't have invite yet, it would create a new invite for Team M
- **BUT** user has no way to select Team M because `firstWhere` always picks first team

## Summary of Current Behavior

1. **User clicks "Join"** → Always uses first team in adminTeams list (Team X or Team M, unpredictable)
2. **Status in Discover** → Shows status for whichever team was used
3. **Cannot join as second team** → No UI to select which team to use
4. **Pending Admin Approval** → User correctly does NOT see it (only Team A admins see it)
5. **Team A admins** → See separate requests for Team X and Team M (if both join)

## Potential Issues

1. **No team selection UI** - User cannot choose which team to join with
2. **Unpredictable team selection** - Depends on database order
3. **Status confusion** - If user is admin of multiple teams, status only shows for one team
4. **Multiple joins possible** - If user could select teams, they could join as both Team X and Team M, creating two separate requests

## Recommended Fix

Add a team selection dialog when user clicks "Join" and is admin of multiple teams in the same sport:

```dart
// Pseudo-code
if (adminTeamsForSport.length > 1) {
  // Show dialog to select which team to join with
  final selectedTeam = await showTeamSelectionDialog(adminTeamsForSport);
  joiningTeamId = selectedTeam['id'];
} else {
  joiningTeamId = adminTeamsForSport.first['id'];
}
```

This would allow:
- User to explicitly choose which team joins
- Clear status display per team
- Ability to join as multiple teams (if desired)
- Better UX

