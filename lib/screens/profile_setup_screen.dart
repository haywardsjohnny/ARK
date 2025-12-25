import 'dart:typed_data';
import 'user_profile_screen.dart';


import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/location_service.dart';

import 'select_sports_screen.dart';
import 'friends_screen.dart';
import 'teams_screen.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();

  bool _loadingProfile = false;
  bool _savingProfile = false;
  bool _uploadingPhoto = false;

  String? _photoUrl; // stored in users.photo_url

  @override
  void initState() {
    super.initState();
    _loadExistingProfile();
  }

  Future<void> _loadExistingProfile() async {
    setState(() => _loadingProfile = true);

    final supa = Supabase.instance.client;
    final user = supa.auth.currentUser;
    if (user == null) {
      setState(() => _loadingProfile = false);
      return;
    }

    final res = await supa
        .from('users')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (res != null) {
      setState(() {
        _nameController.text = res['full_name'] ?? '';
        _bioController.text = res['bio'] ?? '';
        _photoUrl = res['photo_url'] as String?;
      });
    }

    setState(() => _loadingProfile = false);
  }

  Future<void> _saveProfile() async {
    setState(() => _savingProfile = true);

    final supa = Supabase.instance.client;
    final user = supa.auth.currentUser;
    if (user == null) {
      setState(() => _savingProfile = false);
      return;
    }

    final data = {
      'id': user.id,
      'full_name': _nameController.text.trim(),
      'bio': _bioController.text.trim(),
      'photo_url': _photoUrl,
      'updated_at': DateTime.now().toIso8601String(),
    };

    await supa.from('users').upsert(data);

    setState(() => _savingProfile = false);

    if (!mounted) return;
    if (!mounted) return;

// Optional: show a quick success toast
ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(content: Text('Profile saved')),
);

// Go to the nice profile view and replace current page
Navigator.of(context).pushReplacement(
  MaterialPageRoute(
    builder: (_) => const UserProfileScreen(),
  ),
);
  }

  Future<void> _logout() async {
    // Note: We don't clear location cache on logout anymore
    // Cache is now user-specific, so each user has their own cached location
    // This allows faster loading while keeping locations separate per user
    
    await Supabase.instance.client.auth.signOut();
  }

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();

    try {
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70, // compress a bit
      );

      if (picked == null) {
        return; // user cancelled
      }

      setState(() => _uploadingPhoto = true);

      final supa = Supabase.instance.client;
      final user = supa.auth.currentUser;
      if (user == null) {
        setState(() => _uploadingPhoto = false);
        return;
      }

      // 1) Upload to storage
      Uint8List bytes = await picked.readAsBytes();
      final fileExt = picked.name.split('.').last;
      final filePath =
          'avatar_${user.id}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';

      await supa.storage.from('avatars').uploadBinary(
            filePath,
            bytes,
            fileOptions: FileOptions(
              contentType: picked.mimeType ?? 'image/$fileExt',
              upsert: true,
            ),
          );

      // 2) Get public URL
      final publicUrl =
          supa.storage.from('avatars').getPublicUrl(filePath);

      setState(() {
        _photoUrl = publicUrl;
        _uploadingPhoto = false;
      });

      // 3) Try to save into users table (but don't treat failure as upload fail)
      try {
        await supa.from('users').upsert({
          'id': user.id,
          'photo_url': publicUrl,
          'updated_at': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Photo uploaded, but could not update profile: $e',
            ),
          ),
        );
        return;
      }

      // 4) Everything succeeded
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo updated')),
      );
    } catch (e) {
      setState(() => _uploadingPhoto = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to upload photo: $e')),
      );
    }
  }

  Widget _buildAvatar() {
    const double size = 96;

    Widget avatar;
    if (_photoUrl != null && _photoUrl!.isNotEmpty) {
      avatar = CircleAvatar(
        radius: size / 2,
        backgroundImage: NetworkImage(_photoUrl!),
        backgroundColor: Colors.grey[300],
      );
    } else {
      avatar = CircleAvatar(
        radius: size / 2,
        backgroundColor: Colors.grey[300],
        child: const Icon(
          Icons.person,
          size: 48,
          color: Colors.white,
        ),
      );
    }

    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            avatar,
            Positioned(
              right: 4,
              bottom: 4,
              child: InkWell(
                onTap: _uploadingPhoto ? null : _pickAndUploadPhoto,
                borderRadius: BorderRadius.circular(20),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.green,
                  child: _uploadingPhoto
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 16,
                        ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Tap camera to change photo',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingProfile) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Logout",
            onPressed: _logout,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: _buildAvatar()),
              const SizedBox(height: 24),

              // Name, Bio
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Full Name'),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _bioController,
                decoration: const InputDecoration(labelText: 'Bio'),
                maxLines: 3,
              ),
              const SizedBox(height: 16),

              ElevatedButton(
                onPressed: _savingProfile ? null : _saveProfile,
                child: Text(_savingProfile ? 'Saving...' : 'Save Profile'),
              ),

              const SizedBox(height: 24),
              const Text(
                'Interests',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SelectSportsScreen(),
                    ),
                  );
                },
                child: const Text('Choose Sports'),
              ),

              const SizedBox(height: 24),
              const Text(
                'Social',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const FriendsScreen(),
                    ),
                  );
                },
                child: const Text('Manage Friends'),
              ),

              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const TeamsScreen(),
                    ),
                  );
                },
                child: const Text('Manage Teams'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
