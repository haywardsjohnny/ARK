-- Add chat features to games
-- Allows admins to enable chat and control who can message

-- Add chat fields to instant_match_requests
ALTER TABLE instant_match_requests
ADD COLUMN IF NOT EXISTS chat_enabled BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS chat_mode TEXT DEFAULT 'all_users' CHECK (chat_mode IN ('all_users', 'admins_only'));

-- Add comment for documentation
COMMENT ON COLUMN instant_match_requests.chat_enabled IS 'Whether chat is enabled for this game';
COMMENT ON COLUMN instant_match_requests.chat_mode IS 'Who can send messages: all_users or admins_only';

-- Create game_messages table
CREATE TABLE IF NOT EXISTS game_messages (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  request_id UUID NOT NULL REFERENCES instant_match_requests(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_game_messages_request_id ON game_messages(request_id);
CREATE INDEX IF NOT EXISTS idx_game_messages_created_at ON game_messages(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_game_messages_user_id ON game_messages(user_id);

-- Enable Row Level Security
ALTER TABLE game_messages ENABLE ROW LEVEL SECURITY;

-- Policy: Users can read messages if they are part of the game (have attendance record)
CREATE POLICY "Players can read game messages"
  ON game_messages FOR SELECT
  USING (
    request_id IN (
      SELECT request_id 
      FROM team_match_attendance 
      WHERE user_id = auth.uid()
    )
  );

-- Policy: Users can insert messages if:
-- 1. Chat is enabled for the game
-- 2. User is part of the game (has attendance record)
-- 3. If chat_mode is 'admins_only', user must be an admin of one of the teams
CREATE POLICY "Players can send game messages"
  ON game_messages FOR INSERT
  WITH CHECK (
    -- Chat must be enabled
    EXISTS (
      SELECT 1 FROM instant_match_requests
      WHERE id = request_id
        AND chat_enabled = true
    )
    -- User must be part of the game
    AND EXISTS (
      SELECT 1 FROM team_match_attendance
      WHERE request_id = game_messages.request_id
        AND user_id = auth.uid()
    )
    -- If admins_only mode, user must be admin
    AND (
      -- Either chat_mode is all_users
      EXISTS (
        SELECT 1 FROM instant_match_requests
        WHERE id = request_id
          AND chat_mode = 'all_users'
      )
      -- Or user is admin of one of the teams
      OR EXISTS (
        SELECT 1 FROM instant_match_requests imr
        INNER JOIN team_match_attendance tma ON tma.request_id = imr.id
        INNER JOIN team_members tm ON tm.team_id = tma.team_id AND tm.user_id = auth.uid()
        WHERE imr.id = request_id
          AND tm.role = 'admin'
          AND imr.chat_mode = 'admins_only'
      )
    )
  );

-- Policy: Users can update their own messages
CREATE POLICY "Users can update own messages"
  ON game_messages FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Policy: Users can delete their own messages
CREATE POLICY "Users can delete own messages"
  ON game_messages FOR DELETE
  USING (user_id = auth.uid());

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_game_messages_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-update updated_at
CREATE TRIGGER update_game_messages_updated_at
  BEFORE UPDATE ON game_messages
  FOR EACH ROW
  EXECUTE FUNCTION update_game_messages_updated_at();

