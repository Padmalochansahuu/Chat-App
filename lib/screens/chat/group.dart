
import 'package:chatapp/notification/custom_notification.dart';
import 'package:chatapp/services/auth_services.dart';
import 'package:chatapp/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class GroupCreationScreen extends StatefulWidget {
  const GroupCreationScreen({super.key});

  @override
  State<GroupCreationScreen> createState() => _GroupCreationScreenState();
}

class _GroupCreationScreenState extends State<GroupCreationScreen> {
  // --- ALL STATE AND LOGIC IS 100% IDENTICAL TO YOUR ORIGINAL CODE ---
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
    // Added listener to update UI when typing group name for FAB visibility
    _groupNameController.addListener(() => setState(() {}));
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
    
    // Using your exact createGroup logic. This now assumes createGroup returns a simple groupId string.
    final groupId = await _authService.createGroup(_groupNameController.text.trim(), _selectedUserIds.toList());
    
    if (groupId != null && mounted) {
      Navigator.pop(context); // Pop this screen
      showDialog(
        context: context,
        builder: (context) => CustomNotification(
          message: 'Group "${_groupNameController.text.trim()}" created successfully!',
          type: NotificationType.success,
        ),
      );
      // Navigate to the group chat screen using your original keys
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
      backgroundColor: AppTheme.backgroundColor,
      appBar: AppBar(
        title: Text('New Group', style: AppTheme.headline.copyWith(fontSize: 22)),
        backgroundColor: AppTheme.primaryColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // Header section for group name input and selected users
          Container(
            padding: const EdgeInsets.all(16),
            color: AppTheme.primaryColor,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _groupNameController,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.group, color: Colors.white70),
                    labelText: 'Group Name',
                    labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                    enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white54)),
                    focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppTheme.accentColor, width: 2)),
                  ),
                ),
                if (_selectedUserIds.isNotEmpty)
                  _buildSelectedUsersBar(),
              ],
            ),
          ),

          // Search bar and user list
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: AppTheme.textFieldDecoration('Search users...').copyWith(
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
              ),
              style: AppTheme.body,
            ),
          ),

          // User list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
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
                  padding: const EdgeInsets.only(top: 8.0, bottom: 90),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final doc = users[index];
                    final userId = doc.id;
                    final isSelected = _selectedUserIds.contains(userId);

                    return _UserSelectionTile(
                      doc: doc,
                      isSelected: isSelected,
                      // THIS IS YOUR ORIGINAL LOGIC FOR SELECTING/DESELECTING A USER
                      onTap: () {
                        setState(() {
                          if (isSelected) {
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
      floatingActionButton: (_selectedUserIds.isNotEmpty && _groupNameController.text.trim().isNotEmpty)
          ? FloatingActionButton(
              onPressed: _isLoading ? null : _createGroup, // Calls your original function
              backgroundColor: AppTheme.accentColor,
              child: _isLoading
                  ? const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColor))
                  : const Icon(Icons.arrow_forward, color: AppTheme.primaryColor),
            )
          : null,
    );
  }

  // Purely visual widget to show selected users
  Widget _buildSelectedUsersBar() {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: SizedBox(
        height: 60,
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('users').where(FieldPath.documentId, whereIn: _selectedUserIds.toList()).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const SizedBox.shrink();
            final selectedUsers = snapshot.data!.docs;
            return ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: selectedUsers.length,
              itemBuilder: (context, index) {
                final userDoc = selectedUsers[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 10.0),
                  child: Chip(
                    label: Text(userDoc['username'], style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
                    avatar: CircleAvatar(
                      backgroundImage: userDoc['photoUrl'] != null ? NetworkImage(userDoc['photoUrl']) : null,
                      child: userDoc['photoUrl'] == null ? Text(userDoc['username'][0].toUpperCase()) : null,
                    ),
                    backgroundColor: AppTheme.accentColor,
                    onDeleted: () {
                      // Uses your original setState logic
                      setState(() {
                        _selectedUserIds.remove(userDoc.id);
                      });
                    },
                    deleteIcon: const Icon(Icons.close, size: 18, color: AppTheme.primaryColor),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// A purely visual tile that calls your original selection logic
class _UserSelectionTile extends StatelessWidget {
  final DocumentSnapshot doc;
  final bool isSelected;
  final VoidCallback onTap;

  const _UserSelectionTile({required this.doc, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final username = data['username'] ?? 'Unknown';
    final photoUrl = data['photoUrl'] as String?;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primaryColor.withOpacity(0.1) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isSelected ? AppTheme.primaryColor : Colors.grey.shade200),
      ),
      child: ListTile(
        onTap: onTap, // Uses your original onTap logic from build()
        leading: CircleAvatar(
          radius: 25,
          backgroundImage: photoUrl != null && photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
          child: (photoUrl == null || photoUrl.isEmpty) ? Text(username.isNotEmpty ? username[0].toUpperCase() : 'U') : null,
        ),
        title: Text(username, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(data['email'] ?? 'No email available', style: TextStyle(color: Colors.grey.shade600)),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: AppTheme.primaryColor, size: 28)
            : const Icon(Icons.circle_outlined, color: Colors.grey, size: 28),
      ),
    );
  }
}