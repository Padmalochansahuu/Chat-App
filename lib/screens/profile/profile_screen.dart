import 'dart:convert';
import 'dart:io';
import 'package:chatapp/notification/custom_notification.dart';
import 'package:chatapp/services/auth_services.dart';
import 'package:chatapp/theme/app_theme.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileScreen extends StatefulWidget {
  final String? entityId; // For user or group
  final bool isGroup;

  const ProfileScreen({super.key, this.entityId, this.isGroup = false});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  String? _cachedPhotoUrl;
  String? _status = 'Hey there! I am using this app.';
  final TextEditingController _statusController = TextEditingController();
  final AuthService _authService = AuthService();
  String? _currentUserId;
  bool _isAdmin = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCachedData();
    final currentUser = _authService.getCurrentUser();
    if (currentUser != null) {
      _currentUserId = currentUser.uid;
    }
    if (widget.isGroup && widget.entityId != null) {
      _checkAdminStatus();
    }
  }

  Future<void> _loadCachedData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _cachedPhotoUrl = prefs.getString('photoUrl');
      _status = prefs.getString('status') ?? 'Hey there! I am using this app.';
      _statusController.text = _status ?? '';
    });
  }

  Future<void> _checkAdminStatus() async {
    if (widget.entityId != null) {
      try {
        final groupData = await _database.child('groups/${widget.entityId}').once();
        if (groupData.snapshot.value != null) {
          final data = Map<String, dynamic>.from(groupData.snapshot.value as Map);
          setState(() {
            _isAdmin = data['createdBy'] == _currentUserId;
          });
        }
      } catch (e) {
        print('Error checking admin status: $e');
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => CustomNotification(
              message: 'Error checking group admin status: $e',
              type: NotificationType.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _pickAndSaveImage() async {
    if (widget.isGroup && !_isAdmin) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => CustomNotification(
            message: 'Only admin can change group image',
            type: NotificationType.error,
          ),
        );
      }
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );

    if (pickedFile != null) {
      final user = _authService.getCurrentUser();
      if (user == null) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => CustomNotification(
              message: 'Not logged in',
              type: NotificationType.error,
            ),
          );
        }
        return;
      }

      setState(() {
        _isLoading = true;
      });

      try {
        String photoUrl;
        if (kIsWeb) {
          final bytes = await pickedFile.readAsBytes();
          photoUrl = base64Encode(bytes);
        } else {
          final directory = await getApplicationDocumentsDirectory();
          final fileName = '${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg';
          photoUrl = '${directory.path}/$fileName';
          final imageFile = File(pickedFile.path);
          await imageFile.copy(photoUrl);
        }

        if (widget.isGroup && widget.entityId != null) {
          await _database.child('groups/${widget.entityId}/photoUrl').set(photoUrl);
        } else {
          await _authService.firestore.collection('users').doc(user.uid).update({
            'photoUrl': photoUrl,
          });
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('photoUrl', photoUrl);

        if (mounted) {
          setState(() {
            _cachedPhotoUrl = photoUrl;
            _isLoading = false;
          });
          showDialog(
            context: context,
            builder: (context) => CustomNotification(
              message: 'Profile image updated successfully!',
              type: NotificationType.success,
            ),
          );
        }
      } catch (e) {
        print('Error saving image: $e');
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
          showDialog(
            context: context,
            builder: (context) => CustomNotification(
              message: 'Error saving image: $e',
              type: NotificationType.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _saveStatus() async {
    if (widget.isGroup && !_isAdmin) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => CustomNotification(
            message: 'Only admin can change group status',
            type: NotificationType.error,
          ),
        );
      }
      return;
    }

    final user = _authService.getCurrentUser();
    if (user == null) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => CustomNotification(
            message: 'Authentication failed',
            type: NotificationType.error,
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (widget.isGroup && widget.entityId != null) {
        await _database.child('groups/${widget.entityId}').update({
          'status': _statusController.text.trim(),
        });
      } else {
        await _authService.firestore.collection('users').doc(user.uid).update({
          'status': _statusController.text.trim(),
        });
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('status', _statusController.text.trim());

      if (mounted) {
        setState(() {
          _status = _statusController.text.trim();
          _isLoading = false;
        });
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (context) => CustomNotification(
            message: 'Status updated successfully!',
            type: NotificationType.success,
          ),
        );
      }
    } catch (e) {
      print('Error updating status: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        showDialog(
          context: context,
          builder: (context) => CustomNotification(
            message: 'Error updating status: $e',
            type: NotificationType.error,
          ),
        );
      }
    }
  }

  void _showStatusDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update Status', style: AppTheme.headline),
        content: TextField(
          controller: _statusController,
          decoration: AppTheme.textFieldDecoration('Enter your status'),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: AppTheme.body.copyWith(color: AppTheme.primaryColor)),
          ),
          ElevatedButton(
            onPressed: _isLoading ? null : _saveStatus,
            style: AppTheme.elevatedButtonStyle,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text('Save', style: AppTheme.buttonText),
          ),
        ],
      ),
    );
  }

  void _logout() async {
    setState(() {
      _isLoading = true;
    });
    try {
      await _authService.signOut();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
        showDialog(
          context: context,
          builder: (context) => CustomNotification(
            message: 'Logged out successfully!',
            type: NotificationType.success,
          ),
        );
      }
    } catch (e) {
      print('Error logging out: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        showDialog(
          context: context,
          builder: (context) => CustomNotification(
            message: 'Error logging out: $e',
            type: NotificationType.error,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _statusController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.getCurrentUser();

    if (user == null && !widget.isGroup) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_off, size: 60, color: Colors.grey),
              const SizedBox(height: 16),
              Text('Not logged in', style: AppTheme.body),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pushNamed(context, '/login'),
                style: AppTheme.elevatedButtonStyle,
                child: Text('Login', style: AppTheme.buttonText),
              ),
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 600) {
          // Web-specific layout
          final maxWidth = 600.0;
          final padding = 24.0;
          final textScaleFactor = constraints.maxWidth > 1200 ? 1.2 : 1.0;
          final avatarRadius = 100.0;

          return Scaffold(
            body: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppTheme.primaryColor.withOpacity(0.2), Colors.white],
                ),
              ),
              child: Column(
                children: [
                  // Custom AppBar for web
                  Container(
                    padding: EdgeInsets.all(padding),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        Expanded(
                          child: Text(
                            widget.isGroup ? 'Group Profile' : 'Profile',
                            style: AppTheme.headline.copyWith(
                              fontSize: 20 * textScaleFactor,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (!widget.isGroup)
                          IconButton(
                            icon: _isLoading
                                ? SizedBox(
                                    width: 20 * textScaleFactor,
                                    height: 20 * textScaleFactor,
                                    child: const CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.logout, color: Colors.white),
                            onPressed: _isLoading ? null : _logout,
                            tooltip: 'Logout',
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: EdgeInsets.all(padding),
                        child: Container(
                          constraints: BoxConstraints(maxWidth: maxWidth),
                          child: StreamBuilder(
                            stream: widget.isGroup && widget.entityId != null
                                ? kIsWeb
                                    ? FirebaseDatabase.instance.ref('groups/${widget.entityId}').onValue
                                    : _authService.getGroupData(widget.entityId!)
                                : _authService.firestore.collection('users').doc(user?.uid).snapshots(),
                            builder: (context, AsyncSnapshot snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting) {
                                return const Center(child: CircularProgressIndicator());
                              }
                              if (snapshot.hasError) {
                                print('StreamBuilder error: ${snapshot.error}');
                                return Center(
                                  child: Text(
                                    'Error loading profile: ${snapshot.error}',
                                    style: AppTheme.body,
                                    textAlign: TextAlign.center,
                                  ),
                                );
                              }
                              if (!snapshot.hasData) {
                                return Center(child: Text('No profile data available', style: AppTheme.body));
                              }

                              final data = widget.isGroup
                                  ? (kIsWeb
                                      ? (snapshot.data.snapshot.value != null
                                          ? Map<String, dynamic>.from(snapshot.data.snapshot.value as Map)
                                          : {})
                                      : (snapshot.data as Map<String, dynamic>?) ?? {})
                                  : (snapshot.data.data() as Map<String, dynamic>?) ?? {};
                              final username =
                                  widget.isGroup ? data['name'] ?? 'Unknown Group' : data['username'] ?? 'Unknown';
                              final email = widget.isGroup ? '' : data['email'] ?? 'No email';
                              final photoUrl = data['photoUrl'] as String? ?? _cachedPhotoUrl;
                              final status = data['status'] as String? ?? _status;

                              return Column(
                                children: [
                                  Stack(
                                    alignment: Alignment.bottomRight,
                                    children: [
                                      CircleAvatar(
                                        radius: avatarRadius,
                                        backgroundImage: photoUrl != null
                                            ? (kIsWeb
                                                ? (photoUrl.startsWith('data:image')
                                                    ? MemoryImage(base64Decode(photoUrl.split(',')[1]))
                                                    : NetworkImage(photoUrl))
                                                : File(photoUrl).existsSync()
                                                    ? FileImage(File(photoUrl))
                                                    : null)
                                            : null,
                                        backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                                        child: photoUrl == null ||
                                                (kIsWeb
                                                    ? !photoUrl.startsWith('data:image') &&
                                                        !photoUrl.startsWith('http')
                                                    : !File(photoUrl).existsSync())
                                            ? Text(
                                                username.isNotEmpty ? username[0].toUpperCase() : 'U',
                                                style: AppTheme.headline.copyWith(
                                                  fontSize: avatarRadius * 0.75,
                                                  color: AppTheme.primaryColor,
                                                ),
                                              )
                                            : null,
                                      ),
                                      if (_isAdmin || !widget.isGroup)
                                        Container(
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryColor,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black26,
                                                blurRadius: 4,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: IconButton(
                                            icon: _isLoading
                                                ? SizedBox(
                                                    width: 20 * textScaleFactor,
                                                    height: 20 * textScaleFactor,
                                                    child: const CircularProgressIndicator(
                                                      color: Colors.white,
                                                      strokeWidth: 2,
                                                    ),
                                                  )
                                                : const Icon(Icons.camera_alt, color: Colors.white),
                                            onPressed: _isLoading ? null : _pickAndSaveImage,
                                            iconSize: 28 * textScaleFactor,
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    username,
                                    style: AppTheme.headline.copyWith(
                                      fontSize: 28 * textScaleFactor,
                                      fontWeight: FontWeight.bold,
                                      color: AppTheme.primaryColor,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  if (!widget.isGroup) const SizedBox(height: 8),
                                  if (!widget.isGroup)
                                    Text(
                                      email,
                                      style: AppTheme.body.copyWith(
                                        fontSize: 16 * textScaleFactor,
                                        color: Colors.grey[600],
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  const SizedBox(height: 16),
                                  Card(
                                    elevation: 4,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    color: Colors.white,
                                    child: ListTile(
                                      leading: Icon(
                                        Icons.info_outline,
                                        color: AppTheme.primaryColor,
                                        size: 24 * textScaleFactor,
                                      ),
                                      title: Text(
                                        'About',
                                        style: AppTheme.body.copyWith(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 16 * textScaleFactor,
                                        ),
                                      ),
                                      subtitle: Text(
                                        status ?? 'Hey there! I am using this app.',
                                        style: AppTheme.body.copyWith(
                                          color: Colors.grey[700],
                                          fontSize: 14 * textScaleFactor,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      trailing: Icon(
                                        Icons.edit,
                                        color: AppTheme.primaryColor,
                                        size: 20 * textScaleFactor,
                                      ),
                                      onTap: (_isAdmin || !widget.isGroup) ? _showStatusDialog : null,
                                    ),
                                  ),
                                  if (widget.isGroup && _isAdmin)
                                    ListTile(
                                      leading: Icon(
                                        Icons.person_add,
                                        color: AppTheme.primaryColor,
                                        size: 24 * textScaleFactor,
                                      ),
                                      title: Text(
                                        'Manage Members',
                                        style: AppTheme.body.copyWith(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 16 * textScaleFactor,
                                        ),
                                      ),
                                      onTap: () {
                                        showDialog(
                                          context: context,
                                          builder: (context) => CustomNotification(
                                            message: 'Member management coming soon!',
                                            type: NotificationType.info,
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ));
          } else {
            // Original mobile layout (unchanged)
            return Scaffold(
              appBar: AppBar(
                title: Text(
                  widget.isGroup ? 'Group Profile' : 'Profile',
                  style: AppTheme.headline.copyWith(fontSize: 20, color: Colors.white),
                ),
                backgroundColor: AppTheme.primaryColor,
                elevation: 4,
                actions: [
                  if (!widget.isGroup)
                    IconButton(
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.logout, color: Colors.white),
                      onPressed: _isLoading ? null : _logout,
                      tooltip: 'Logout',
                    ),
                ],
              ),
              body: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppTheme.primaryColor.withOpacity(0.2), Colors.white],
                  ),
                ),
                child: StreamBuilder(
                  stream: widget.isGroup && widget.entityId != null
                      ? kIsWeb
                          ? FirebaseDatabase.instance.ref('groups/${widget.entityId}').onValue
                          : _authService.getGroupData(widget.entityId!)
                      : _authService.firestore.collection('users').doc(user?.uid).snapshots(),
                  builder: (context, AsyncSnapshot snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      print('StreamBuilder error: ${snapshot.error}');
                      return Center(
                        child: Text(
                          'Error loading profile: ${snapshot.error}',
                          style: AppTheme.body,
                          textAlign: TextAlign.center,
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return Center(child: Text('No profile data available', style: AppTheme.body));
                    }

                    final data = widget.isGroup
                        ? (kIsWeb
                            ? (snapshot.data.snapshot.value != null
                                ? Map<String, dynamic>.from(snapshot.data.snapshot.value as Map)
                                : {})
                            : (snapshot.data as Map<String, dynamic>?) ?? {})
                        : (snapshot.data.data() as Map<String, dynamic>?) ?? {};
                    final username = widget.isGroup ? data['name'] ?? 'Unknown Group' : data['username'] ?? 'Unknown';
                    final email = widget.isGroup ? '' : data['email'] ?? 'No email';
                    final photoUrl = data['photoUrl'] as String? ?? _cachedPhotoUrl;
                    final status = data['status'] as String? ?? _status;

                    return ListView(
                      padding: const EdgeInsets.all(16.0),
                      children: [
                        Center(
                          child: Column(
                            children: [
                              Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  CircleAvatar(
                                    radius: 80,
                                    backgroundImage: photoUrl != null
                                        ? (kIsWeb
                                            ? (photoUrl.startsWith('data:image')
                                                ? MemoryImage(base64Decode(photoUrl.split(',')[1]))
                                                : null)
                                            : File(photoUrl).existsSync()
                                                ? FileImage(File(photoUrl))
                                                : null)
                                        : null,
                                    backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                                    child: photoUrl == null ||
                                            (kIsWeb
                                                ? !photoUrl.startsWith('data:image')
                                                : !File(photoUrl).existsSync())
                                        ? Text(
                                            username.isNotEmpty ? username[0].toUpperCase() : 'U',
                                            style: AppTheme.headline.copyWith(
                                              fontSize: 60,
                                              color: AppTheme.primaryColor,
                                            ),
                                          )
                                        : null,
                                  ),
                                  if (_isAdmin || !widget.isGroup)
                                    Container(
                                      decoration: BoxDecoration(
                                        color: AppTheme.primaryColor,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black26,
                                            blurRadius: 4,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: IconButton(
                                        icon: _isLoading
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child: CircularProgressIndicator(
                                                    color: Colors.white, strokeWidth: 2),
                                              )
                                            : const Icon(Icons.camera_alt, color: Colors.white),
                                        onPressed: _isLoading ? null : _pickAndSaveImage,
                                        iconSize: 28,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              Text(
                                username,
                                style: AppTheme.headline.copyWith(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryColor,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              if (!widget.isGroup) const SizedBox(height: 8),
                              if (!widget.isGroup)
                                Text(
                                  email,
                                  style: AppTheme.body.copyWith(
                                    fontSize: 16,
                                    color: Colors.grey[600],
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              const SizedBox(height: 16),
                              Card(
                                elevation: 4,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                color: Colors.white,
                                child: ListTile(
                                  leading: Icon(Icons.info_outline, color: AppTheme.primaryColor),
                                  title: Text(
                                    'About',
                                    style: AppTheme.body.copyWith(fontWeight: FontWeight.w500),
                                  ),
                                  subtitle: Text(
                                    status ?? 'Hey there! I am using this app.',
                                    style: AppTheme.body.copyWith(color: Colors.grey[700]),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Icon(Icons.edit, color: AppTheme.primaryColor),
                                  onTap: (_isAdmin || !widget.isGroup) ? _showStatusDialog : null,
                                ),
                              ),
                              if (widget.isGroup && _isAdmin)
                                ListTile(
                                  leading: Icon(Icons.person_add, color: AppTheme.primaryColor),
                                  title: Text('Manage Members', style: AppTheme.body.copyWith(fontWeight: FontWeight.w500)),
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      builder: (context) => CustomNotification(
                                        message: 'Member management coming soon!',
                                        type: NotificationType.info,
                                      ),
                                    );
                                  },
                                ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          }
    });
 
  }}