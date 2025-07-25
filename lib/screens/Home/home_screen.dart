
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:animation_list/animation_list.dart';
import 'package:chatapp/connection/network_check.dart';
import 'package:chatapp/notification/custom_notification.dart';
import 'package:chatapp/services/auth_services.dart';
import 'package:chatapp/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rxdart/rxdart.dart';

// Main HomeScreen Widget
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // --- STATE AND CONTROLLERS (LOGIC UNCHANGED) ---
  final TextEditingController _searchController = TextEditingController();
  final AuthService _authService = AuthService();
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  String _searchQuery = '';
  late AnimationController _fabController;
  late Animation<double> _fabScaleAnimation;
  bool _isOnline = true;
  String? _currentUserId;
  TabController? _tabController;
  Stream<CombinedSnapshot>? _combinedStream;
  StreamSubscription<CombinedSnapshot>? _combinedStreamSubscription;

  // --- LIFECYCLE METHODS (LOGIC UNCHANGED) ---
  @override
  void initState() {
    super.initState();
    _ensureAuthenticated();
    _authService.initialize();
    FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);

    _fabController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fabScaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _fabController, curve: Curves.easeInOut),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _fabController.reverse();
        }
      });

    final currentUser = _authService.getCurrentUser();
    if (currentUser != null) {
      _currentUserId = currentUser.uid;
      _authService.updatePresence(true);
    }

    NetworkCheck().connectivityStream.listen((isConnected) {
      if (mounted) {
        setState(() {
          _isOnline = isConnected;
        });
      }
    });

    _searchController.addListener(() {
      if (mounted) {
        setState(() {
          _searchQuery = _searchController.text.trim().toLowerCase();
        });
      }
    });

    _tabController = TabController(length: 2, vsync: this);
    _initializeStream();
  }

  void _initializeStream() {
    _combinedStream = combineStreams().asBroadcastStream();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _fabController.dispose();
    _tabController?.dispose();
    _combinedStreamSubscription?.cancel();
    _authService.dispose();
    super.dispose();
  }

  // --- AUTHENTICATION & DATA HANDLING (LOGIC UNCHANGED) ---
  Future<void> _ensureAuthenticated() async {
    if (!await _authService.isAuthenticated()) {
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
        showDialog(
          context: context,
          builder: (context) => CustomNotification(
            message: 'Session expired. Please log in again.',
            type: NotificationType.error,
          ),
        );
      }
    }
  }

  void _logout() async {
    try {
      await _authService.signOut();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
        showDialog(
          context: context,
          builder: (context) => CustomNotification(
            message: 'Logged out successfully!',
            type: NotificationType.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
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

  Stream<CombinedSnapshot> combineStreams() {
    return CombineLatestStream.combine2(
      _authService.firestore.collection('users').snapshots(),
      _database.child('groups').onValue,
      (QuerySnapshot usersSnapshot, DatabaseEvent groupsEvent) {
        final users = usersSnapshot.docs
            .where((doc) => doc.id != _currentUserId && (_searchQuery.isEmpty || doc['username'].toString().toLowerCase().contains(_searchQuery)))
            .toList();

        final groups = groupsEvent.snapshot.value != null
            ? Map<String, dynamic>.from(groupsEvent.snapshot.value as Map)
                .entries
                .map((entry) => {
                      'id': entry.key,
                      ...Map<String, dynamic>.from(entry.value as Map),
                    })
                .where((group) => _searchQuery.isEmpty || group['name'].toString().toLowerCase().contains(_searchQuery))
                .where((group) => group['members'] != null && (group['members'] as Map).containsKey(_currentUserId))
                .toList()
            : <Map<String, dynamic>>[];

        return CombinedSnapshot(users: users, groups: groups);
      },
    );
  }

  // --- NEW CUSTOM HEADER WIDGET ---
  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 12.0),
      decoration: const BoxDecoration(
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 8, top: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Chats', style: AppTheme.headline),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.person_outline, color: Colors.white, size: 26),
                        tooltip: 'Profile',
                        onPressed: () {
                          Navigator.pushNamed(context, '/profile');
                        },
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: Colors.white, size: 26),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        onSelected: (value) {
                          if (value == 'logout') _logout();
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'logout',
                            child: Row(
                              children: [
                                Icon(Icons.logout, color: Colors.red.shade400),
                                const SizedBox(width: 8),
                                const Text('Logout'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.black87),
                decoration: AppTheme.textFieldDecoration('Search users or groups...').copyWith(
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 20),
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(text: 'All'),
                Tab(text: 'Groups'),
              ],
              labelColor: Colors.white,
              labelStyle: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
              unselectedLabelColor: Colors.white.withOpacity(0.7),
              indicator: UnderlineTabIndicator(
                borderSide: BorderSide(width: 3.5, color: Colors.white.withOpacity(0.9)),
                insets: const EdgeInsets.symmetric(horizontal: 40.0), // Creates the short line effect
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- BUILD METHOD (UI REDESIGNED) ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundColor,
      body: Column(
        children: [
          _buildHeader(context),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                AllTab(combinedStream: _combinedStream, isOnline: _isOnline, currentUserId: _currentUserId),
                GroupsTab(database: _database, searchQuery: _searchQuery, currentUserId: _currentUserId, isOnline: _isOnline),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: ScaleTransition(
        scale: _fabScaleAnimation,
        child: FloatingActionButton(
          onPressed: () {
            _fabController.forward();
            Navigator.pushNamed(context, '/group');
          },
          backgroundColor: AppTheme.accentColor,
          elevation: 6,
          tooltip: 'Create Group',
          child: const Icon(Icons.group_add, color: AppTheme.primaryColor, size: 28),
        ),
      ),
    );
  }
}

// --- UTILITY & TAB WIDGETS (UNCHANGED, but provided for completeness) ---

class CombinedSnapshot {
  final List<QueryDocumentSnapshot> users;
  final List<Map<String, dynamic>> groups;
  CombinedSnapshot({required this.users, required this.groups});
}

class AllTab extends StatefulWidget {
  final Stream<CombinedSnapshot>? combinedStream;
  final bool isOnline;
  final String? currentUserId;
  const AllTab({super.key, this.combinedStream, required this.isOnline, this.currentUserId});

  @override
  State<AllTab> createState() => _AllTabState();
}

class _AllTabState extends State<AllTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String _getChatId(String userId1, String userId2) {
    return userId1.compareTo(userId2) < 0 ? '${userId1}_$userId2' : '${userId2}_$userId1';
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 100, color: AppTheme.primaryColor.withOpacity(0.3)),
            const SizedBox(height: 24),
            Text('No Chats Yet', style: AppTheme.headline.copyWith(fontSize: 22, color: Colors.black87), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Search for users or create a group to start a conversation.', style: AppTheme.subtitle.copyWith(color: Colors.black54, fontSize: 16), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<CombinedSnapshot>(
      stream: widget.combinedStream,
      builder: (context, AsyncSnapshot<CombinedSnapshot> snapshot) {
        if (!widget.isOnline && !snapshot.hasData) {
          return Center(child: Text('No internet connection.', style: AppTheme.body.copyWith(color: Colors.grey)));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}', style: AppTheme.body.copyWith(color: Colors.red)));
        }
        if (!snapshot.hasData || (snapshot.data!.users.isEmpty && snapshot.data!.groups.isEmpty)) {
          return _buildEmptyState();
        }

        final allItems = [
          ...snapshot.data!.users.map((user) => {'type': 'user', 'data': user}),
          ...snapshot.data!.groups.map((group) => {'type': 'group', 'data': group}),
        ];

        allItems.sort((a, b) {
          dynamic aData = a['data'];
          dynamic bData = b['data'];
          int aTimestamp = 0;
          int bTimestamp = 0;

          if (a['type'] == 'user') {
            aTimestamp = (aData['lastSeen'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          } else {
            aTimestamp = (aData['lastUpdated'] as int?) ?? 0;
          }
          if (b['type'] == 'user') {
            bTimestamp = (bData['lastSeen'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
          } else {
            bTimestamp = (bData['lastUpdated'] as int?) ?? 0;
          }
          return bTimestamp.compareTo(aTimestamp);
        });

        return AnimationList(
          padding: const EdgeInsets.only(top: 8, bottom: 80),
          duration: 1000,
          children: allItems.map((item) {
            if (item['type'] == 'user') {
              final user = item['data'] as QueryDocumentSnapshot;
              return UserTile(
                userId: user.id,
                username: user['username'] ?? 'Unknown',
                photoUrl: user['photoUrl'],
                lastSeen: (user['lastSeen'] as Timestamp?)?.toDate(),
                lastMessage: user['lastMessage'] ?? 'No messages yet',
                chatId: widget.currentUserId != null ? _getChatId(widget.currentUserId!, user.id) : null,
                currentUserId: widget.currentUserId,
              );
            } else {
              final group = item['data'] as Map<String, dynamic>;
              return GroupTile(
                groupId: group['id'],
                name: group['name'],
                photoUrl: group['photoUrl'],
                lastMessage: group['lastMessage'] ?? 'No messages yet',
                currentUserId: widget.currentUserId,
              );
            }
          }).toList(),
        );
      },
    );
  }
}

class GroupsTab extends StatefulWidget {
  final DatabaseReference database;
  final String searchQuery;
  final String? currentUserId;
  final bool isOnline;
  const GroupsTab({super.key, required this.database, required this.searchQuery, this.currentUserId, required this.isOnline});

  @override
  State<GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends State<GroupsTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_off_outlined, size: 100, color: AppTheme.primaryColor.withOpacity(0.3)),
            const SizedBox(height: 24),
            Text('No Groups Found', style: AppTheme.headline.copyWith(fontSize: 22, color: Colors.black87), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('You are not part of any groups yet. Create one to start!', style: AppTheme.subtitle.copyWith(color: Colors.black54, fontSize: 16), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return StreamBuilder<DatabaseEvent>(
      stream: widget.database.child('groups').onValue,
      builder: (context, snapshot) {
        if (!widget.isOnline && !snapshot.hasData) {
          return Center(child: Text('No internet connection.', style: AppTheme.body.copyWith(color: Colors.grey)));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}', style: AppTheme.body.copyWith(color: Colors.red)));
        }
        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
          return _buildEmptyState();
        }

        final groups = Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map)
            .entries
            .map((entry) => {'id': entry.key, ...Map<String, dynamic>.from(entry.value as Map)})
            .where((group) => widget.searchQuery.isEmpty || group['name'].toString().toLowerCase().contains(widget.searchQuery))
            .where((group) => group['members'] != null && (group['members'] as Map).containsKey(widget.currentUserId))
            .toList();

        if (groups.isEmpty) {
          return _buildEmptyState();
        }

        groups.sort((a, b) => (b['lastUpdated'] as int? ?? 0).compareTo(a['lastUpdated'] as int? ?? 0));

        return AnimationList(
          padding: const EdgeInsets.only(top: 8, bottom: 80),
          duration: 1000,
          children: groups.map((group) {
            return GroupTile(
              groupId: group['id'],
              name: group['name'],
              photoUrl: group['photoUrl'],
              lastMessage: group['lastMessage'] ?? 'No messages yet',
              currentUserId: widget.currentUserId,
            );
          }).toList(),
        );
      },
    );
  }
}

// --- TILE WIDGETS (UNCHANGED) ---

class UserTile extends StatefulWidget {
  final String userId;
  final String username;
  final String? photoUrl;
  final DateTime? lastSeen;
  final String lastMessage;
  final String? chatId;
  final String? currentUserId;

  const UserTile({
    super.key,
    required this.userId,
    required this.username,
    this.photoUrl,
    this.lastSeen,
    required this.lastMessage,
    this.chatId,
    this.currentUserId,
  });

  @override
  State<UserTile> createState() => _UserTileState();
}

class _UserTileState extends State<UserTile> {
  // --- STATE AND STREAMS (LOGIC UNCHANGED) ---
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  bool _isOnline = false;
  StreamSubscription<DatabaseEvent>? _onlineSubscription;
  StreamSubscription<DatabaseEvent>? _typingSubscription;
  bool _isTyping = false;

  @override
  void initState() {
    super.initState();
    _onlineSubscription = _database.child('presence/${widget.userId}/isOnline').onValue.listen((event) {
      if (mounted) setState(() => _isOnline = event.snapshot.value == true);
    });

    if (widget.chatId != null) {
      _typingSubscription = _database.child('chats/${widget.chatId}/typing/${widget.userId}').onValue.listen((event) {
        if (!mounted) return;
        final data = event.snapshot.value;
        if (data is Map && data['isTyping'] == true) {
          final timestamp = data['timestamp'] as int? ?? 0;
          if (DateTime.now().millisecondsSinceEpoch - timestamp < 5000) {
            if (!_isTyping) setState(() => _isTyping = true);
          } else {
            if (_isTyping) setState(() => _isTyping = false);
          }
        } else {
          if (_isTyping) setState(() => _isTyping = false);
        }
      });
    }
  }

  @override
  void dispose() {
    _onlineSubscription?.cancel();
    _typingSubscription?.cancel();
    super.dispose();
  }

  String _formatLastSeen(DateTime? lastSeen) {
    if (lastSeen == null) return '';
    final now = DateTime.now();
    final difference = now.difference(lastSeen);
    if (difference.inMinutes < 1) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        child: ListTile(
          onTap: () {
            Navigator.pushNamed(context, '/chat', arguments: {'userId': widget.userId, 'username': widget.username, 'isGroup': false});
          },
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          leading: Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                backgroundImage: widget.photoUrl != null && widget.photoUrl!.isNotEmpty
                    ? (kIsWeb
                        ? (widget.photoUrl!.startsWith('data:image')
                            ? MemoryImage(base64Decode(widget.photoUrl!.split(',')[1]))
                            : NetworkImage(widget.photoUrl!)) as ImageProvider
                        : (File(widget.photoUrl!).existsSync() ? FileImage(File(widget.photoUrl!)) : null))
                    : null,
                child: (widget.photoUrl == null ||
                        widget.photoUrl!.isEmpty ||
                        (!kIsWeb && !File(widget.photoUrl!).existsSync()))
                    ? Text(
                        widget.username.isNotEmpty ? widget.username[0].toUpperCase() : 'U',
                        style: AppTheme.headline.copyWith(color: AppTheme.primaryColor, fontSize: 24),
                      )
                    : null,
              ),
              if (_isOnline)
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.greenAccent.shade400,
                    border: Border.all(color: Colors.white, width: 2.5),
                  ),
                ),
            ],
          ),
          title: Text(widget.username, style: AppTheme.body.copyWith(fontWeight: FontWeight.bold, fontSize: 16)),
          subtitle: _isTyping
              ? Text('typing...', style: AppTheme.body.copyWith(color: AppTheme.primaryColor, fontStyle: FontStyle.italic))
              : StreamBuilder<DatabaseEvent>(
                  stream: widget.chatId != null ? _database.child('chats/${widget.chatId}/lastMessage').onValue : null,
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data?.snapshot.value != null) {
                      final data = snapshot.data!.snapshot.value;
                      if (data is Map) {
                        final text = data['text'] as String? ?? '...';
                        final senderId = data['senderId'] as String?;
                        final isMyMessage = senderId == widget.currentUserId;
                        return Row(
                          children: [
                            if (isMyMessage)
                              Icon(
                                data['status'] == 'seen' ? Icons.done_all : Icons.done,
                                size: 16,
                                color: data['status'] == 'seen' ? Colors.blueAccent : Colors.grey,
                              ),
                            if (isMyMessage) const SizedBox(width: 4),
                            // IMPORTANT: No Expanded here to prevent layout overflow
                            Flexible(
                              child: Text(
                                text,
                                style: AppTheme.body.copyWith(
                                  color: Colors.grey[600],
                                  fontStyle: text == 'This message was deleted' ? FontStyle.italic : FontStyle.normal,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        );
                      }
                    }
                    return Text(
                      widget.lastMessage,
                      style: AppTheme.body.copyWith(color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _isOnline ? 'Online' : _formatLastSeen(widget.lastSeen),
                style: AppTheme.body.copyWith(fontSize: 12, color: _isOnline ? Colors.green : Colors.grey),
              ),
              if (widget.chatId != null && widget.currentUserId != null)
                StreamBuilder<DatabaseEvent>(
                  stream: _database.child('chats/${widget.chatId}/unread/${widget.currentUserId}').onValue,
                  builder: (context, snapshot) {
                    final count = snapshot.data?.snapshot.value as int? ?? 0;
                    return count > 0
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(color: AppTheme.accentColor, borderRadius: BorderRadius.circular(12)),
                            child: Text(
                              count.toString(),
                              style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          )
                        : const SizedBox(height: 18); // Placeholder to maintain alignment
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class GroupTile extends StatefulWidget {
  final String groupId;
  final String name;
  final String? photoUrl;
  final String lastMessage;
  final String? currentUserId;

  const GroupTile({super.key, required this.groupId, required this.name, this.photoUrl, required this.lastMessage, this.currentUserId});

  @override
  State<GroupTile> createState() => _GroupTileState();
}

class _GroupTileState extends State<GroupTile> {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  StreamSubscription<DatabaseEvent>? _typingSubscription;
  bool _isTypingActive = false;

  @override
  void initState() {
    super.initState();
    _typingSubscription = _database.child('groups/${widget.groupId}/typing').onValue.listen((event) {
      if (!mounted) return;
      bool isAnyoneTyping = false;
      if (event.snapshot.value != null && event.snapshot.value is Map) {
        final typingData = Map<String, dynamic>.from(event.snapshot.value as Map);
        isAnyoneTyping = typingData.values.any((user) => user is Map && user['isTyping'] == true);
      }
      if (_isTypingActive != isAnyoneTyping) {
        setState(() => _isTypingActive = isAnyoneTyping);
      }
    });
  }

  @override
  void dispose() {
    _typingSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        elevation: 2,
        shadowColor: Colors.black.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        child: ListTile(
          onTap: () {
            Navigator.pushNamed(context, '/chat', arguments: {'groupId': widget.groupId, 'name': widget.name, 'isGroup': true});
          },
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          leading: CircleAvatar(
            radius: 28,
            backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
            backgroundImage: widget.photoUrl != null && widget.photoUrl!.isNotEmpty
                ? (kIsWeb
                    ? (widget.photoUrl!.startsWith('data:image')
                        ? MemoryImage(base64Decode(widget.photoUrl!.split(',')[1]))
                        : NetworkImage(widget.photoUrl!)) as ImageProvider
                    : (File(widget.photoUrl!).existsSync() ? FileImage(File(widget.photoUrl!)) : null))
                : null,
            child: (widget.photoUrl == null ||
                    widget.photoUrl!.isEmpty ||
                    (!kIsWeb && !File(widget.photoUrl!).existsSync()))
                ? Text(
                    widget.name.isNotEmpty ? widget.name[0].toUpperCase() : 'G',
                    style: AppTheme.headline.copyWith(color: AppTheme.primaryColor, fontSize: 24),
                  )
                : null,
          ),
          title: Text(widget.name, style: AppTheme.body.copyWith(fontWeight: FontWeight.bold, fontSize: 16)),
          subtitle: _isTypingActive
              ? Text('typing...', style: AppTheme.body.copyWith(color: AppTheme.primaryColor, fontStyle: FontStyle.italic))
              : StreamBuilder<DatabaseEvent>(
                  stream: _database.child('groups/${widget.groupId}/lastMessage').onValue,
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data?.snapshot.value != null) {
                      final data = snapshot.data!.snapshot.value;
                      // DEFENSIVE CHECK to prevent cast error
                      if (data is Map) {
                        final text = data['text'] as String? ?? '...';
                        final senderName = data['senderName'] as String?;
                        final senderId = data['senderId'] as String?;
                        final isMyMessage = senderId == widget.currentUserId;
                        final displayText = isMyMessage ? "You: $text" : (senderName != null ? "$senderName: $text" : text);
                        return Text(
                          displayText,
                          style: AppTheme.body.copyWith(color: Colors.grey[600]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        );
                      }
                    }
                    return Text(
                      widget.lastMessage,
                      style: AppTheme.body.copyWith(color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StreamBuilder<DatabaseEvent>(
                stream: _database.child('groups/${widget.groupId}/lastMessage').onValue,
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                    final data = snapshot.data!.snapshot.value;
                    if (data is Map) {
                      final timestamp = data['timestamp'] as int?;
                      if (timestamp != null) {
                        final time = DateTime.fromMillisecondsSinceEpoch(timestamp);
                        final now = DateTime.now();
                        String timeText;
                        if (now.difference(time).inDays == 0) {
                          timeText = '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
                        } else {
                          timeText = '${time.day}/${time.month}';
                        }
                        return Text(timeText, style: AppTheme.body.copyWith(fontSize: 12, color: Colors.grey));
                      }
                    }
                  }
                  return const SizedBox(height: 16);
                },
              ),
              if (widget.currentUserId != null)
                StreamBuilder<DatabaseEvent>(
                  stream: _database.child('groups/${widget.groupId}/unread/${widget.currentUserId}').onValue,
                  builder: (context, snapshot) {
                    final count = snapshot.data?.snapshot.value as int? ?? 0;
                    return count > 0
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(color: AppTheme.accentColor, borderRadius: BorderRadius.circular(12)),
                            child: Text(
                              count.toString(),
                              style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          )
                        : const SizedBox(height: 18);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}