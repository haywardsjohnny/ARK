-- Migration: Ensure all teams have at least one admin
-- 1. One-time fix: Assign admin role to first member of teams with no admins
-- 2. Add trigger to prevent removing the last admin
-- 3. Add trigger to ensure creator gets admin role when team is created

-- ============================================
-- ONE-TIME FIX: Assign admin to teams with no admins
-- ============================================
-- Temporarily disable ALL UPDATE triggers on team_members to allow the fix
DO $$
DECLARE
    team_record RECORD;
    first_member_id UUID;
    trigger_rec RECORD;
    disabled_triggers TEXT[] := ARRAY[]::TEXT[];
    i INTEGER;
BEGIN
    -- Disable ALL UPDATE triggers on team_members
    FOR trigger_rec IN
        SELECT trigger_name
        FROM information_schema.triggers
        WHERE event_object_table = 'team_members'
          AND event_manipulation = 'UPDATE'
    LOOP
        EXECUTE format('ALTER TABLE team_members DISABLE TRIGGER %I', trigger_rec.trigger_name);
        disabled_triggers := array_append(disabled_triggers, trigger_rec.trigger_name);
        RAISE NOTICE 'Temporarily disabled trigger: %', trigger_rec.trigger_name;
    END LOOP;
    
    -- Find all teams that have no admins
    FOR team_record IN
        SELECT t.id, t.name
        FROM teams t
        WHERE NOT EXISTS (
            SELECT 1
            FROM team_members tm
            WHERE tm.team_id = t.id
              AND LOWER(tm.role) IN ('admin', 'captain')
        )
    LOOP
        -- Get the first member (by id, which represents insertion order)
        SELECT tm.user_id INTO first_member_id
        FROM team_members tm
        WHERE tm.team_id = team_record.id
        ORDER BY tm.id ASC
        LIMIT 1;
        
        -- If team has members, assign first one as admin
        IF first_member_id IS NOT NULL THEN
            UPDATE team_members
            SET role = 'admin'
            WHERE team_id = team_record.id
              AND user_id = first_member_id;
            
            RAISE NOTICE 'Assigned admin role to user % for team % (%)', 
                first_member_id, team_record.id, team_record.name;
        ELSE
            -- Team has no members - this is a data integrity issue
            -- We'll log it but can't fix it automatically
            RAISE WARNING 'Team % (%) has no members and no admin - cannot auto-fix', 
                team_record.id, team_record.name;
        END IF;
    END LOOP;
    
    -- Re-enable all triggers we disabled
    FOR i IN 1..array_length(disabled_triggers, 1)
    LOOP
        EXECUTE format('ALTER TABLE team_members ENABLE TRIGGER %I', disabled_triggers[i]);
        RAISE NOTICE 'Re-enabled trigger: %', disabled_triggers[i];
    END LOOP;
END $$;

-- ============================================
-- TRIGGER FUNCTION: Ensure creator gets admin role
-- ============================================
CREATE OR REPLACE FUNCTION ensure_creator_is_admin()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    creator_id UUID;
BEGIN
    -- Get the creator_id from the teams table
    SELECT created_by INTO creator_id
    FROM teams
    WHERE id = NEW.team_id;
    
    -- If creator exists and this is the creator being added, ensure they're admin
    IF creator_id IS NOT NULL AND NEW.user_id = creator_id THEN
        -- Only set to admin if not already admin/captain
        IF LOWER(NEW.role) NOT IN ('admin', 'captain') THEN
            NEW.role := 'admin';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;

-- Create trigger to ensure creator gets admin role when added as member
DROP TRIGGER IF EXISTS ensure_creator_is_admin_trigger ON team_members;
CREATE TRIGGER ensure_creator_is_admin_trigger
    BEFORE INSERT ON team_members
    FOR EACH ROW
    EXECUTE FUNCTION ensure_creator_is_admin();

-- ============================================
-- TRIGGER FUNCTION: Prevent removing last admin
-- ============================================
CREATE OR REPLACE FUNCTION prevent_remove_last_admin()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    admin_count INTEGER;
    is_removing_admin BOOLEAN;
BEGIN
    -- Check if we're removing an admin
    is_removing_admin := (LOWER(OLD.role) IN ('admin', 'captain'));
    
    IF is_removing_admin THEN
        -- Count remaining admins after this deletion
        SELECT COUNT(*) INTO admin_count
        FROM team_members
        WHERE team_id = OLD.team_id
          AND user_id != OLD.user_id  -- Exclude the one being removed
          AND LOWER(role) IN ('admin', 'captain');
        
        -- If no admins will remain, prevent the deletion
        IF admin_count = 0 THEN
            RAISE EXCEPTION 'Cannot remove the last admin from a team. Please assign another admin first.';
        END IF;
    END IF;
    
    RETURN OLD;
END;
$$;

-- Create trigger to prevent removing last admin
DROP TRIGGER IF EXISTS prevent_remove_last_admin_trigger ON team_members;
CREATE TRIGGER prevent_remove_last_admin_trigger
    BEFORE DELETE ON team_members
    FOR EACH ROW
    EXECUTE FUNCTION prevent_remove_last_admin();

-- ============================================
-- TRIGGER FUNCTION: Prevent demoting last admin
-- ============================================
CREATE OR REPLACE FUNCTION prevent_demote_last_admin()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    admin_count INTEGER;
    was_admin BOOLEAN;
    is_admin BOOLEAN;
BEGIN
    -- Check if we're demoting an admin (changing from admin to non-admin)
    was_admin := (LOWER(OLD.role) IN ('admin', 'captain'));
    is_admin := (LOWER(NEW.role) IN ('admin', 'captain'));
    
    IF was_admin AND NOT is_admin THEN
        -- Count remaining admins after this update
        SELECT COUNT(*) INTO admin_count
        FROM team_members
        WHERE team_id = NEW.team_id
          AND user_id != NEW.user_id  -- Exclude the one being demoted
          AND LOWER(role) IN ('admin', 'captain');
        
        -- If no admins will remain, prevent the demotion
        IF admin_count = 0 THEN
            RAISE EXCEPTION 'Cannot demote the last admin from a team. Please assign another admin first.';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;

-- Create trigger to prevent demoting last admin
DROP TRIGGER IF EXISTS prevent_demote_last_admin_trigger ON team_members;
CREATE TRIGGER prevent_demote_last_admin_trigger
    BEFORE UPDATE ON team_members
    FOR EACH ROW
    WHEN (OLD.role IS DISTINCT FROM NEW.role)
    EXECUTE FUNCTION prevent_demote_last_admin();

-- ============================================
-- COMMENTS
-- ============================================
COMMENT ON FUNCTION ensure_creator_is_admin() IS
'Ensures that when a team creator is added as a member, they automatically get admin role.';

COMMENT ON FUNCTION prevent_remove_last_admin() IS
'Prevents deletion of the last admin from a team. Ensures teams always have at least one admin.';

COMMENT ON FUNCTION prevent_demote_last_admin() IS
'Prevents demoting the last admin from a team. Ensures teams always have at least one admin.';

