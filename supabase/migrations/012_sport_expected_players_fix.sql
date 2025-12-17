-- Fix script: Drop trigger if it exists, then run the main migration
-- Run this if you get "trigger already exists" error

DROP TRIGGER IF EXISTS update_sport_expected_players_updated_at ON sport_expected_players;

-- Now you can safely run the main migration file (012_sport_expected_players.sql)

