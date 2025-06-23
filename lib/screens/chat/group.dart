import 'dart:convert';
import 'dart:io';
import 'package:chatapp/notification/custom_notification.dart';
import 'package:chatapp/services/auth_services.dart';
import 'package:chatapp/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class GroupCreationScreen extends StatefulWidget {
  const GroupCreationScreen({super.key});

  @override
  State<GroupCreationScreen> createState() => _GroupCreationScreenState();
}

class _GroupCreationScreenState extends State<GroupCreationScreen> {
  final TextEditingController _groupNameController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final AuthService _authService = AuthService();
  String _searchQuery = '';
  Set<String> _selectedUserIds = {};
  String? _currentUserId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final currentUser = _authService.getCurrentUser();
    if (currentUser != null) {
      _currentUserId = currentUser.uid;
    }
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
  if (_isLoading || _groupNameController.text.trim().isEmpty || _selectedUserIds.isEmpty) {
    _showErrorDialog('Please enter a group name and select at least one member.');
    return;
  }

  setState(() {
    _isLoading = true;
  });

  final groupId = await _authService.createGroup(_groupNameController.text.trim(), _selectedUserIds.toList());
  if (groupId != null && mounted) {
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (context) => CustomNotification(
        message: 'Group "${_groupNameController.text.trim()}" created successfully!',
        type: NotificationType.success,
      ),
    );
    // Navigate to the group chat screen
    Navigator.pushNamed(context, '/chat', arguments: {
      'groupId': groupId,
      'name': _groupNameController.text.trim(),
      'isGroup': true,
    });
  } else if (mounted) {
    _showErrorDialog('Failed to create group. Please try again.');
  }

  if (mounted) {
    setState(() {
      _isLoading = false;
    });
  }
}

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => CustomNotification(
        message: message,
        type: NotificationType.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('New Group', style: AppTheme.headline.copyWith(fontSize: 20, color: Colors.white)),
        backgroundColor: AppTheme.primaryColor,
        elevation: 2,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _createGroup,
            child: Text(
              'Create',
              style: AppTheme.buttonText.copyWith(color: _isLoading ? Colors.grey : Colors.white),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _groupNameController,
              decoration: AppTheme.textFieldDecoration('Enter group name'),
              style: AppTheme.body,
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16.0),
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              decoration: AppTheme.textFieldDecoration('Search users...').copyWith(
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: AppTheme.primaryColor),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
              ),
              style: AppTheme.body,
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error loading users', style: AppTheme.body));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(child: Text('No users found', style: AppTheme.body));
                }

                final users = snapshot.data!.docs
                    .where((doc) => doc.id != _currentUserId)
                    .where((doc) => _searchQuery.isEmpty || (doc['username'] as String).toLowerCase().contains(_searchQuery))
                    .toList();

                return ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final doc = users[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final userId = doc.id;
                    final username = data['username'] ?? 'Unknown';
                    final photoUrl = data['photoUrl'] as String?;

                    return ListTile(
                      leading: CircleAvatar(
  radius: 20,
  backgroundImage: photoUrl != null
      ? (kIsWeb
          ? (photoUrl.startsWith('data:image')
              ? MemoryImage(base64Decode(photoUrl.split(',')[1]))
              : null)
          : File(photoUrl).existsSync()
              ? FileImage(File(photoUrl))
              : null)
      : null,
  child: photoUrl == null ||
          (kIsWeb
              ? !photoUrl.startsWith('data:image')
              : !File(photoUrl).existsSync())
      ? Text(
          username.isNotEmpty ? username[0].toUpperCase() : 'U',
          style: AppTheme.body.copyWith(color: Colors.white),
        )
      : null,
),
                      title: Text(username, style: AppTheme.body.copyWith(fontWeight: FontWeight.w500)),
                      trailing: Checkbox(
                        value: _selectedUserIds.contains(userId),
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selectedUserIds.add(userId);
                            } else {
                              _selectedUserIds.remove(userId);
                            }
                          });
                        },
                        activeColor: AppTheme.primaryColor,
                      ),
                      onTap: () {
                        setState(() {
                          if (_selectedUserIds.contains(userId)) {
                            _selectedUserIds.remove(userId);
                          } else {
                            _selectedUserIds.add(userId);
                          }
                        });
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}