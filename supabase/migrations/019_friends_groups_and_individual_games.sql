-- Friends Groups and Individual Games Enhancement
-- This migration adds friends groups, updates individual game visibility, and adds pending availability

-- ============================================
-- FRIENDS GROUPS
-- ============================================
CREATE TABLE IF NOT EXISTS friends_groups (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  created_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Friends Group Members
CREATE TABLE IF NOT EXISTS friends_group_members (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  group_id UUID NOT NULL REFERENCES friends_groups(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  added_by UUID REFERENCES users(id) ON DELETE SET NULL,
  added_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(group_id, user_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_friends_groups_created_by ON friends_groups(created_by);
CREATE INDEX IF NOT EXISTS idx_friends_group_members_group_id ON friends_group_members(group_id);
CREATE INDEX IF NOT EXISTS idx_friends_group_members_user_id ON friends_group_members(user_id);

-- RLS for friends_groups
ALTER TABLE friends_groups ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view groups they belong to"
  ON friends_groups FOR SELECT
  USING (
    created_by = auth.uid()
    OR id IN (
      SELECT group_id FROM friends_group_members WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Users can create groups"
  ON friends_groups FOR INSERT
  WITH CHECK (created_by = auth.uid());

CREATE POLICY "Group creators can update their groups"
  ON friends_groups FOR UPDATE
  USING (created_by = auth.uid())
  WITH CHECK (created_by = auth.uid());

CREATE POLICY "Group creators can delete their groups"
  ON friends_groups FOR DELETE
  USING (created_by = auth.uid());

-- RLS for friends_group_members
ALTER TABLE friends_group_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view members of their groups"
  ON friends_group_members FOR SELECT
  USING (
    group_id IN (
      SELECT id FROM friends_groups 
      WHERE created_by = auth.uid()
      OR id IN (
        SELECT group_id FROM friends_group_members WHERE user_id = auth.uid()
      )
    )
  );

CREATE POLICY "Group creators can add members"
  ON friends_group_members FOR INSERT
  WITH CHECK (
    group_id IN (
      SELECT id FROM friends_groups WHERE created_by = auth.uid()
    )
  );

CREATE POLICY "Users can leave groups"
  ON friends_group_members FOR DELETE
  USING (user_id = auth.uid());

-- ============================================
-- INDIVIDUAL GAME VISIBILITY AND ATTENDANCE
-- ============================================

-- Add visibility field to instant_match_requests (if not exists from previous migrations)
-- Update visibility to support: 'all_friends', 'friends_group', 'public'
ALTER TABLE instant_match_requests
ADD COLUMN IF NOT EXISTS friends_group_id UUID REFERENCES friends_groups(id) ON DELETE SET NULL;

-- Create individual_game_attendance table for tracking individual game participants
CREATE TABLE IF NOT EXISTS individual_game_attendance (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  request_id UUID NOT NULL REFERENCES instant_match_requests(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'declined')),
  invited_by UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(request_id, user_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_individual_game_attendance_request_id ON individual_game_attendance(request_id);
CREATE INDEX IF NOT EXISTS idx_individual_game_attendance_user_id ON individual_game_attendance(user_id);
CREATE INDEX IF NOT EXISTS idx_individual_game_attendance_status ON individual_game_attendance(status);

-- RLS for individual_game_attendance
ALTER TABLE individual_game_attendance ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view attendance for games they're part of"
  ON individual_game_attendance FOR SELECT
  USING (
    user_id = auth.uid()
    OR request_id IN (
      SELECT id FROM instant_match_requests WHERE created_by = auth.uid()
    )
    OR request_id IN (
      SELECT request_id FROM individual_game_attendance WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Organizers can insert attendance records"
  ON individual_game_attendance FOR INSERT
  WITH CHECK (
    request_id IN (
      SELECT id FROM instant_match_requests WHERE created_by = auth.uid()
    )
  );

CREATE POLICY "Users can update their own attendance"
  ON individual_game_attendance FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can delete their own attendance"
  ON individual_game_attendance FOR DELETE
  USING (user_id = auth.uid());

-- ============================================
-- AUTO-FRIENDING FOR INDIVIDUAL GAMES
-- ============================================

-- Function to auto-create friendships when users join the same individual game
CREATE OR REPLACE FUNCTION auto_friend_individual_game_participants()
RETURNS TRIGGER AS $$
DECLARE
  game_creator UUID;
  other_participants UUID[];
BEGIN
  -- Only process when status changes to 'accepted'
  IF NEW.status != 'accepted' OR OLD.status = 'accepted' THEN
    RETURN NEW;
  END IF;

  -- Get game creator
  SELECT created_by INTO game_creator
  FROM instant_match_requests
  WHERE id = NEW.request_id;

  -- Get all other accepted participants
  SELECT ARRAY_AGG(user_id) INTO other_participants
  FROM individual_game_attendance
  WHERE request_id = NEW.request_id
    AND user_id != NEW.user_id
    AND status = 'accepted';

  -- Auto-friend with game creator
  IF game_creator IS NOT NULL AND game_creator != NEW.user_id THEN
    INSERT INTO friends (user_id, friend_id, status)
    VALUES (NEW.user_id, game_creator, 'accepted')
    ON CONFLICT (user_id, friend_id) DO NOTHING;
    
    INSERT INTO friends (user_id, friend_id, status)
    VALUES (game_creator, NEW.user_id, 'accepted')
    ON CONFLICT (user_id, friend_id) DO NOTHING;
  END IF;

  -- Auto-friend with other participants
  IF other_participants IS NOT NULL THEN
    FOREACH game_creator IN ARRAY other_participants
    LOOP
      INSERT INTO friends (user_id, friend_id, status)
      VALUES (NEW.user_id, game_creator, 'accepted')
      ON CONFLICT (user_id, friend_id) DO NOTHING;
      
      INSERT INTO friends (user_id, friend_id, status)
      VALUES (game_creator, NEW.user_id, 'accepted')
      ON CONFLICT (user_id, friend_id) DO NOTHING;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-friend when user accepts individual game
DROP TRIGGER IF EXISTS trigger_auto_friend_individual_game ON individual_game_attendance;
CREATE TRIGGER trigger_auto_friend_individual_game
  AFTER UPDATE OF status ON individual_game_attendance
  FOR EACH ROW
  WHEN (NEW.status = 'accepted' AND OLD.status != 'accepted')
  EXECUTE FUNCTION auto_friend_individual_game_participants();

