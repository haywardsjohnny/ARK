#!/bin/bash
# Script to apply Supabase migrations
# Usage: ./apply_migrations.sh [project-ref] [db-password]

set -e

PROJECT_REF=${1:-""}
DB_PASSWORD=${2:-""}

if [ -z "$PROJECT_REF" ] || [ -z "$DB_PASSWORD" ]; then
    echo "Usage: ./apply_migrations.sh <project-ref> <db-password>"
    echo ""
    echo "Example:"
    echo "  ./apply_migrations.sh abcdefghijklmnop supabase_password"
    exit 1
fi

DB_URL="postgresql://postgres:${DB_PASSWORD}@db.${PROJECT_REF}.supabase.co:5432/postgres"

echo "🚀 Applying migrations to project: $PROJECT_REF"
echo ""

# Apply migrations in order
for migration in supabase/migrations/*.sql; do
    if [ -f "$migration" ]; then
        echo "📄 Applying $(basename $migration)..."
        psql "$DB_URL" -f "$migration"
        echo "✅ $(basename $migration) applied successfully"
        echo ""
    fi
done

echo "🎉 All migrations applied successfully!"

