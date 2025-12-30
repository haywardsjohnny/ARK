# Backup Information

## Code Backup
✅ **Code backup created successfully**

**Location:** `../sportsdug_backups_[timestamp]/code_backup_[timestamp].tar.gz`

**Contents:**
- All source code files
- Migration files
- Configuration files
- Documentation files

**Excluded:**
- `node_modules/`
- `.dart_tool/`
- `build/`
- `.flutter-plugins`
- `.flutter-plugins-dependencies`
- `.packages`
- `pubspec.lock`

## Database Backup

⚠️ **Database backup requires manual action**

The Supabase CLI requires Docker to create database backups. You have three options:

### Option 1: Using Supabase Dashboard (Easiest)
1. Go to https://supabase.com/dashboard
2. Select your project: **bcrglducvsimtghrgrpv**
3. Navigate to **Settings > Database**
4. Scroll to **Connection string** section
5. Copy the connection string (use "Connection pooling" mode)
6. Run:
   ```bash
   pg_dump 'YOUR_CONNECTION_STRING' > backup.sql
   ```

### Option 2: Using Supabase Dashboard SQL Editor
1. Go to https://supabase.com/dashboard
2. Select your project
3. Navigate to **SQL Editor**
4. Run queries to export data from each table
5. Save the SQL scripts

### Option 3: Using Supabase CLI (requires Docker Desktop)
1. Install Docker Desktop: https://docs.docker.com/desktop
2. Start Docker Desktop
3. Run:
   ```bash
   supabase db dump -f db_backup.sql
   ```

## Git Backup
✅ **Git commit created**

**Commit:** `Backup: Fix user display names - RPC function type casting and RLS bypass`

**To push to remote:**
```bash
git push origin main
```

**To create a tag for this backup:**
```bash
git tag -a backup-$(date +%Y%m%d-%H%M%S) -m "Backup: User display names fix"
git push origin --tags
```

## Restore Instructions

### Restore Code:
```bash
tar -xzf code_backup_[timestamp].tar.gz -C /path/to/restore
```

### Restore Database:
```bash
psql 'YOUR_CONNECTION_STRING' < db_backup.sql
```

## Current State Summary

**Recent Changes:**
- Fixed user display names issue (RLS bypass using RPC function)
- Fixed function overloading issue for `get_confirmed_matches_for_user`
- Added migrations for user name display with email fallback
- Fixed type casting issues in RPC functions

**Migration Files:**
- 043_fix_get_confirmed_matches_overload.sql
- 044_create_user_on_signup.sql
- 045_fix_user_names_rpc.sql
- 046_create_user_display_view.sql
- 047_fix_user_display_names_type.sql

