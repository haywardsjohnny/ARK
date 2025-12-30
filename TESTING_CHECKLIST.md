# Testing Checklist - Scalability Changes

Use this checklist **after each phase** of scalability improvements.

---

## Phase 1: Database Indexes Only

### Pre-Testing
- [ ] Applied migration `048_add_scalability_indexes.sql`
- [ ] Migration completed without errors
- [ ] No database errors in Supabase dashboard

### Authentication & Profile
- [ ] Sign in works
- [ ] Sign up works (if applicable)
- [ ] Profile screen loads
- [ ] Profile data displays correctly
- [ ] Update profile works
- [ ] Profile photo uploads work

### Teams
- [ ] Teams screen loads
- [ ] User's teams display correctly
- [ ] Team details screen loads
- [ ] Team members list displays
- [ ] All team member names show (not "Player" or "Unknown")
- [ ] Create new team works
- [ ] Join team works
- [ ] Exit team works
- [ ] Team admin functions work

### Games - My Games Tab
- [ ] "My Games" tab loads
- [ ] Games created by user display
- [ ] Games user is attending display
- [ ] Game details show correctly
- [ ] Game rosters display correctly
- [ ] User names in rosters show correctly

### Games - Pending Admin Approval
- [ ] "Pending Admin Approval" tab loads
- [ ] Pending invites display
- [ ] Accept invite works
- [ ] Decline invite works
- [ ] Game status updates correctly after accept/decline

### Games - Confirmed Matches
- [ ] Confirmed matches display
- [ ] Match details show correctly
- [ ] Match rosters display
- [ ] User names in rosters show correctly

### Games - Discovery
- [ ] Discovery tab loads
- [ ] Public games display
- [ ] Filter by sport works
- [ ] Filter by distance works
- [ ] Game details show correctly

### Friends
- [ ] Friends screen loads
- [ ] Friends list displays
- [ ] Add friend works
- [ ] Friend names display correctly
- [ ] Remove friend works (if applicable)

### Individual Games
- [ ] Create individual game works
- [ ] Individual games display in "My Games"
- [ ] Join individual game works
- [ ] Individual game rosters display

### Team Games
- [ ] Create team game works
- [ ] Team game invites work
- [ ] Team game attendance works
- [ ] Team game rosters display

### Chat (if applicable)
- [ ] Chat messages load
- [ ] Send message works
- [ ] Message history displays

### Performance Checks
- [ ] No noticeable slowdowns
- [ ] No timeout errors
- [ ] No "query timeout" errors
- [ ] App feels responsive

### Error Checks
- [ ] No errors in Flutter console
- [ ] No errors in Supabase dashboard
- [ ] No PostgrestException errors
- [ ] No "structure of query does not match" errors

---

## Phase 2: Optional Pagination (If Applied)

### Pre-Testing
- [ ] Pagination helper added
- [ ] Pagination applied to friends/teams (if applicable)
- [ ] Default limits set high (1000+)

### Friends Pagination
- [ ] Friends list loads (should show all friends due to high default)
- [ ] No friends missing
- [ ] Friend names display correctly

### Teams Pagination
- [ ] Teams list loads (should show all teams due to high default)
- [ ] No teams missing
- [ ] Team details work correctly

### Performance Checks
- [ ] No slowdowns compared to Phase 1
- [ ] Query times similar or better

---

## Phase 3: RPC Function Limits (If Applied)

### Pre-Testing
- [ ] RPC functions updated with optional limit parameter
- [ ] Default limits set high (1000+)
- [ ] Existing code doesn't need changes

### RPC Function Tests
- [ ] `get_confirmed_matches_for_user()` returns expected results
- [ ] `get_all_matches_for_user()` returns expected results
- [ ] `get_match_requests_for_attendance()` returns expected results
- [ ] Users with < 1000 matches see all matches
- [ ] Users with > 1000 matches see first 1000 (acceptable)

### Match Display Tests
- [ ] "My Games" shows all user's games (up to limit)
- [ ] Confirmed matches display correctly
- [ ] Match rosters display correctly
- [ ] No missing matches for users with many games

---

## Critical Failure Indicators

**STOP AND ROLLBACK if you see:**

1. ❌ **Missing Data:**
   - Users can't see their teams
   - Users can't see their games
   - Team members missing
   - Friends missing

2. ❌ **Performance Degradation:**
   - Queries slower than before
   - Timeout errors
   - App feels sluggish

3. ❌ **Functionality Broken:**
   - Can't create games
   - Can't accept invites
   - Can't view matches
   - Can't update profile

4. ❌ **Errors:**
   - PostgrestException errors
   - "structure of query does not match" errors
   - Database connection errors
   - RPC function errors

---

## Rollback Decision Tree

### If Phase 1 Fails:
```
→ Drop indexes (see SAFE_SCALABILITY_PLAN.md)
→ Test again
→ If still broken → Check for other issues
```

### If Phase 2 Fails:
```
→ Revert code changes
→ Test again
→ If still broken → Check Phase 1 indexes
```

### If Phase 3 Fails:
```
→ Revert RPC function changes
→ Test again
→ If still broken → Check Phase 1 & 2
```

---

## Success Criteria

✅ **All tests pass**
✅ **No missing data**
✅ **No performance regressions**
✅ **No errors in logs**
✅ **User experience unchanged or better**

---

## Notes

- Test with real user accounts if possible
- Test with users who have many teams/games/friends
- Test edge cases (empty lists, single items, etc.)
- Monitor Supabase dashboard for query performance
- Check Flutter console for errors

---

## Sign-Off

**Phase 1 (Indexes):**
- [ ] All tests passed
- [ ] No issues found
- [ ] Ready for Phase 2

**Phase 2 (Pagination):**
- [ ] All tests passed
- [ ] No issues found
- [ ] Ready for Phase 3

**Phase 3 (RPC Limits):**
- [ ] All tests passed
- [ ] No issues found
- [ ] Scalability improvements complete

