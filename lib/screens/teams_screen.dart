import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'team_profile_screen.dart';
import 'user_profile_screen.dart';

class TeamsScreen extends StatefulWidget {
  const TeamsScreen({super.key});

  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  bool _loading = false;
  List<Map<String, dynamic>> _myTeams = [];

  @override
  void initState() {
    super.initState();
    _loadMyTeams();
  }

  Future<void> _loadMyTeams() async {
    setState(() => _loading = true);

    final supa = Supabase.instance.client;
    final user = supa.auth.currentUser;
    if (user == null) {
      setState(() {
        _myTeams = [];
        _loading = false;
      });
      return;
    }

    try {
      final memberRows = await supa
          .from('team_members')
          .select('team_id, role')
          .eq('user_id', user.id);

      if (memberRows is! List || memberRows.isEmpty) {
        setState(() {
          _myTeams = [];
          _loading = false;
        });
        return;
      }

      final teamIds =
          memberRows.map<String>((m) => m['team_id'] as String).toList();

      final teamsRows = await supa
          .from('teams')
          .select('id, name, sport, proficiency_level, zip_code, team_number')
          .inFilter('id', teamIds);

      final Map<String, String> roleByTeamId = {};
      for (final m in memberRows) {
        roleByTeamId[m['team_id'] as String] = m['role'] as String? ?? 'member';
      }

      final myTeams = (teamsRows as List).map<Map<String, dynamic>>((t) {
        final id = t['id'] as String;
        return {
          'id': id,
          'name': t['name'] as String? ?? '',
          'sport': t['sport'] as String? ?? '',
          'proficiency_level': t['proficiency_level'] as String?,
          'zip_code': t['zip_code'] as String?,
          'team_number': t['team_number'],
          'role': roleByTeamId[id] ?? 'member',
        };
      }).toList();

      myTeams.sort((a, b) {
        int rank(String role) {
          final lower = role.toLowerCase();
          if (lower == 'admin') return 0;
          return 1;
        }

        final ra = rank((a['role'] as String?) ?? 'member');
        final rb = rank((b['role'] as String?) ?? 'member');
        if (ra != rb) return ra.compareTo(rb);
        return (a['name'] as String)
            .toLowerCase()
            .compareTo((b['name'] as String).toLowerCase());
      });

      setState(() {
        _myTeams = myTeams;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load teams: $e')),
      );
    }
  }

  String? _roleLabel(String role) {
    final lower = role.toLowerCase();
    if (lower == 'admin') {
      return 'Admin';
    }
    return null; // Don't show label for members
  }

  Color? _roleColor(String role) {
    final lower = role.toLowerCase();
    if (lower == 'admin') {
      return Colors.blue;
    }
    return null; // No color for members
  }

  Future<void> _exitTeam(String teamId, String teamName) async {
    final supa = Supabase.instance.client;
    final user = supa.auth.currentUser;
    if (user == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit Team'),
        content: Text('Do you want to exit "$teamName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final memberRows = await supa
          .from('team_members')
          .select('user_id, role')
          .eq('team_id', teamId);

      final admins = (memberRows as List)
          .where((m) {
            final r = (m['role'] as String?) ?? 'member';
            final lower = r.toLowerCase();
            return lower == 'admin';
          })
          .toList();

      final isAdmin = admins.any((m) => m['user_id'] == user.id);

      if (isAdmin && admins.length <= 1) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You are the only admin. Assign another admin before exiting.',
            ),
          ),
        );
        return;
      }

      await supa
          .from('team_members')
          .delete()
          .match({'team_id': teamId, 'user_id': user.id});

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exited team "$teamName"')),
      );
      await _loadMyTeams();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to exit team: $e')),
      );
    }
  }

  void _openTeamManagement(Map<String, dynamic> team) {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => TeamManagementScreen(
          teamId: team['id'] as String,
          teamName: team['name'] as String? ?? '',
        ),
      ),
    )
        .then((_) async {
      await _loadMyTeams();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Teams'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _myTeams.isEmpty
              ? const Center(
                  child: Text(
                    'You are not part of any team yet.',
                    textAlign: TextAlign.center,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadMyTeams,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _myTeams.length,
                    itemBuilder: (ctx, i) {
                      final t = _myTeams[i];
                      final role = (t['role'] as String?) ?? 'member';
                      final isAdmin = role.toLowerCase() == 'admin';

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          leading: CircleAvatar(
                            child: Text(
                              (t['name'] as String?)?.isNotEmpty == true
                                  ? (t['name'] as String)[0].toUpperCase()
                                  : '?',
                            ),
                          ),
                          title: Text(t['name'] as String? ?? ''),
                          subtitle: Text(
                            '${t['sport'] ?? ''} • '
                            '${t['proficiency_level'] ?? 'N/A'}',
                          ),
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => TeamProfileScreen(
                                  teamId: t['id'] as String,
                                  teamName: t['name'] as String? ?? '',
                                ),
                              ),
                            );
                          },
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              if (_roleLabel(role) != null)
                                Chip(
                                  label: Text(
                                    _roleLabel(role)!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                    ),
                                  ),
                                  backgroundColor: _roleColor(role),
                                ),
                              if (isAdmin)
                                IconButton(
                                  tooltip: 'Edit team & members',
                                  icon: const Icon(Icons.manage_accounts),
                                  onPressed: () => _openTeamManagement(t),
                                ),
                              IconButton(
                                tooltip: 'Exit team',
                                icon: const Icon(Icons.exit_to_app),
                                onPressed: () =>
                                    _exitTeam(t['id'] as String, t['name'] as String? ?? ''),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class TeamManagementScreen extends StatefulWidget {
  final String teamId;
  final String teamName;

  const TeamManagementScreen({
    super.key,
    required this.teamId,
    required this.teamName,
  });

  @override
  State<TeamManagementScreen> createState() => _TeamManagementScreenState();
}

class _TeamManagementScreenState extends State<TeamManagementScreen> {
  bool _loading = false;
  bool _saving = false;
  Map<String, dynamic>? _team;
  List<Map<String, dynamic>> _members = [];

  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _proficiency = 'Recreational';

  @override
  void initState() {
    super.initState();
    _loadTeam();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  /// Map any stored value into one of the allowed dropdown values.
  String _normalizeProficiency(String? raw) {
    if (raw == null) return 'Recreational';
    final lower = raw.trim().toLowerCase();
    if (lower == 'recreational') return 'Recreational';
    if (lower == 'intermediate') return 'Intermediate';
    if (lower == 'competitive' || lower == 'advanced') {
      // treat "advanced" as Competitive for now
      return 'Competitive';
    }
    return 'Recreational';
  }

  Future<void> _loadTeam() async {
    setState(() => _loading = true);

    final supa = Supabase.instance.client;

    try {
      final teamRow = await supa
          .from('teams')
          .select(
            'id, name, sport, description, proficiency_level, zip_code, team_number, created_by',
          )
          .eq('id', widget.teamId)
          .maybeSingle();

      if (teamRow == null) {
        setState(() {
          _team = null;
          _members = [];
          _loading = false;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Team not found')),
        );
        return;
      }

      final memberRows = await supa
          .from('team_members')
          .select('user_id, role')
          .eq('team_id', widget.teamId);

      final memberList =
          (memberRows as List).map<Map<String, dynamic>>((m) {
        return {
          'user_id': m['user_id'] as String,
          'role': m['role'] as String? ?? 'member',
        };
      }).toList();

      final userIds = memberList.map((m) => m['user_id'] as String).toList();

      Map<String, Map<String, dynamic>> userById = {};
      if (userIds.isNotEmpty) {
        final userRows = await supa
            .from('users')
            .select('id, full_name, photo_url, base_zip_code')
            .inFilter('id', userIds);

        for (final u in userRows as List) {
          userById[u['id'] as String] =
              Map<String, dynamic>.from(u as Map<String, dynamic>);
        }
      }

      final combinedMembers = <Map<String, dynamic>>[];
      for (final m in memberList) {
        final uid = m['user_id'] as String;
        final u = userById[uid] ?? {};
        combinedMembers.add({
          'user_id': uid,
          'role': m['role'],
          'full_name': u['full_name'] ?? 'Unknown',
          'photo_url': u['photo_url'],
          'base_zip_code': u['base_zip_code'],
        });
      }

      combinedMembers.sort((a, b) {
        int rank(String role) {
          final lower = role.toLowerCase();
          if (lower == 'admin') return 0;
          return 1;
        }

        final ra = rank((a['role'] as String?) ?? 'member');
        final rb = rank((b['role'] as String?) ?? 'member');
        if (ra != rb) return ra.compareTo(rb);
        return (a['full_name'] as String)
            .toLowerCase()
            .compareTo((b['full_name'] as String).toLowerCase());
      });

      _nameCtrl.text = teamRow['name'] as String? ?? '';
      _descCtrl.text = teamRow['description'] as String? ?? '';

      // normalize DB value into safe dropdown value
      _proficiency =
          _normalizeProficiency(teamRow['proficiency_level'] as String?);

      setState(() {
        _team = Map<String, dynamic>.from(teamRow);
        _members = combinedMembers;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load team: $e')),
      );
    }
  }

  Future<void> _saveTeam() async {
    if (_team == null) return;
    setState(() => _saving = true);

    final supa = Supabase.instance.client;
    try {
      await supa.from('teams').update({
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'proficiency_level': _proficiency,
      }).eq('id', widget.teamId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Team updated')),
      );
      setState(() => _saving = false);
    } catch (e) {
      setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save team: $e')),
      );
    }
  }

  Future<void> _changeRole(String userId, String newRole) async {
    final supa = Supabase.instance.client;

    try {
      final admins = _members.where((m) {
        final r = (m['role'] as String?) ?? 'member';
        final lower = r.toLowerCase();
        return lower == 'admin';
      }).toList();

      final isTargetAdmin = admins.any((m) => m['user_id'] == userId);

      if (isTargetAdmin &&
          newRole.toLowerCase() == 'member' &&
          admins.length <= 1) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('At least one admin must remain on the team.'),
          ),
        );
        return;
      }

      await supa
          .from('team_members')
          .update({'role': newRole})
          .match({'team_id': widget.teamId, 'user_id': userId});

      if (!mounted) return;
      setState(() {
        for (final m in _members) {
          if (m['user_id'] == userId) {
            m['role'] = newRole;
            break;
          }
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Role updated')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update role: $e')),
      );
    }
  }

  Future<void> _removeMember(String userId, String fullName) async {
    final supa = Supabase.instance.client;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Member'),
        content: Text('Remove $fullName from this team?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final admins = _members.where((m) {
        final r = (m['role'] as String?) ?? 'member';
        final lower = r.toLowerCase();
        return lower == 'admin';
      }).toList();

      final isTargetAdmin = admins.any((m) => m['user_id'] == userId);

      if (isTargetAdmin && admins.length <= 1) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You cannot remove the last admin from the team.'),
          ),
        );
        return;
      }

      await supa
          .from('team_members')
          .delete()
          .match({'team_id': widget.teamId, 'user_id': userId});

      if (!mounted) return;
      setState(() {
        _members.removeWhere((m) => m['user_id'] == userId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed $fullName from team')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove member: $e')),
      );
    }
  }

  Future<void> _addMember() async {
    final supa = Supabase.instance.client;
    final nameCtrl = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool searching = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> doSearch() async {
              final name = nameCtrl.text.trim();

              setSheetState(() => searching = true);
              try {
                var query = supa
                    .from('users')
                    .select('id, full_name, photo_url');

                if (name.isNotEmpty) {
                  query = query.ilike('full_name', '%$name%');
                }

                final rows = await query;
                results = (rows as List)
                    .map<Map<String, dynamic>>((u) => {
                          'id': u['id'] as String,
                          'full_name': u['full_name'] as String? ?? 'Unknown',
                          'photo_url': u['photo_url'] as String?,
                          'base_zip_code': u['base_zip_code'] as String?,
                        })
                    .toList();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Search failed: $e')),
                  );
                }
              } finally {
                setSheetState(() => searching = false);
              }
            }

            Future<void> addUserToTeam(String userId, String fullName) async {
              try {
                await supa.from('team_members').insert({
                  'team_id': widget.teamId,
                  'user_id': userId,
                  'role': 'member',
                });

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$fullName added to the team as Member'),
                    ),
                  );
                }

                setState(() {
                  _members.add({
                    'user_id': userId,
                    'role': 'member',
                    'full_name': fullName,
                    'photo_url': null,
                    'base_zip_code': null,
                  });
                });

                Navigator.of(ctx).pop();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to add member: $e')),
                  );
                }
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
                    'Add Member',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Search by name',
                      prefixIcon: Icon(Icons.person_search),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: searching ? null : doSearch,
                      icon: const Icon(Icons.search),
                      label: Text(searching ? 'Searching...' : 'Search'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (results.isEmpty && !searching)
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Search players by name to add to this team.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: 260,
                      child: searching
                          ? const Center(child: CircularProgressIndicator())
                          : ListView.builder(
                              itemCount: results.length,
                              itemBuilder: (ctx, idx) {
                                final r = results[idx];
                                final id = r['id'] as String;
                                final name =
                                    r['full_name'] as String? ?? 'Unknown';
                                final photoUrl = r['photo_url'] as String?;
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
                                    subtitle: null,
                                    trailing: IconButton(
                                      icon:
                                          const Icon(Icons.person_add_alt_1),
                                      onPressed: () =>
                                          addUserToTeam(id, name),
                                    ),
                                  ),
                                );
                              },
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

  @override
  Widget build(BuildContext context) {
    final isLoading = _loading;
    final team = _team;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          team != null
              ? (team['name'] as String? ?? widget.teamName)
              : widget.teamName,
        ),
        actions: [
          IconButton(
            tooltip: 'Save team',
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            onPressed: _saving ? null : _saveTeam,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : team == null
              ? const Center(child: Text('Team not found'))
              : RefreshIndicator(
                  onRefresh: _loadTeam,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Team name',
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _descCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Description',
                            ),
                            maxLines: 3,
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            value: _proficiency,
                            decoration: const InputDecoration(
                              labelText: 'Proficiency level',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'Recreational',
                                child: Text('Recreational'),
                              ),
                              DropdownMenuItem(
                                value: 'Intermediate',
                                child: Text('Intermediate'),
                              ),
                              DropdownMenuItem(
                                value: 'Competitive',
                                child: Text('Competitive'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val == null) return;
                              setState(() {
                                _proficiency = val;
                              });
                            },
                          ),
                          const SizedBox(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Members',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _addMember,
                                icon: const Icon(Icons.person_add_alt_1),
                                label: const Text('Add'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (_members.isEmpty)
                            const Text(
                              'No members yet.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey,
                              ),
                            )
                          else
                            Column(
                              children: _members.map((m) {
                                final name =
                                    m['full_name'] as String? ?? 'Unknown';
                                final photoUrl = m['photo_url'] as String?;
                                final role = (m['role'] as String?) ?? 'member';
                                final userId = m['user_id'] as String;

                                final lower = role.toLowerCase();
                                final isAdmin = lower == 'admin';

                                return Card(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 4),
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
                                    subtitle: null,
                                    trailing: Wrap(
                                      spacing: 4,
                                      children: [
                                        DropdownButton<String>(
                                          value: isAdmin ? 'admin' : 'member',
                                          underline:
                                              const SizedBox.shrink(),
                                          items: const [
                                            DropdownMenuItem(
                                              value: 'admin',
                                              child: Text('Admin'),
                                            ),
                                            DropdownMenuItem(
                                              value: 'member',
                                              child: Text('Member'),
                                            ),
                                          ],
                                          onChanged: (val) {
                                            if (val == null) return;
                                            _changeRole(userId, val);
                                          },
                                        ),
                                        IconButton(
                                          tooltip: 'Remove',
                                          icon: const Icon(Icons.delete),
                                          onPressed: () =>
                                              _removeMember(userId, name),
                                        ),
                                      ],
                                    ),
                                    onTap: () {
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
                              }).toList(),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }
}
