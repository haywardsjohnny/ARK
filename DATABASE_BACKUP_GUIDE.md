# Database Backup Guide for Supabase

## Method 1: Using Supabase Dashboard SQL Editor (Easiest - No Connection String Needed)

### Step-by-Step Instructions:

1. **Go to SQL Editor**
   - In Supabase Dashboard, click on **"SQL Editor"** in the left sidebar
   - Or go directly to: `https://supabase.com/dashboard/project/bcrglducvsimtghrgrpv/sql`

2. **Create Backup Script**
   - Click **"New query"**
   - Copy and paste this SQL script to export all your data:

```sql
-- Export all tables data
\copy (SELECT * FROM users) TO 'users_backup.csv' CSV HEADER;
\copy (SELECT * FROM teams) TO 'teams_backup.csv' CSV HEADER;
\copy (SELECT * FROM team_members) TO 'team_members_backup.csv' CSV HEADER;
\copy (SELECT * FROM instant_match_requests) TO 'instant_match_requests_backup.csv' CSV HEADER;
\copy (SELECT * FROM team_match_attendance) TO 'team_match_attendance_backup.csv' CSV HEADER;
\copy (SELECT * FROM instant_request_invites) TO 'instant_request_invites_backup.csv' CSV HEADER;
\copy (SELECT * FROM friends) TO 'friends_backup.csv' CSV HEADER;
\copy (SELECT * FROM friends_groups) TO 'friends_groups_backup.csv' CSV HEADER;
\copy (SELECT * FROM friends_group_members) TO 'friends_group_members_backup.csv' CSV HEADER;
\copy (SELECT * FROM individual_game_attendance) TO 'individual_game_attendance_backup.csv' CSV HEADER;
\copy (SELECT * FROM game_messages) TO 'game_messages_backup.csv' CSV HEADER;
\copy (SELECT * FROM team_join_requests) TO 'team_join_requests_backup.csv' CSV HEADER;
\copy (SELECT * FROM team_admin_requests) TO 'team_admin_requests_backup.csv' CSV HEADER;
\copy (SELECT * FROM user_sports) TO 'user_sports_backup.csv' CSV HEADER;
\copy (SELECT * FROM user_hidden_games) TO 'user_hidden_games_backup.csv' CSV HEADER;
\copy (SELECT * FROM sport_expected_players) TO 'sport_expected_players_backup.csv' CSV HEADER;
```

**Note:** The SQL Editor might not support `\copy` directly. Use the alternative method below instead.

## Method 2: Export via Supabase Dashboard (Recommended)

### Export Schema (Structure):
1. Go to **Database** → **Migrations** in the left sidebar
2. Click on **"Download migrations"** or view the latest migration
3. All your migration files are already in your codebase at `supabase/migrations/`

### Export Data (Content):
1. Go to **Database** → **Tables**
2. Click on each table you want to backup
3. Click the **"..."** (three dots) menu → **"Export"** or **"Download CSV"**
4. Repeat for all important tables:
   - `users`
   - `teams`
   - `team_members`
   - `instant_match_requests`
   - `team_match_attendance`
   - `friends`
   - `friends_groups`
   - `friends_group_members`
   - `individual_game_attendance`
   - `game_messages`
   - `team_join_requests`
   - `team_admin_requests`
   - `user_sports`
   - `user_hidden_games`
   - `sport_expected_players`

## Method 3: Find Connection String (If Needed)

### Steps to Find Connection String:
1. In Supabase Dashboard, click on **"Settings"** (gear icon) in the left sidebar
2. Click on **"Database"** under Settings
3. Scroll down to find **"Connection string"** section
4. You'll see different connection string formats:
   - **URI** (full connection string)
   - **JDBC** (Java)
   - **Golang**
   - **Node.js**
   - **Python**
   - **Connection pooling**

5. **For pg_dump**, use the **"URI"** format or **"Connection pooling"** mode
6. Copy the connection string (it will look like):
   ```
   postgresql://postgres:[YOUR-PASSWORD]@db.bcrglducvsimtghrgrpv.supabase.co:5432/postgres
   ```

### Using Connection String for Backup:
```bash
# Replace [YOUR-PASSWORD] with your actual database password
pg_dump 'postgresql://postgres:[YOUR-PASSWORD]@db.bcrglducvsimtghrgrpv.supabase.co:5432/postgres' > db_backup.sql
```

## Method 4: Using Supabase CLI (Requires Docker)

If you have Docker Desktop installed and running:

```bash
cd /Users/saireddykasthuri/sportsdug_app
supabase db dump -f ../sportsdug_backups_20251229_041317/db_backup.sql
```

## Method 5: Quick SQL Export Script

Run this in Supabase SQL Editor to generate INSERT statements:

```sql
-- Export users table
SELECT 'INSERT INTO users (id, full_name, base_zip_code, bio, photo_url, created_at, updated_at) VALUES (' ||
       quote_literal(id::text) || ', ' ||
       quote_literal(full_name) || ', ' ||
       quote_literal(base_zip_code) || ', ' ||
       quote_literal(bio) || ', ' ||
       quote_literal(photo_url) || ', ' ||
       quote_literal(created_at) || ', ' ||
       quote_literal(updated_at) || ');'
FROM users;
```

Repeat for each table.

## Recommended Approach

**For your current situation, I recommend:**

1. **Schema Backup:** ✅ Already done - Your migration files in `supabase/migrations/` contain the complete schema
2. **Data Backup:** Use Method 2 (Export via Dashboard) for critical tables
3. **Full Backup:** Use Method 3 (Connection String + pg_dump) if you can find the connection string

## Quick Checklist

- [x] Code backup created
- [x] Git commit created
- [ ] Database schema backup (migrations already in codebase)
- [ ] Database data backup (use one of the methods above)

