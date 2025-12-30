import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/location_service.dart';

class LocationPickerDialog extends StatefulWidget {
  const LocationPickerDialog({super.key});

  @override
  State<LocationPickerDialog> createState() => _LocationPickerDialogState();
}

class _LocationPickerDialogState extends State<LocationPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, String>> _searchResults = [];
  bool _isSearching = false;
  bool _useAutoLocation = true;

  @override
  void initState() {
    super.initState();
    _checkCurrentMode();
  }

  Future<void> _checkCurrentMode() async {
    final isManual = await LocationService.isUsingManualLocation();
    setState(() {
      _useAutoLocation = !isManual;
    });
  }

  Future<void> _searchLocations(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final results = await LocationService.searchLocations(query);
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error searching: $e')),
        );
      }
    }
  }

  Future<void> _selectLocation(Map<String, String> location) async {
    try {
      // Parse city and state from display string (format: "City, State")
      final display = location['display']!;
      final parts = display.split(', ');
      final city = parts.length >= 1 ? parts[0].trim() : '';
      final state = parts.length >= 2 ? parts[1].trim() : '';
      final zip = location['zip']!;
      
      // Save to profile
      final supa = Supabase.instance.client;
      final user = supa.auth.currentUser;
      if (user != null && city.isNotEmpty && state.isNotEmpty) {
        await supa.from('users').update({
          'home_city': city,
          'home_state': state,
          'home_zip_code': zip,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', user.id);
      }
      
      // Also set as manual location for immediate use
      await LocationService.setManualLocation(
        displayName: display,
        zipCode: zip,
      );

      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate location changed
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error setting location: $e')),
        );
      }
    }
  }

  Future<void> _useDeviceLocation() async {
    try {
      // Get current device location and save to profile
      final location = await LocationService.getCurrentLocationDisplay();
      final zip = await LocationService.getCurrentZipCode();
      
      if (location != null && location.isNotEmpty && zip != null && zip.isNotEmpty) {
        // Parse city and state from location string (format: "City, State")
        final parts = location.split(', ');
        if (parts.length >= 2) {
          final city = parts[0].trim();
          final state = parts[1].trim();
          
          // Save to profile
          final supa = Supabase.instance.client;
          final user = supa.auth.currentUser;
          if (user != null) {
            await supa.from('users').update({
              'home_city': city,
              'home_state': state,
              'home_zip_code': zip,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            }).eq('id', user.id);
            
            // Also set as manual location for immediate use
            await LocationService.setManualLocation(
              displayName: location,
              zipCode: zip,
            );
          }
        }
      }

      if (mounted) {
        Navigator.of(context).pop(true); // Return true to indicate location changed
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error setting location: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Change Location',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Auto Location Option
            Card(
              child: ListTile(
                leading: Radio<bool>(
                  value: true,
                  groupValue: _useAutoLocation,
                  onChanged: (value) {
                    setState(() {
                      _useAutoLocation = true;
                    });
                  },
                ),
                title: const Text('Set to Current Location'),
                subtitle: const Text('Get your current device location and save to profile'),
                trailing: const Icon(Icons.gps_fixed),
                onTap: () {
                  setState(() {
                    _useAutoLocation = true;
                  });
                },
              ),
            ),
            const SizedBox(height: 12),

            // Manual Location Option
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: Radio<bool>(
                      value: false,
                      groupValue: _useAutoLocation,
                      onChanged: (value) {
                        setState(() {
                          _useAutoLocation = false;
                        });
                      },
                    ),
                    title: const Text('Search Location'),
                    subtitle: const Text('Manually search for a location'),
                    trailing: const Icon(Icons.search),
                    onTap: () {
                      setState(() {
                        _useAutoLocation = false;
                      });
                    },
                  ),
                  if (!_useAutoLocation) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Enter city name or ZIP code',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        onChanged: (value) {
                          if (value.length >= 3) {
                            _searchLocations(value);
                          } else {
                            setState(() {
                              _searchResults = [];
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Search Results
            if (!_useAutoLocation && _searchController.text.length >= 3) ...[
              const SizedBox(height: 12),
              const Text(
                'Search Results:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _isSearching
                    ? const Center(child: CircularProgressIndicator())
                    : _searchResults.isEmpty
                        ? const Center(
                            child: Text(
                              'No results found',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              final location = _searchResults[index];
                              return ListTile(
                                leading: const Icon(Icons.location_on),
                                title: Text(location['display']!),
                                subtitle: Text('ZIP: ${location['zip']}'),
                                onTap: () => _selectLocation(location),
                              );
                            },
                          ),
              ),
            ],

            // Action Buttons
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                if (_useAutoLocation)
                  ElevatedButton.icon(
                    onPressed: _useDeviceLocation,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Set to Current Location'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

