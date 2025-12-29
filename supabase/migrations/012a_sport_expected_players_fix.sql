-- Fix script: Drop trigger if it exists, then run the main migration
-- Run this if you get "trigger already exists" error
-- NOTE: This is now redundant as 012_sport_expected_players.sql already handles the trigger drop
-- This file is kept for migration history but does nothing

-- No-op migration: The main migration (012_sport_expected_players.sql) already includes:
-- DROP TRIGGER IF EXISTS update_sport_expected_players_updated_at ON sport_expected_players;
-- This file exists only to maintain migration history and does not perform any operations.

