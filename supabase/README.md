# Supabase Database Migrations

This directory contains SQL migration files for the SPORTSDUG database schema.

## 📁 Migration Files

- `001_initial_schema.sql` - Creates all tables, indexes, and triggers
- `002_rpc_functions.sql` - Creates RPC functions for business logic
- `003_row_level_security.sql` - Sets up Row Level Security (RLS) policies
- `004_fixes_and_optimizations.sql` - Fixes and performance optimizations

## 🚀 How to Apply Migrations

### Option 1: Using Supabase Dashboard (Recommended for First Time)

1. Go to your Supabase project dashboard
2. Navigate to **SQL Editor**
3. Copy and paste each migration file content in order
4. Run each migration one at a time

### Option 2: Using Supabase CLI

```bash
# Install Supabase CLI if you haven't
npm install -g supabase

# Link to your project
supabase link --project-ref your-project-ref

# Apply all migrations
supabase db push
```

### Option 3: Using psql

```bash
# Connect to your Supabase database
psql "postgresql://postgres:[YOUR-PASSWORD]@db.[YOUR-PROJECT-REF].supabase.co:5432/postgres"

# Run migrations in order
\i supabase/migrations/001_initial_schema.sql
\i supabase/migrations/002_rpc_functions.sql
\i supabase/migrations/003_row_level_security.sql
\i supabase/migrations/004_fixes_and_optimizations.sql
```

## ⚠️ Important Notes

1. **Run migrations in order** - They are numbered and should be executed sequentially
2. **Backup first** - Always backup your database before running migrations in production
3. **Test in development** - Test all migrations in a development environment first
4. **RLS Policies** - The RLS policies are permissive by default. Review and adjust based on your security requirements

## 🔍 Verifying Migrations

After running migrations, verify:

```sql
-- Check tables exist
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
ORDER BY table_name;

-- Check RPC functions
SELECT routine_name 
FROM information_schema.routines 
WHERE routine_schema = 'public' 
AND routine_type = 'FUNCTION';

-- Check RLS is enabled
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public';
```

## 📝 Creating New Migrations

When you need to make schema changes:

1. Create a new file: `005_your_migration_name.sql`
2. Use descriptive names and comments
3. Make migrations idempotent (use `IF NOT EXISTS`, `IF EXISTS`, etc.)
4. Test thoroughly before applying to production

## 🔐 Security Checklist

- [ ] RLS policies are enabled on all tables
- [ ] Service role key is kept secret
- [ ] Anon key is safe to expose (but still protect it)
- [ ] RPC functions use `SECURITY DEFINER` appropriately
- [ ] Indexes are created for performance
- [ ] Foreign key constraints are in place

## 🆘 Troubleshooting

**Migration fails:**
- Check if previous migrations were applied
- Verify you have the correct permissions
- Check for syntax errors in SQL

**RLS blocking queries:**
- Review RLS policies
- Check if user is authenticated
- Verify user has correct permissions

**Performance issues:**
- Check if indexes are created
- Review query execution plans
- Consider adding composite indexes

## 📚 Additional Resources

- [Supabase Documentation](https://supabase.com/docs)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)
- [Row Level Security Guide](https://supabase.com/docs/guides/auth/row-level-security)

