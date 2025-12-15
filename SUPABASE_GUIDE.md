# Supabase Database Management Guide

## 🎯 What I Can Do For You

I can create and maintain:
- ✅ **SQL Migration Files** - Complete schema definitions
- ✅ **RPC Functions** - Database functions for business logic
- ✅ **RLS Policies** - Row Level Security policies
- ✅ **Indexes & Optimizations** - Performance improvements
- ✅ **Triggers** - Automated database actions
- ✅ **Documentation** - Clear instructions for applying changes

## 🚫 What I Cannot Do

- ❌ **Execute SQL directly** - I don't have access to your Supabase instance
- ❌ **See your database** - I can only work with what you show me in code
- ❌ **Test migrations** - You'll need to test in your environment

## 📋 Current Database Schema

Based on your code, your app uses these tables:

1. **users** - User profiles
2. **user_sports** - User sport preferences
3. **teams** - Team information
4. **team_members** - Team membership
5. **instant_match_requests** - Match requests
6. **instant_request_invites** - Match invites
7. **team_match_attendance** - Player attendance
8. **user_hidden_games** - Hidden games per user

**RPC Functions:**
- `approve_team_vs_team_invite` - Approves team vs team matches

## 🔄 How to Request Changes

When you need database changes, just tell me:

1. **What you want to change** (e.g., "Add a notifications table")
2. **Why you need it** (e.g., "To send push notifications")
3. **Any specific requirements** (e.g., "Should link to users table")

I'll create:
- Migration SQL file
- Updated RLS policies (if needed)
- Documentation on how to apply

## 📝 Example Workflow

**You:** "I need to add a notifications table"

**Me:** I'll create:
```sql
-- supabase/migrations/005_add_notifications.sql
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id),
    title TEXT NOT NULL,
    message TEXT,
    read BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
-- Plus indexes, RLS policies, etc.
```

**You:** Run the migration in Supabase Dashboard or via CLI

## 🛠️ Quick Commands

### Check Current Schema
```sql
-- In Supabase SQL Editor
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public';
```

### View RPC Functions
```sql
SELECT routine_name, routine_definition
FROM information_schema.routines
WHERE routine_schema = 'public';
```

### Check RLS Policies
```sql
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE schemaname = 'public';
```

## 🔍 Common Tasks I Can Help With

1. **Add new tables** - With proper indexes and RLS
2. **Modify existing tables** - Add columns, change types
3. **Create RPC functions** - Complex business logic
4. **Optimize queries** - Add indexes, rewrite queries
5. **Fix bugs** - Like the time_slot issue we fixed
6. **Add constraints** - Data validation at DB level
7. **Create views** - For complex queries
8. **Set up triggers** - Automated actions

## 📚 Migration Files Location

All migrations are in: `supabase/migrations/`

Apply them in order (001, 002, 003, etc.)

## ⚠️ Important Reminders

1. **Always backup** before running migrations in production
2. **Test first** in development/staging
3. **Run in order** - Migrations are numbered sequentially
4. **Review RLS** - Make sure policies match your security needs
5. **Check indexes** - Ensure performance is maintained

## 🆘 Need Help?

Just ask me:
- "Create a migration for [feature]"
- "Add an index for [table/column]"
- "Fix the RLS policy for [table]"
- "Create an RPC function for [operation]"

I'll generate the SQL files you need! 🚀

