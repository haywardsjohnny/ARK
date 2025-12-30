# Home Screen Changes - Specific Code Modifications

## Overview
This document outlines the **exact code changes** needed to implement the Home Screen enhancements:
1. Remove Join Game button
2. Move Create Game to floating button
3. Replace Join/Create section with Smart Cards

---

## Changes Required

### 1. Remove Join Game Button & Move Create Game to FAB

#### Current Structure (in `_buildHomeTab()`):
```dart
Widget _buildHomeTab() {
  return Scaffold(
    body: RefreshIndicator(...),
    // NO floatingActionButton currently
  );
}
```

#### New Structure:
```dart
Widget _buildHomeTab() {
  return Scaffold(
    body: RefreshIndicator(...),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: _showCreateInstantMatchSheet,
      backgroundColor: const Color(0xFF14919B), // Your teal color
      icon: const Icon(Icons.add_circle_outline, color: Colors.white),
      label: const Text(
        'Create Game',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    ),
    floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
  );
}
```

**File:** `lib/screens/home_tabs/home_tabs_screen.dart`
**Line:** ~1898 (in `_buildHomeTab()` method)

---

### 2. Replace `_buildMyActivePlansSection()` with Enhanced Smart Cards

#### Current Code (lines ~2124-2306):
```dart
Widget _buildMyActivePlansSection() {
  return Column(
    children: [
      // "My Quick Actions" header
      // Join Game card (lines 2147-2222)
      // Create Game card (lines 2226-2300)
    ],
  );
}
```

#### Change: Replace entire section call

**In `_buildHomeTab()` (line ~1929):**

**OLD:**
```dart
// My Active Plans (Join/Create Game)
_buildMyActivePlansSection(),
```

**NEW:**
```dart
// Smart Cards (replaces Join/Create section)
// Note: Smart Cards section is already below, just remove this line
// and enhance _buildSmartCardsSection() instead
```

**OR** - Keep the section but change its content:

**Option A: Remove the section entirely**
- Delete call to `_buildMyActivePlansSection()` at line ~1929
- Delete the `_buildMyActivePlansSection()` method (lines ~2124-2306)
- Enhance `_buildSmartCardsSection()` to show in that location

**Option B: Replace section content with Smart Cards**
- Keep the section wrapper
- Replace Join/Create cards with Smart Cards
- Rename method to `_buildSmartCardsSection()` (or keep separate)

**Recommendation: Option A** - Remove `_buildMyActivePlansSection()` entirely and enhance existing `_buildSmartCardsSection()`

---

### 3. Enhance Smart Cards Section

#### Current Structure (lines ~2376-2400):
```dart
Widget _buildSmartCardsSection() {
  final cards = _buildSmartCards();
  
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Cards display
    ],
  );
}
```

#### Enhanced Implementation:

**File:** `lib/screens/home_tabs/home_tabs_screen.dart`

**Add new method to generate smart cards:**

```dart
List<SmartCard> _buildSmartCards() {
  final cards = <SmartCard>[];
  
  // Priority 1: Action Required
  final pendingInvites = _controller.pendingAdminMatches?.length ?? 0;
  final pendingTeamInvites = /* Get pending team/group invites */;
  
  if (pendingTeamInvites > 0) {
    cards.add(SmartCard(
      type: 'action_required',
      title: 'Team Invitation',
      message: 'You have been added to a team/group, please accept.',
      actionLabel: 'View Invites',
      priority: 1,
      onTap: () {
        // Navigate to profile or teams screen to see invites
        setState(() => _controller.selectedIndex = 4); // Profile tab
      },
    ));
  }
  
  if (pendingInvites > 0) {
    cards.add(SmartCard(
      type: 'action_required',
      title: 'Games Awaiting Action',
      message: 'You have $pendingInvites games awaiting your action.',
      actionLabel: 'View',
      priority: 1,
      onTap: () {
        // Navigate to pending approval section
        setState(() => _pendingAdminExpanded = true);
      },
    ));
  }
  
  // Priority 2: Upcoming Games
  final confirmedGames = _controller.confirmedTeamMatches.length;
  if (confirmedGames > 0) {
    cards.add(SmartCard(
      type: 'upcoming',
      title: 'Confirmed Games',
      message: confirmedGames == 1
          ? 'You have 1 confirmed game scheduled and ready to play.'
          : 'You have $confirmedGames confirmed games scheduled and ready to play.',
      actionLabel: 'View Games',
      priority: 2,
      onTap: () {
        setState(() => _controller.selectedIndex = 2); // My Games tab
      },
    ));
  }
  
  // Priority 3: Discovery
  final nearbyGames = /* Get nearby games count */;
  if (nearbyGames > 0) {
    cards.add(SmartCard(
      type: 'discovery',
      title: 'Games Near You',
      message: '$nearbyGames games near ${_currentLocation ?? "your location"} this week',
      actionLabel: 'Discover',
      priority: 3,
      onTap: () {
        setState(() => _controller.selectedIndex = 1); // Discover tab
      },
    ));
  }
  
  // Priority 4: Onboarding
  final userSports = _controller.userSports;
  if (userSports.isEmpty || userSports.length < 2) {
    cards.add(SmartCard(
      type: 'onboarding',
      title: 'Add Sports',
      message: 'Add your favorite sports to get better matches',
      actionLabel: 'Add Sports',
      priority: 4,
      onTap: () {
        // Navigate to profile to add sports
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const UserProfileScreen()),
        );
      },
    ));
  }
  
  if (confirmedGames == 0 && pendingInvites == 0) {
    cards.add(SmartCard(
      type: 'onboarding',
      title: 'Get Started',
      message: 'No games yet — create one in under 60 seconds',
      actionLabel: 'Create Game',
      priority: 4,
      onTap: _showCreateInstantMatchSheet,
    ));
  }
  
  // Sort by priority (1 = highest)
  cards.sort((a, b) => a.priority.compareTo(b.priority));
  
  // Return top 3 cards
  return cards.take(3).toList();
}
```

**Add SmartCard model class (add at top of file):**

```dart
class SmartCard {
  final String type; // 'action_required', 'upcoming', 'discovery', 'onboarding'
  final String title;
  final String message;
  final String? actionLabel;
  final int priority;
  final VoidCallback? onTap;
  
  SmartCard({
    required this.type,
    required this.title,
    required this.message,
    this.actionLabel,
    required this.priority,
    this.onTap,
  });
}
```

**Update `_buildSmartCardsSection()` method:**

```dart
Widget _buildSmartCardsSection() {
  final cards = _buildSmartCards();
  
  if (cards.isEmpty) {
    return const SizedBox.shrink();
  }
  
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Header (optional)
      // const Text(
      //   'Quick Updates',
      //   style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      // ),
      // const SizedBox(height: 12),
      
      // Cards (show up to 3)
      ...cards.map((card) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _buildSmartCardWidget(card),
      )),
    ],
  );
}

Widget _buildSmartCardWidget(SmartCard card) {
  // Determine colors based on card type
  Color cardColor;
  Color iconColor;
  IconData icon;
  
  switch (card.type) {
    case 'action_required':
      cardColor = Colors.orange.shade50;
      iconColor = Colors.orange.shade700;
      icon = Icons.notifications_active;
      break;
    case 'upcoming':
      cardColor = Colors.blue.shade50;
      iconColor = Colors.blue.shade700;
      icon = Icons.event;
      break;
    case 'discovery':
      cardColor = Colors.purple.shade50;
      iconColor = Colors.purple.shade700;
      icon = Icons.explore;
      break;
    case 'onboarding':
      cardColor = Colors.grey.shade100;
      iconColor = Colors.grey.shade700;
      icon = Icons.info_outline;
      break;
    default:
      cardColor = Colors.grey.shade100;
      iconColor = Colors.grey.shade700;
      icon = Icons.info;
  }
  
  return Card(
    elevation: 2,
    color: cardColor,
    child: InkWell(
      onTap: card.onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 16),
            
            // Text content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: iconColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    card.message,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                  if (card.actionLabel != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      card.actionLabel!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: iconColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            // Arrow
            Icon(Icons.chevron_right, color: iconColor.withOpacity(0.5)),
          ],
        ),
      ),
    ),
  );
}
```

---

## Summary of Code Changes

### Files to Modify:
1. `lib/screens/home_tabs/home_tabs_screen.dart`

### Changes:

1. **Add FloatingActionButton to `_buildHomeTab()`** (line ~1898)
   - Add `floatingActionButton` property to Scaffold
   - Link to `_showCreateInstantMatchSheet`

2. **Remove `_buildMyActivePlansSection()` call** (line ~1929)
   - Delete the line that calls this method
   - OR replace it with enhanced smart cards

3. **Delete `_buildMyActivePlansSection()` method** (lines ~2124-2306)
   - Entire method can be removed

4. **Add SmartCard model class** (add near top of file, after imports)
   - Simple data class for card information

5. **Replace `_buildSmartCards()` method** (if it exists, or create new)
   - Implement logic to generate cards based on user state
   - Return prioritized list of cards

6. **Update `_buildSmartCardsSection()` method** (line ~2376)
   - Call new `_buildSmartCards()` method
   - Display cards using `_buildSmartCardWidget()`

7. **Add `_buildSmartCardWidget()` method** (new method)
   - Builds individual card widget
   - Handles styling based on card type

---

## Implementation Steps

1. **Step 1:** Add FloatingActionButton
   - Test that Create Game still works

2. **Step 2:** Remove Join Game button
   - Delete `_buildMyActivePlansSection()` call
   - Test that navigation still works

3. **Step 3:** Add SmartCard model
   - Simple data class, no logic

4. **Step 4:** Implement `_buildSmartCards()` logic
   - Start with one card type
   - Test, then add more

5. **Step 5:** Add card rendering
   - Implement `_buildSmartCardWidget()`
   - Style cards appropriately

6. **Step 6:** Test all card types
   - Action required cards
   - Upcoming games cards
   - Discovery cards
   - Onboarding cards

---

## Data Needed for Smart Cards

To implement smart cards, you'll need access to:

1. **Pending invites count:**
   - `_controller.pendingAdminMatches.length`
   - Need to query for pending team/group invites

2. **Confirmed games count:**
   - `_controller.confirmedTeamMatches.length`

3. **Nearby games count:**
   - `_controller.discoveryPickupMatches.length`
   - Or query for games near user's location

4. **User sports:**
   - `_controller.userSports` (need to check if this exists)

5. **Team/Group invites:**
   - May need to query `team_members` table for pending invites
   - May need to query `friends_group_members` table

---

## Testing Checklist

After implementing:

- [ ] FloatingActionButton appears on home screen
- [ ] Create Game works from FAB
- [ ] Join Game button is removed
- [ ] Smart cards appear in place of Join/Create section
- [ ] Smart cards show correct information
- [ ] Tapping cards navigates correctly
- [ ] Cards update when data changes
- [ ] Maximum 3 cards shown
- [ ] Cards prioritized correctly (action required first)
- [ ] All card types render correctly
- [ ] No errors in console

---

## Notes

- **Smart Cards Location:** Currently smart cards are below the dark section. You may want to move them up to replace the Join/Create section location (inside the dark section).

- **Data Loading:** Make sure smart card data is loaded when home tab loads (check `_controller.init()` and `_buildHomeTab()` refresh logic).

- **Performance:** Limit to 3 cards max. Cache card data if needed to avoid excessive queries.

- **Styling:** Match your app's design system. Colors suggested above are examples.

