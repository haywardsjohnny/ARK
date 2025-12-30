#!/bin/bash
# Database Backup Script for Supabase
# This script creates a backup of your Supabase database

BACKUP_DIR="../sportsdug_backups_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "Creating database backup..."
echo ""
echo "Option 1: Using Supabase Dashboard (Recommended)"
echo "1. Go to https://supabase.com/dashboard"
echo "2. Select your project: bcrglducvsimtghrgrpv"
echo "3. Go to Settings > Database"
echo "4. Scroll down to 'Connection string' section"
echo "5. Copy the connection string (use 'Connection pooling' mode)"
echo "6. Use pg_dump command:"
echo ""
echo "   pg_dump 'YOUR_CONNECTION_STRING' > $BACKUP_DIR/db_backup_$(date +%Y%m%d_%H%M%S).sql"
echo ""
echo "Option 2: Using Supabase CLI (requires Docker)"
echo "   supabase db dump -f $BACKUP_DIR/db_backup_$(date +%Y%m%d_%H%M%S).sql"
echo ""
echo "Option 3: Manual export via Supabase Dashboard"
echo "1. Go to Database > Tables"
echo "2. Use the SQL Editor to export data"
echo ""
echo "Backup directory: $BACKUP_DIR"
echo ""
echo "To restore database later:"
echo "   psql 'YOUR_CONNECTION_STRING' < $BACKUP_DIR/db_backup_*.sql"

