// Debug utility for individual games
// This file can be used to test individual game creation and attendance record creation

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class IndividualGamesDebugger {
  static Future<void> debugGroupMembers(String groupId) async {
    final supa = Supabase.instance.client;
    final userId = supa.auth.currentUser?.id;
    
    if (userId == null) {
      if (kDebugMode) print('[DEBUG] No user logged in');
      return;
    }
    
    if (kDebugMode) {
      print('[DEBUG] Current user: $userId');
      print('[DEBUG] Checking group: $groupId');
    }
    
    try {
      // Check if user can see the group
      final group = await supa
          .from('friends_groups')
          .select('id, name, created_by, sport')
          .eq('id', groupId)
          .maybeSingle();
      
      if (kDebugMode) {
        print('[DEBUG] Group info: $group');
      }
      
      // Check group members
      final members = await supa
          .from('friends_group_members')
          .select('user_id, group_id')
          .eq('group_id', groupId);
      
      if (kDebugMode) {
        print('[DEBUG] Group members found: ${members is List ? members.length : 0}');
        if (members is List) {
          for (final member in members) {
            print('[DEBUG] Member: ${member['user_id']}');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('[DEBUG] Error checking group members: $e');
      }
    }
  }
  
  static Future<void> debugAttendanceRecords(String requestId) async {
    final supa = Supabase.instance.client;
    final userId = supa.auth.currentUser?.id;
    
    if (userId == null) {
      if (kDebugMode) print('[DEBUG] No user logged in');
      return;
    }
    
    if (kDebugMode) {
      print('[DEBUG] Checking attendance records for game: $requestId');
      print('[DEBUG] Current user: $userId');
    }
    
    try {
      // Check all attendance records for this game (as organizer)
      final allAttendance = await supa
          .from('individual_game_attendance')
          .select('id, request_id, user_id, status, created_at')
          .eq('request_id', requestId);
      
      if (kDebugMode) {
        print('[DEBUG] All attendance records: ${allAttendance is List ? allAttendance.length : 0}');
        if (allAttendance is List) {
          for (final record in allAttendance) {
            print('[DEBUG] Record: user=${record['user_id']}, status=${record['status']}');
          }
        }
      }
      
      // Check pending records for current user
      final myPending = await supa
          .from('individual_game_attendance')
          .select('id, request_id, user_id, status')
          .eq('request_id', requestId)
          .eq('user_id', userId)
          .eq('status', 'pending');
      
      if (kDebugMode) {
        print('[DEBUG] My pending records: ${myPending is List ? myPending.length : 0}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[DEBUG] Error checking attendance records: $e');
      }
    }
  }
}

