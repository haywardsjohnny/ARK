import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/user_profile_screen.dart';
import '../screens/team_profile_screen.dart';

/// Opens a bottom sheet that lets you search players & teams
/// by name / ZIP / email / phone (free-text).
Future<void> showGlobalSearchSheet(BuildContext context) async {
  final supa = Supabase.instance.client;
  final searchCtrl = TextEditingController();

  bool searching = false;
  List<Map<String, dynamic>> playerResults = [];
  List<Map<String, dynamic>> teamResults = [];

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> doSearch() async {
            final term = searchCtrl.text.trim();
            if (term.isEmpty) return;

            setSheetState(() {
              searching = true;
            });

            try {
              // ---------- PLAYERS ----------
              final userRows = await supa
                  .from('users')
                  .select(
                      'id, full_name, photo_url, base_zip_code, email, phone')
                  .or(
                    [
                      "full_name.ilike.%$term%",
                      "base_zip_code.eq.$term",
                      "email.ilike.%$term%",
                      "phone.ilike.%$term%",
                    ].join(','),
                  );

              playerResults = (userRows as List)
                  .map<Map<String, dynamic>>((u) => {
                        'id': u['id'] as String,
                        'full_name': u['full_name'] as String? ?? 'Unknown',
                        'photo_url': u['photo_url'] as String?,
                        'zip': u['base_zip_code'] as String?,
                        'email': u['email'] as String?,
                        'phone': u['phone'] as String?,
                      })
                  .toList();

              // ---------- TEAMS ----------
              final teamRows = await supa
                  .from('teams')
                  .select('id, name, sport, zip_code, proficiency_level')
                  .or(
                    [
                      "name.ilike.%$term%",
                      "zip_code.eq.$term",
                    ].join(','),
                  );

              teamResults = (teamRows as List)
                  .map<Map<String, dynamic>>((t) => {
                        'id': t['id'] as String,
                        'name': t['name'] as String? ?? '',
                        'sport': t['sport'] as String? ?? '',
                        'zip': t['zip_code'] as String?,
                        'level': t['proficiency_level'] as String?,
                      })
                  .toList();
            } catch (e) {
              if (Navigator.of(ctx).canPop()) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Search failed: $e')),
                );
              }
            } finally {
              setSheetState(() {
                searching = false;
              });
            }
          }

          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: bottomInset + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Search players / teams',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: searchCtrl,
                  decoration: const InputDecoration(
                    labelText:
                        'Search a player/team by name or ZIP or email id or phone number',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (_) => doSearch(),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: searching ? null : doSearch,
                    child: Text(searching ? 'Searching…' : 'Search'),
                  ),
                ),
                const SizedBox(height: 12),
                if (!searching &&
                    playerResults.isEmpty &&
                    teamResults.isEmpty)
                  const Text(
                    'Type a keyword above and tap Search.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  )
                else
                  Expanded(
                    child: searching
                        ? const Center(child: CircularProgressIndicator())
                        : ListView(
                            children: [
                              // ---- PLAYERS ----
                              if (playerResults.isNotEmpty)
                                const Text(
                                  'Players',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ...playerResults.map((p) {
                                final name =
                                    p['full_name'] as String? ?? 'Unknown';
                                final photoUrl = p['photo_url'] as String?;
                                final zip = p['zip'] as String?;
                                final email = p['email'] as String?;
                                final phone = p['phone'] as String?;
                                final userId = p['id'] as String;

                                String subtitle = '';
                                if (zip != null) subtitle += 'ZIP: $zip';
                                if (email != null) {
                                  if (subtitle.isNotEmpty) subtitle += ' • ';
                                  subtitle += email;
                                }
                                if (phone != null) {
                                  if (subtitle.isNotEmpty) subtitle += ' • ';
                                  subtitle += phone;
                                }

                                return Card(
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundImage: (photoUrl != null &&
                                              photoUrl.isNotEmpty)
                                          ? NetworkImage(photoUrl)
                                          : null,
                                      child: (photoUrl == null ||
                                              photoUrl.isEmpty)
                                          ? Text(
                                              name.isNotEmpty
                                                  ? name[0].toUpperCase()
                                                  : '?',
                                            )
                                          : null,
                                    ),
                                    title: Text(name),
                                    subtitle: subtitle.isNotEmpty
                                        ? Text(subtitle)
                                        : null,
                                    onTap: () {
                                      Navigator.of(ctx).pop();
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => UserProfileScreen(
                                            userId: userId,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              }),

                              const SizedBox(height: 8),

                              // ---- TEAMS ----
                              if (teamResults.isNotEmpty)
                                const Text(
                                  'Teams',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ...teamResults.map((t) {
                                final name =
                                    t['name'] as String? ?? 'Unnamed team';
                                final sport = t['sport'] as String? ?? '';
                                final zip = t['zip'] as String?;
                                final level = t['level'] as String?;
                                final teamId = t['id'] as String;

                                String subtitle = sport;
                                if (level != null && level.isNotEmpty) {
                                  if (subtitle.isNotEmpty) subtitle += ' • ';
                                  subtitle += level;
                                }
                                if (zip != null) {
                                  if (subtitle.isNotEmpty) subtitle += ' • ';
                                  subtitle += 'ZIP $zip';
                                }

                                return Card(
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      child: Text(
                                        name.isNotEmpty
                                            ? name[0].toUpperCase()
                                            : '?',
                                      ),
                                    ),
                                    title: Text(name),
                                    subtitle: subtitle.isNotEmpty
                                        ? Text(subtitle)
                                        : null,
                                    onTap: () {
                                      Navigator.of(ctx).pop();
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => TeamProfileScreen(
                                            teamId: teamId,
                                            teamName: name,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              }),
                            ],
                          ),
                  ),
              ],
            ),
          );
        },
      );
    },
  );
}
