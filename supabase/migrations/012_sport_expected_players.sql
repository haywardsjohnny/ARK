-- Create a separate table for expected players per team by sport
-- This allows easy management and updates of expected player counts

-- First, ensure the update_updated_at_column function exists (it should from initial schema, but create if not)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TABLE IF NOT EXISTS sport_expected_players (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sport TEXT NOT NULL UNIQUE,
    game_type TEXT, -- Optional: can be 'team_vs_team', 'individual', etc.
    expected_players_per_team INTEGER NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add comment for documentation
COMMENT ON TABLE sport_expected_players IS 
'Lookup table for expected players per team by sport. Used to calculate availability percentages in match cards.';

-- Insert default values for all sports
INSERT INTO sport_expected_players (sport, expected_players_per_team) VALUES
    ('cricket', 11),
    ('soccer', 11),
    ('football', 11),
    ('basketball', 5),
    ('volleyball', 6),
    ('pickleball', 4),
    ('tennis', 4),
    ('table_tennis', 2),
    ('badminton', 4)
ON CONFLICT (sport) DO NOTHING;

-- Create index for fast lookups
CREATE INDEX IF NOT EXISTS idx_sport_expected_players_sport ON sport_expected_players(sport);

-- Create trigger for updated_at (drop first if exists to avoid errors on re-run)
DROP TRIGGER IF EXISTS update_sport_expected_players_updated_at ON sport_expected_players;
CREATE TRIGGER update_sport_expected_players_updated_at 
    BEFORE UPDATE ON sport_expected_players
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- Grant permissions
GRANT SELECT ON sport_expected_players TO authenticated;
GRANT INSERT, UPDATE, DELETE ON sport_expected_players TO authenticated;

