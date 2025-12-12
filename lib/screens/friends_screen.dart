import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _emailController = TextEditingController();
  bool _adding = false;
  List<Map<String, dynamic>> _friends = [];

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    final supa = Supabase.instance.client;
    final user = supa.auth.currentUser;
    if (user == null) return;

    // Get accepted friendships where current user is user_id
    final rows = await supa
        .from('friends')
        .select('friend_id, friend:friend_id(full_name)')
        .eq('user_id', user.id)
        .eq('status', 'accepted');

    setState(() {
      _friends = (rows as List)
          .map<Map<String, dynamic>>((r) {
            final friend = r['friend'] as Map<String, dynamic>?;
            return {
              'friend_id': r['friend_id'],
              'friend_name': friend?['full_name'] ?? 'Unknown',
            };
          })
          .toList();
    });
  }

  Future<void> _addFriendByEmail() async {
    setState(() => _adding = true);

    final supa = Supabase.instance.client;
    final currentUser = supa.auth.currentUser;
    if (currentUser == null) return;

    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _adding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an email')),
      );
      return;
    }

    // Call RPC function to find user by email from auth.users
    final result = await supa.rpc(
      'get_user_by_email',
      params: {'email_input': email},
    );

    if (result == null) {
      setState(() => _adding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No user found with that email')),
      );
      return;
    }

    final data = result as Map<String, dynamic>;
    final friendId = data['id'] as String?;

    if (friendId == null) {
      setState(() => _adding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No user found with that email')),
      );
      return;
    }

    if (friendId == currentUser.id) {
      setState(() => _adding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot add yourself')),
      );
      return;
    }

    // Insert symmetrical friendship (both accepted for now)
    await supa.from('friends').upsert([
      {
        'user_id': currentUser.id,
        'friend_id': friendId,
        'status': 'accepted',
      },
      {
        'user_id': friendId,
        'friend_id': currentUser.id,
        'status': 'accepted',
      },
    ]);

    setState(() => _adding = false);
    _emailController.clear();
    await _loadFriends();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Friend added')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Friends')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Friend email',
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _adding ? null : _addFriendByEmail,
              child: Text(_adding ? 'Adding...' : 'Add Friend'),
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Your friends:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: _friends.length,
                itemBuilder: (context, index) {
                  final f = _friends[index];
                  return ListTile(
                    leading: const Icon(Icons.person),
                    title: Text(f['friend_name'] ?? 'Unknown'),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
