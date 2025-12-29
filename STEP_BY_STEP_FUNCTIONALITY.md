# SportsDug App - Step-by-Step Functionality Guide

This document provides a comprehensive breakdown of all app functionality at each step level.

---

## Table of Contents
1. [App Initialization](#1-app-initialization)
2. [Authentication Flow](#2-authentication-flow)
3. [Profile Setup](#3-profile-setup)
4. [Main Navigation Structure](#4-main-navigation-structure)
5. [Home Tab Functionality](#5-home-tab-functionality)
6. [Discover Tab Functionality](#6-discover-tab-functionality)
7. [My Games Tab Functionality](#7-my-games-tab-functionality)
8. [Chat Tab Functionality](#8-chat-tab-functionality)
9. [Profile Tab Functionality](#9-profile-tab-functionality)
10. [Game Creation Flows](#10-game-creation-flows)
11. [Game Management Actions](#11-game-management-actions)

---

## 1. App Initialization

### Step 1.1: App Launch
- **Action**: User opens the app
- **What Happens**:
  - Flutter binding initialized
  - App configuration validated (`AppConfig.validate()`)
  - App info initialized (name, version)
  - Firebase initialized (if enabled)
  - Sentry error tracking initialized (if configured)
  - Supabase client initialized (if credentials provided)
  - Error handling setup

### Step 1.2: Authentication Check
- **Action**: App checks authentication state
- **What Happens**:
  - `AuthGate` widget listens to Supabase auth state changes
  - If no session exists → Redirects to `AuthSignInScreen`
  - If session exists → Redirects to `HomeTabsScreen`

---

## 2. Authentication Flow

### Step 2.1: Sign In Screen Display
- **Action**: User sees sign-in screen
- **What Happens**:
  - Email and password input fields displayed
  - SportsDug logo displayed
  - Sign in/Sign up button available

### Step 2.2: User Authentication
- **Action**: User enters email/password and clicks button
- **What Happens**:
  1. App attempts **sign in** first
  2. If sign in fails → Attempts **sign up** (auto-registration)
  3. Session created → Auth state changes
  4. `AuthGate` detects session → Redirects to `HomeTabsScreen`

### Step 2.3: First-Time User Flow
- **Action**: New user signs up
- **What Happens**:
  - User account created in Supabase Auth
  - User record created in `users` table
  - Redirected to Profile Setup (if profile incomplete)

---

## 3. Profile Setup

### Step 3.1: Profile Information Entry
- **Action**: User fills out profile
- **What Happens**:
  - Name, location (ZIP code), photo upload
  - Profile saved to `users` table
  - Location stored for game discovery

### Step 3.2: Sports Selection
- **Action**: User selects sports interests
- **What Happens**:
  - Navigate to `SelectSportsScreen`
  - User selects from available sports:
    - Badminton, Cricket, Tennis, Table Tennis, Pickleball, Football, Basketball, Volleyball
  - Selections saved to `user_sports` table
  - Used for game discovery filtering

### Step 3.3: Friends Management
- **Action**: User manages friends
- **What Happens**:
  - Navigate to `FriendsScreen`
  - View existing friends
  - Create friends groups (sport-specific)
  - Add members to friends groups
  - Friends groups used for private game creation

### Step 3.4: Teams Management
- **Action**: User manages teams
- **What Happens**:
  - Navigate to `TeamsScreen`
  - View teams user is member of
  - Create new team (becomes admin)
  - Join existing team
  - View team details, members, roles

---

## 4. Main Navigation Structure

### Step 4.1: Tab Bar Display
- **Action**: User sees main navigation
- **Tabs Available**:
  1. **Home** - Main dashboard with pending actions
  2. **Discover** - Browse and find games
  3. **My Games** - View all user's games
  4. **Chat** - Messaging interface
  5. **Profile** - User profile and settings

### Step 4.2: Tab Initialization
- **Action**: Each tab loads on first access
- **What Happens**:
  - `HomeTabsController` initializes
  - Loads user basics (name, sports, location)
  - Loads admin teams and invites
  - Loads all games (confirmed, pending, awaiting)
  - Loads discovery games
  - Sets up realtime subscriptions for live updates

---

## 5. Home Tab Functionality

### Step 5.1: Home Tab Display
- **Action**: User navigates to Home tab
- **Sections Displayed**:
  1. **Location Display** - Current location (GPS or manual)
  2. **Create Game Button** - Quick access to game creation
  3. **Pending Admin Approval** - Team game invites requiring admin action
  4. **Pending Approval** - Games requiring user availability response
  5. **Pending Confirmation** - Team games awaiting opponent acceptance

### Step 5.2: Location Management
- **Action**: User views/updates location
- **What Happens**:
  - Displays current location (city, state from ZIP)
  - Uses GPS location (with 3-second timeout)
  - Falls back to last known ZIP from database
  - Falls back to cached location
  - User can manually set location via location picker dialog
  - Location used for game discovery distance calculations

### Step 5.3: Pending Admin Approval Section
- **Action**: Admin sees team game invites
- **What Happens**:
  - Shows team games where user is admin of invited team
  - Displays: Creating team name, date/time, venue
  - Shows **"Accept"** and **"Deny"** buttons
  - Only visible to team admins

### Step 5.4: Pending Approval Section
- **Action**: User sees games requiring availability response
- **What Happens**:
  - Shows individual games with pending attendance
  - Shows team games (after opponent accepts) with pending attendance
  - Displays: Sport, date/time, venue, spots left
  - Shows **"Available"** and **"Not Available"** buttons
  - User must respond to mark availability

### Step 5.5: Pending Confirmation Section
- **Action**: User sees team games awaiting opponent
- **What Happens**:
  - Shows team games created by user's team
  - Game status: "Awaiting opponent confirmation"
  - Displays: Opponent team names or "Open challenge"
  - Admin can see **"Cancel Game"** button
  - Game moves to "Confirmed" after opponent accepts

---

## 6. Discover Tab Functionality

### Step 6.1: Discover Tab Display
- **Action**: User navigates to Discover tab
- **What Happens**:
  - Loads public games within 100 miles
  - Filters by user's sports interests
  - Shows distance from user's location
  - Displays individual games and team games (open challenges)

### Step 6.2: Game Discovery Filtering
- **Action**: System filters discoverable games
- **Filters Applied**:
  - `visibility = 'public'` OR `is_public = true`
  - Within 100 miles of user's location (ZIP-based)
  - Matches user's notification preferences (sport, radius)
  - For team games: User must be admin of team in same sport
  - Game status must be `'open'` (not cancelled)

### Step 6.3: Individual Game Discovery
- **Action**: User sees public individual game
- **Display Shows**:
  - Sport name
  - Date and time
  - Venue
  - Distance from user
  - Number of players and spots left
  - **"Request to Join"** button

### Step 6.4: Team Game Discovery (Open Challenge)
- **Action**: User (admin) sees public team game
- **Display Shows**:
  - Sport name
  - Date and time
  - Venue
  - Creating team name
  - Distance from user
  - **"Accept"** or **"Request to Join"** button

### Step 6.5: Request to Join Individual Game
- **Action**: User clicks "Request to Join" on individual game
- **What Happens**:
  1. Creates attendance record in `individual_game_attendance`:
     - `status = 'pending'`
     - Requires organizer approval
  2. Game appears in:
     - User's "My Games → Individual" (with "Waiting for approval" status)
     - User's "Home → Pending Approval"
     - Organizer's "Home → Pending Approval" (for approval)

### Step 6.6: Accept Team Game (Open Challenge)
- **Action**: Admin clicks "Accept" on team game
- **What Happens**:
  1. Creates invite record in `instant_request_invites`:
     - `status = 'accepted'`
  2. Updates game status to `'matched'`
  3. Sets `matched_team_id` to accepting team
  4. Creates attendance records for ALL members of both teams:
     - `status = 'pending'` (members mark availability)
  5. Game appears in:
     - Both teams' "My Games → Team Games → Confirmed"
     - Both teams' "Home → Pending Approval"
  6. Game removed from Discover tab (no longer accepting teams)

---

## 7. My Games Tab Functionality

### Step 7.1: My Games Tab Display
- **Action**: User navigates to My Games tab
- **Tabs Available**:
  - **Team Games** - All team games
  - **Individual Games** - All individual games

### Step 7.2: Team Games Tab
- **Action**: User views Team Games
- **Sections**:
  1. **Confirmed** - Active team games with confirmed opponent
  2. **Awaiting Opponent Confirmation** - Games waiting for opponent to accept
  3. **Past** - Completed games
  4. **Cancelled** - Cancelled games

### Step 7.3: Individual Games Tab
- **Action**: User views Individual Games
- **Sections**:
  1. **Current** - Active individual games
  2. **Past** - Completed games
  3. **Cancelled** - Cancelled games
  4. **Hidden** - Hidden games

### Step 7.4: Game Card Display (Collapsed)
- **Action**: User sees game in list
- **Shows**:
  - Sport name
  - Date and time
  - Venue
  - Status bar (attendance percentage)
  - Spots left / Opponent team name
  - Status text (e.g., "Waiting for organizer approval")

### Step 7.5: Game Card Display (Expanded)
- **Action**: User taps game card
- **Shows**:
  - Full game details
  - Creator name (marked as "Admin")
  - Player list with availability status
  - For team games: Both teams' player lists
  - Status bars (game level and team level)
  - Action buttons:
    - **Open Map** - View location on map
    - **Reminder** - Set game reminder
    - **Chat** - Access game chat
    - **Leave** - Leave the game

### Step 7.6: Status Bar Display
- **Action**: User views attendance status
- **What Shows**:
  - **Game Level**: Overall attendance percentage
    - 100% = Green (all required players available)
    - 0% = Red (no players available)
    - Gradual color transition based on percentage
  - **Team Level** (team games): Each team's attendance percentage
    - Based on `expected_players_per_team` setting
    - Sport-specific defaults (e.g., 11 for cricket/soccer, 5 for basketball)

---

## 8. Chat Tab Functionality

### Step 8.1: Chat Tab Display
- **Action**: User navigates to Chat tab
- **What Happens**:
  - Shows list of chat conversations
  - Displays friends and game chats
  - Shows unread message counts

### Step 8.2: Game Chat Access
- **Action**: User opens game chat
- **What Happens**:
  - Navigate to `GameChatScreen`
  - Shows messages for specific game
  - All game participants can see and send messages
  - Real-time message updates

### Step 8.3: Direct Message Chat
- **Action**: User chats with friend
- **What Happens**:
  - Navigate to `ChatDetailScreen`
  - One-on-one messaging
  - Real-time message delivery

---

## 9. Profile Tab Functionality

### Step 9.1: Profile Tab Display
- **Action**: User navigates to Profile tab
- **Shows**:
  - User name and photo
  - Location
  - Sports interests
  - Friends count
  - Teams count

### Step 9.2: Profile Editing
- **Action**: User edits profile
- **What Happens**:
  - Navigate to `UserProfileScreen`
  - Update name, location, photo
  - Changes saved to `users` table

### Step 9.3: Sports Management
- **Action**: User manages sports
- **What Happens**:
  - Navigate to `SelectSportsScreen`
  - Add/remove sports interests
  - Changes saved to `user_sports` table
  - Affects game discovery filtering

### Step 9.4: Friends Management
- **Action**: User manages friends
- **What Happens**:
  - Navigate to `FriendsScreen`
  - View friends list
  - Create friends groups
  - Add/remove friends from groups
  - Friends groups are sport-specific

### Step 9.5: Teams Management
- **Action**: User manages teams
- **What Happens**:
  - Navigate to `TeamsScreen`
  - View all teams user is member of
  - Create new team (becomes admin)
  - View team details
  - Manage team members (if admin)
  - Leave team

### Step 9.6: Sign Out
- **Action**: User signs out
- **What Happens**:
  - Supabase session cleared
  - Redirected to `AuthSignInScreen`
  - All cached data cleared

---

## 10. Game Creation Flows

### 10.1: Access Create Game
- **Action**: User clicks "Create Game" button
- **What Happens**:
  - Navigate to `CreateGameScreen`
  - Choose game type:
    - **Individual Game**
    - **Team vs Team**

### 10.2: Individual Game Creation - Public

#### Step 10.2.1: Fill Game Details
- **Action**: User fills form
- **Fields**:
  - Sport (dropdown)
  - Number of Players
  - Skill Level (Recreational, Intermediate, Competitive)
  - Date & Time (start and end)
  - Venue (location name/address)
  - Game Details (optional)

#### Step 10.2.2: Select Visibility
- **Action**: User selects "Public"
- **What Happens**:
  - Game will be visible to all users within 100 miles
  - No friends group selection needed

#### Step 10.2.3: Create Game
- **Action**: User clicks "Create Game"
- **Database Operations**:
  1. Insert into `instant_match_requests`:
     - `visibility = 'public'`
     - `is_public = true`
     - `radius_miles = 100`
     - `status = 'open'`
  2. Create attendance record for creator:
     - `status = 'accepted'` (creator auto-accepted)

#### Step 10.2.4: Post-Creation
- **What Happens**:
  - Game appears in creator's "My Games → Individual"
  - Game appears in "Discover" tab for all users within 100 miles
  - Other users can request to join
  - Creator approves/denies requests in "Home → Pending Approval"

### 10.3: Individual Game Creation - Friends Group

#### Step 10.3.1: Fill Game Details
- **Action**: User fills form (same as public)
- **Fields**: Same as public individual game

#### Step 10.3.2: Select Visibility
- **Action**: User selects "Friends Group"
- **What Happens**:
  - If no friends groups exist:
    - Shows message: "You currently do not have friends group"
    - Provides link to create friends group
    - Redirects to Profile → Friends Groups
  - If friends groups exist:
    - Dropdown shows: "Group Name (Sport)"
    - User selects group

#### Step 10.3.3: Create Game
- **Action**: User clicks "Create Game"
- **Database Operations**:
  1. Insert into `instant_match_requests`:
     - `visibility = 'friends_group'`
     - `is_public = false`
     - `friends_group_id = selected group ID`
     - `status = 'open'`
  2. Create attendance records for **ALL group members**:
     - Including organizer
     - `status = 'pending'` (all start as pending)

#### Step 10.3.4: Post-Creation
- **What Happens**:
  - Game appears in ALL group members' "My Games → Individual"
  - Game appears in ALL group members' "Home → Pending Approval"
  - Members mark availability (Available/Not Available)
  - Auto-friending occurs when members accept

### 10.4: Team Game Creation - Invite Specific Teams

#### Step 10.4.1: Fill Game Details
- **Action**: Admin fills form
- **Fields**:
  - Sport (dropdown)
  - Your Team (dropdown of user's admin teams)
  - Opponent Type: "Invite specific teams"
  - Opponent Teams (select one or more)
  - Date & Time
  - Venue
  - Expected Players per Team
  - Game Details (optional)

#### Step 10.4.2: Create Game
- **Action**: Admin clicks "Create Game"
- **Database Operations**:
  1. Insert into `instant_match_requests`:
     - `mode = 'team_vs_team'`
     - `visibility = 'invited'`
     - `is_public = false`
     - `status = 'open'`
     - `matched_team_id = null` (awaiting acceptance)
  2. Create invites in `instant_request_invites`:
     - One record per invited team
     - `status = 'pending'`
  3. Create attendance records:
     - For ALL members of creating team: `status = 'pending'`
     - For ALL members of each invited team: `status = 'pending'`

#### Step 10.4.3: Post-Creation
- **What Happens**:
  - Game appears in creating team's "My Games → Team Games → Awaiting Opponent Confirmation"
  - Game appears in invited team admins' "Home → Pending Admin Approval"
  - Invited team admins accept/deny
  - If accepted: Game moves to "Confirmed" for both teams
  - If all deny: Game can become public (if configured)

### 10.5: Team Game Creation - Open Challenge

#### Step 10.5.1: Fill Game Details
- **Action**: Admin fills form
- **Fields**:
  - Sport (dropdown)
  - Your Team (dropdown)
  - Opponent Type: "Open challenge"
  - Date & Time
  - Venue
  - Expected Players per Team
  - Game Details (optional)

#### Step 10.5.2: Create Game
- **Action**: Admin clicks "Create Game"
- **Database Operations**:
  1. Insert into `instant_match_requests`:
     - `mode = 'team_vs_team'`
     - `visibility = 'public'`
     - `is_public = true`
     - `status = 'open'`
  2. Create attendance records for creating team:
     - ALL members: `status = 'pending'`
  3. NO invites created (open challenge)

#### Step 10.5.3: Post-Creation
- **What Happens**:
  - Game appears in creating team's "My Games → Team Games → Awaiting Opponent Confirmation"
  - Game appears in "Discover" tab for team admins (same sport, within 100 miles)
  - Other team admins can accept from Discover tab
  - Once accepted: Game moves to "Confirmed" for both teams

---

## 11. Game Management Actions

### 11.1: Mark Availability (Individual Games)

#### Step 11.1.1: View Pending Game
- **Action**: User sees game in "Home → Pending Approval"
- **Shows**: "Available" and "Not Available" buttons

#### Step 11.1.2: Mark Available
- **Action**: User clicks "Available"
- **What Happens**:
  1. Updates `individual_game_attendance.status` to `'accepted'`
  2. User counted in game attendance
  3. Game moves to "My Games → Individual"
  4. Auto-friending occurs (if other users also accepted)

#### Step 11.1.3: Mark Not Available
- **Action**: User clicks "Not Available"
- **What Happens**:
  1. Updates `individual_game_attendance.status` to `'denied'`
  2. User NOT counted in game attendance
  3. Game still appears in "My Games" but user not counted
  4. No auto-friending

### 11.2: Approve/Deny Individual Game Request

#### Step 11.2.1: View Pending Request
- **Action**: Organizer sees request in "Home → Pending Approval"
- **Shows**: Requester name, game details, "Approve" and "Deny" buttons

#### Step 11.2.2: Approve Request
- **Action**: Organizer clicks "Approve"
- **What Happens**:
  1. Updates `individual_game_attendance.status` to `'accepted'`
  2. User counted in game attendance
  3. Game appears in requester's "My Games"
  4. Auto-friending occurs (friendship created)

#### Step 11.2.3: Deny Request
- **Action**: Organizer clicks "Deny"
- **What Happens**:
  1. Updates `individual_game_attendance.status` to `'denied'`
  2. User NOT counted
  3. Game still appears in requester's "My Games" but user not counted
  4. No friendship created

### 11.3: Accept/Deny Team Game Invite (Admin)

#### Step 11.3.1: View Invite
- **Action**: Admin sees invite in "Home → Pending Admin Approval"
- **Shows**: Creating team name, game details, "Accept" and "Deny" buttons

#### Step 11.3.2: Accept Invite
- **Action**: Admin clicks "Accept"
- **What Happens**:
  1. Updates `instant_request_invites.status` to `'accepted'`
  2. Updates `instant_match_requests.status` to `'matched'`
  3. Sets `matched_team_id` to accepting team
  4. Creates/updates attendance records for BOTH teams:
     - All members: `status = 'pending'`
  5. Accepting admin's attendance auto-set to `'accepted'`
  6. Game appears in:
     - Both teams' "My Games → Team Games → Confirmed"
     - Both teams' "Home → Pending Approval"
  7. Game removed from "Awaiting Opponent Confirmation"

#### Step 11.3.3: Deny Invite
- **Action**: Admin clicks "Deny"
- **What Happens**:
  1. Updates `instant_request_invites.status` to `'denied'`
  2. Game removed from admin's "Pending Admin Approval"
  3. Game removed from team members' "Awaiting Opponent Confirmation"
  4. If ALL invited teams deny:
     - Game becomes public: `visibility = 'public'`, `is_public = true`
     - Game appears in "Discover" tab

### 11.4: Mark Availability (Team Games)

#### Step 11.4.1: View Pending Game
- **Action**: Team member sees game in "Home → Pending Approval"
- **Shows**: "Available" and "Not Available" buttons

#### Step 11.4.2: Mark Available
- **Action**: Member clicks "Available"
- **What Happens**:
  1. Updates `team_match_attendance.status` to `'accepted'`
  2. Member counted in team attendance
  3. Status bar updates (team level and game level)
  4. Game remains in "My Games → Team Games → Confirmed"

#### Step 11.4.3: Mark Not Available
- **Action**: Member clicks "Not Available"
- **What Happens**:
  1. Updates `team_match_attendance.status` to `'denied'`
  2. Member NOT counted in team attendance
  3. Status bar updates
  4. Game remains visible but member not counted

### 11.5: Cancel Team Game

#### Step 11.5.1: View Game
- **Action**: Admin views game in "My Games → Team Games → Awaiting Opponent Confirmation"
- **Shows**: "Cancel Game" button (admins only)

#### Step 11.5.2: Cancel Game
- **Action**: Admin clicks "Cancel Game"
- **What Happens**:
  1. Updates `instant_match_requests.status` to `'cancelled'`
  2. Game removed from:
     - Creating team's "Awaiting Opponent Confirmation"
     - Invited teams' "Pending Admin Approval"
     - Invited team members' "Awaiting Opponent Confirmation"
  3. Game appears in "My Games → Cancelled" tab

### 11.6: Leave Game

#### Step 11.6.1: View Game
- **Action**: User views game in "My Games"
- **Shows**: "Leave" button in expanded view

#### Step 11.6.2: Leave Game
- **Action**: User clicks "Leave"
- **What Happens**:
  1. For individual games:
     - Updates `individual_game_attendance.status` to `'denied'` or deletes record
  2. For team games:
     - Updates `team_match_attendance.status` to `'denied'`
  3. User removed from attendance count
  4. Game may be hidden or removed from user's view

### 11.7: Set Game Reminder

#### Step 11.7.1: View Game
- **Action**: User views game in "My Games"
- **Shows**: "Reminder" button

#### Step 11.7.2: Set Reminder
- **Action**: User clicks "Reminder"
- **What Happens**:
  - Opens reminder dialog
  - User selects reminder time (e.g., 1 hour before, 1 day before)
  - Reminder scheduled
  - Notification sent at specified time

### 11.8: Open Map

#### Step 11.8.1: View Game
- **Action**: User views game in "My Games"
- **Shows**: "Open Map" button

#### Step 11.8.2: Open Map
- **Action**: User clicks "Open Map"
- **What Happens**:
  - Opens map view with game location
  - Shows venue address
  - Provides directions option
  - Displays distance from user's location

### 11.9: Access Game Chat

#### Step 11.9.1: View Game
- **Action**: User views game in "My Games"
- **Shows**: "Chat" button (if enabled)

#### Step 11.9.2: Open Chat
- **Action**: User clicks "Chat"
- **What Happens**:
  - Navigate to `GameChatScreen`
  - Shows all messages for the game
  - All game participants can see and send messages
  - Real-time message updates

---

## Key Database Tables Reference

### Core Tables
- **`users`** - User profiles and basic info
- **`user_sports`** - User sports interests
- **`friends`** - Friendships between users
- **`friends_groups`** - Friends group definitions
- **`friends_group_members`** - Friends group membership
- **`teams`** - Team definitions
- **`team_members`** - Team membership and roles

### Game Tables
- **`instant_match_requests`** - Main game records
  - `visibility`: `'friends_group'`, `'public'`, `'invited'`
  - `is_public`: Boolean flag
  - `status`: `'open'`, `'matched'`, `'cancelled'`
  - `mode`: `'pickup'` (individual), `'team_vs_team'`
- **`individual_game_attendance`** - Individual game attendance
  - `status`: `'pending'`, `'accepted'`, `'denied'`
- **`team_match_attendance`** - Team game attendance
  - `status`: `'pending'`, `'accepted'`, `'denied'`
- **`instant_request_invites`** - Team game invites
  - `status`: `'pending'`, `'accepted'`, `'denied'`
  - `target_type`: `'team'`

---

## Key Features Summary

### Individual Games
- ✅ Public games visible to all users within 100 miles
- ✅ Friends group games private to group members
- ✅ Creator auto-accepted in public games
- ✅ All members start pending in friends group games
- ✅ Organizer approval required for public game requests
- ✅ Self-select availability for friends group games
- ✅ Auto-friending when users accept same game

### Team Games
- ✅ Specific team invites (private)
- ✅ Open challenge (public)
- ✅ Admin approval required for team invites
- ✅ All members see game after admin accepts
- ✅ Members mark availability after confirmation
- ✅ Status bars show game and team level attendance
- ✅ Admins can cancel games
- ✅ If all teams deny, game can become public

### General Features
- ✅ Real-time updates via Supabase subscriptions
- ✅ Distance-based game discovery (100-mile radius)
- ✅ Sport-specific filtering
- ✅ Location management (GPS + manual)
- ✅ Game chat functionality
- ✅ Reminder system
- ✅ Map integration
- ✅ Status indicators (attendance percentages)

---

*Last Updated: Based on current codebase implementation*

