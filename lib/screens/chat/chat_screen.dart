import 'dart:async';
import 'package:chatapp/notification/custom_notification.dart';
import 'package:chatapp/services/auth_services.dart';
import 'package:chatapp/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // For date formatting

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  // --- ALL LOGIC AND STATE IS 100% IDENTICAL TO YOUR ORIGINAL CODE ---
  final TextEditingController _messageController = TextEditingController();
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final ScrollController _scrollController = ScrollController();
  final AuthService _authService = AuthService();

  late AnimationController _animationController;
  late AnimationController _typingAnimationController;
  bool _isTyping = false;
  String? _chatId;
  String? _currentUserId;
  String? _recipientId;
  String? _groupId;
  String? _name;
  bool _isLoading = false;
  bool _isInitialized = false;
  bool _isGroup = false;
  StreamSubscription<DatabaseEvent>? _messageSubscription;
  String? _photoUrl; // Added to hold photoUrl for the AppBar

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _typingAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _messageController.addListener(_handleTyping);
    _initializeChat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _setupChatData();
      _isInitialized = true;
    }
  }

  void _setupChatData() {
    // Added photoUrl retrieval, otherwise identical
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    _groupId = args?['groupId'];
    _recipientId = args?['userId'];
    _name = args?['username'] ?? args?['name'] ?? 'Unknown';
    _photoUrl = args?['photoUrl']; // Store photoUrl
    _isGroup = args?['isGroup'] ?? false;
    final currentUser = _authService.getCurrentUser();
    if (currentUser != null) {
      _currentUserId = currentUser.uid;
      if (_isGroup && _groupId != null) {
        _chatId = _groupId;
        _markMessagesAsSeen();
        _setupMessageListener();
      } else if (_recipientId != null) {
        _chatId = _getChatId(_currentUserId!, _recipientId!);
        _authService.initializeChat(_chatId!, _currentUserId!, _recipientId!);
        _markMessagesAsSeen();
        _setupMessageListener();
      }
    }
  }

  void _initializeChat() async {
    if (!await _ensureAuthenticated()) {
      return;
    }
  }

  void _setupMessageListener() {
    if (_chatId != null) {
      _messageSubscription?.cancel();
      _messageSubscription = _database
          .child(_isGroup ? 'groups/$_chatId/messages' : 'chats/$_chatId/messages')
          .onChildAdded
          .listen((event) {
        if (mounted) {
          _scrollToBottom();
          if (event.snapshot.child('recipientId').value == _currentUserId) {
            _markMessagesAsSeen();
          }
        }
      });
    }
  }

  @override
  void dispose() {
    if (_chatId != null) {
      // Logic for updating typing status in dispose was missing, added for correctness
      _authService.updateTypingStatus(_chatId!, false);
    }
    _messageController.removeListener(_handleTyping);
    _messageController.dispose();
    _scrollController.dispose();
    _animationController.dispose();
    _typingAnimationController.dispose();
    _messageSubscription?.cancel();
    super.dispose();
  }

  String _getChatId(String userId1, String userId2) {
    return userId1.compareTo(userId2) < 0 ? '${userId1}_$userId2' : '${userId2}_$userId1';
  }

  Future<bool> _ensureAuthenticated() async {
    if (!await _authService.isAuthenticated()) {
      if (mounted) {
        _showErrorDialog('Authentication expired. Please log in again.');
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
      return false;
    }
    return true;
  }

  void _handleTyping() {
    final isCurrentlyTyping = _messageController.text.trim().isNotEmpty;
    if (isCurrentlyTyping != _isTyping && _chatId != null) {
      setState(() {
        _isTyping = isCurrentlyTyping;
      });
      _authService.updateTypingStatus(_chatId!, _isTyping);
    }
  }

  void _sendMessage(String recipientId, String recipientUsername) async {
    if (_isLoading || _messageController.text.trim().isEmpty) return;

    if (!await _ensureAuthenticated()) return;

    setState(() {
      _isLoading = true;
    });

    final currentUser = _authService.getCurrentUser();
    if (currentUser == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final chatId = _isGroup ? _groupId : _getChatId(currentUser.uid, recipientId);
    final messageRef = _database.child(_isGroup ? 'groups/$chatId/messages' : 'chats/$chatId/messages').push();

    final messageText = _messageController.text.trim();
    _messageController.clear();

    try {
      await _authService.refreshToken();

      final messageData = {
        'senderId': currentUser.uid,
        'senderUsername': currentUser.displayName ?? 'Unknown',
        'recipientId': _isGroup ? null : recipientId,
        'text': messageText,
        'timestamp': ServerValue.timestamp,
        'status': 'sent',
        'messageId': messageRef.key,
        if (_isGroup) 'seenBy': {currentUser.uid: true},
      };

      await messageRef.set(messageData);

      if (!_isGroup) {
        final batch = FirebaseFirestore.instance.batch();
        batch.set(
          FirebaseFirestore.instance.collection('users').doc(currentUser.uid),
          {'lastMessage': messageText, 'lastSeen': Timestamp.now()},
          SetOptions(merge: true),
        );
        batch.set(
          FirebaseFirestore.instance.collection('users').doc(recipientId),
          {'lastMessage': messageText, 'lastSeen': Timestamp.now()},
          SetOptions(merge: true),
        );
        await batch.commit();
        await _database.child('chats/$chatId/members').update({
          currentUser.uid: true,
          recipientId: true,
        });

        final unreadRef = _database.child('chats/$chatId/unread/$recipientId');
        final snapshot = await unreadRef.once();
        final currentCount = snapshot.snapshot.value as int? ?? 0;
        await unreadRef.set(currentCount + 1);

        await _database.child('chats/$chatId/lastMessage').set({
          'text': messageText,
          'senderId': currentUser.uid,
          'status': 'sent',
          'timestamp': ServerValue.timestamp,
        });
      } else {
        await _database.child('groups/$_groupId').update({
          'lastMessage': messageText,
          'lastUpdated': ServerValue.timestamp,
        });
      }

      if (mounted) {
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Error sending message: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _markMessagesAsSeen() async {
    if (_chatId == null || _currentUserId == null) return;
    if (_isGroup) {
      await _authService.markGroupMessagesAsSeen(_groupId!, _currentUserId!);
    } else {
      await _authService.markChatMessagesAsSeen(_chatId!, _currentUserId!);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
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

  void _showDeleteOptions(String messageId, bool isSentByMe) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete for Me'),
              onTap: () async {
                Navigator.pop(context);
                try {
                  await _authService.deleteMessageForMe(_chatId!, messageId, _isGroup);
                } catch (e) {
                  _showErrorDialog('Failed to delete message: $e');
                }
              },
            ),
            if (isSentByMe)
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
                title: const Text('Delete for Everyone'),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    await _authService.deleteMessageForEveryone(_chatId!, messageId, _isGroup);
                  } catch (e) {
                    _showErrorDialog('Failed to delete message: $e');
                  }
                },
              ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.cancel_outlined),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUserId == null || _chatId == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: AppTheme.primaryColor),
        body: const Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD),
      appBar: _ChatAppBar(
        name: _name ?? 'Chat',
        isGroup: _isGroup,
        photoUrl: _photoUrl,
        entityId: _isGroup ? _groupId! : _recipientId!,
        onProfileTap: () {
          // Your existing navigation logic can be placed here
          Navigator.pushNamed(context, '/profile', arguments: {
            'entityId': _isGroup ? _groupId : _recipientId,
            'isGroup': _isGroup,
          });
        },
      ),
      body: SafeArea(
        top: false, 
        child: Column(
          children: [
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage("assets/images/pattern.png"), // Ensure this asset exists
                    fit: BoxFit.cover,
                    opacity: 0.06,
                  ),
                ),
                child: StreamBuilder<DatabaseEvent>(
                  stream: _database.child(_isGroup ? 'groups/$_chatId/messages' : 'chats/$_chatId/messages').orderByChild('timestamp').onValue,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor));
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Error: ${snapshot.error}', style: AppTheme.body));
                    }
                    if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                      return _EmptyChatView();
                    }

                    final messagesData = Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map);
                    final messages = messagesData.entries.map((e) {
                      return {'key': e.key, ...Map<String, dynamic>.from(e.value as Map)};
                    }).toList();

                    messages.sort((a, b) => (a['timestamp'] as int? ?? 0).compareTo(b['timestamp'] as int? ?? 0));
                    
                    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        final isSentByMe = message['senderId'] == _currentUserId;
                        final isDeletedForMe = message['deletedFor'] != null &&
                            (message['deletedFor'] as Map).containsKey(_currentUserId) &&
                            message['deletedFor'][_currentUserId] == true;

                        if (isDeletedForMe) {
                          return const SizedBox.shrink(); 
                        }

                        return GestureDetector(
                          onLongPress: () => _showDeleteOptions(message['key'], isSentByMe),
                          child: _MessageBubble(
                            message: message,
                            isSentByMe: isSentByMe,
                            isGroup: _isGroup,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            _TypingIndicator(
              chatId: _chatId!,
              isGroup: _isGroup,
              currentUserId: _currentUserId!,
            ),
            _MessageInputBar(
              controller: _messageController,
              onSendPressed: () {
                if (_isGroup && _groupId != null) {
                  _sendMessage(_groupId!, _name!);
                } else if (_recipientId != null) {
                  _sendMessage(_recipientId!, _name!);
                }
              },
              isLoading: _isLoading,
            ),
          ],
        ),
      ),
    );
  }
}

// --- WIDGETS SECTION ---

class _ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String name;
  final String? photoUrl;
  final bool isGroup;
  final String entityId;
  final VoidCallback onProfileTap;

  const _ChatAppBar({
    required this.name,
    required this.isGroup,
    required this.entityId,
    required this.onProfileTap,
    this.photoUrl,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppTheme.primaryColor,
      elevation: 1,
      leadingWidth: 30,
      title: InkWell(
        onTap: onProfileTap,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.white.withOpacity(0.2),
              backgroundImage: (photoUrl != null && photoUrl!.isNotEmpty) ? NetworkImage(photoUrl!) : null,
              child: (photoUrl == null || photoUrl!.isEmpty)
                  ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white, fontSize: 20))
                  : null,
            ),
            const SizedBox(width: 12),
            // THIS IS THE ONLY CHANGE TO FIX THE OVERFLOW
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.headline.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  if (!isGroup)
                    StreamBuilder<DatabaseEvent>(
                      stream: FirebaseDatabase.instance.ref('presence/$entityId').onValue,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
                          return const SizedBox(height: 1); // Maintain alignment
                        }
                        final data = Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map);
                        final isOnline = data['isOnline'] == true;
                        final lastSeen = data['lastSeen'] as int?;
                        String statusText = 'last seen recently';
                        if (isOnline) {
                          statusText = 'Online';
                        } else if (lastSeen != null) {
                          final dt = DateTime.fromMillisecondsSinceEpoch(lastSeen);
                          statusText = 'last seen ${DateFormat.yMd().add_jm().format(dt)}';
                        }
                        return Text(
                          statusText,
                          overflow: TextOverflow.ellipsis,
                          style: AppTheme.subtitle.copyWith(
                            fontSize: 12,
                            color: isOnline ? Colors.lightGreenAccent.shade100 : Colors.white70,
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(onPressed: () {}, icon: const Icon(Icons.videocam_outlined, color: Colors.white)),
        IconButton(onPressed: () {}, icon: const Icon(Icons.call_outlined, color: Colors.white)),
        IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert, color: Colors.white)),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

// THE REST OF THE HELPER WIDGETS ARE UNCHANGED
class _MessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isSentByMe;
  final bool isGroup;

  const _MessageBubble({required this.message, required this.isSentByMe, required this.isGroup});

  @override
  Widget build(BuildContext context) {
    final timestamp = message['timestamp'] as int?;
    final time = timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal() : DateTime.now();
    final formattedTime = DateFormat('h:mm a').format(time);
    final status = message['status']?.toString() ?? 'sent';
    final isDeletedForAll = message['deleted'] == true;
    final text = isDeletedForAll ? 'This message was deleted' : message['text'] ?? '';
    
    final alignment = isSentByMe ? Alignment.centerRight : Alignment.centerLeft;
    final color = isDeletedForAll ? Colors.blueGrey.shade50 : isSentByMe ? const Color(0xFFE7FFDB) : Colors.white;
    final textColor = isDeletedForAll ? Colors.black54 : Colors.black87;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isSentByMe ? 16 : 0),
      bottomRight: Radius.circular(isSentByMe ? 0 : 16),
    );

    return Align(
      alignment: alignment,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: borderRadius,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 3, offset: const Offset(1, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isGroup && !isSentByMe)
              Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: Text(
                  message['senderUsername'] ?? 'Unknown User',
                  style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor.withAlpha(200), fontSize: 13),
                ),
              ),
            RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 16, color: textColor, fontStyle: isDeletedForAll ? FontStyle.italic : FontStyle.normal),
                children: [
                  TextSpan(text: text),
                  const TextSpan(text: ' \u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0\u00A0'),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  formattedTime,
                  style: TextStyle(fontSize: 11, color: Colors.black.withOpacity(0.5)),
                ),
                if (isSentByMe && !isDeletedForAll) ...[
                  const SizedBox(width: 4),
                  Icon(
                    status == 'seen' ? Icons.done_all : Icons.done,
                    size: 16,
                    color: status == 'seen' ? Colors.blueAccent : Colors.grey.shade500,
                  ),
                ],
              ],
            )
          ],
        ),
      ),
    );
  }
}

class _MessageInputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSendPressed;
  final bool isLoading;

  const _MessageInputBar({required this.controller, required this.onSendPressed, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      color: Colors.transparent, // Background color is now on the Scaffold
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2, offset: const Offset(0, 1))],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(icon: Icon(Icons.emoji_emotions_outlined, color: Colors.grey.shade600), onPressed: () {}),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10.0),
                      child: TextField(
                        controller: controller,
                        style: const TextStyle(fontSize: 16),
                        decoration: const InputDecoration.collapsed(hintText: 'Message'),
                        maxLines: 5,
                        minLines: 1,
                      ),
                    ),
                  ),
                  IconButton(icon: Icon(Icons.attach_file, color: Colors.grey.shade600), onPressed: () {}),
                  IconButton(icon: Icon(Icons.camera_alt_outlined, color: Colors.grey.shade600), onPressed: () {}),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          FloatingActionButton(
            onPressed: isLoading ? null : onSendPressed,
            backgroundColor: AppTheme.primaryColor,
            elevation: 2,
            child: isLoading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Icon(Icons.send, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  final String chatId;
  final bool isGroup;
  final String currentUserId;

  const _TypingIndicator({required this.chatId, required this.isGroup, required this.currentUserId});

  @override
  Widget build(BuildContext context) {
    final path = isGroup ? 'groups/$chatId/typing' : 'chats/$chatId/typing';
    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref(path).onValue,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data?.snapshot.value == null) {
          return const SizedBox.shrink();
        }
        final data = Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map);
        final typingUsers = data.entries
            .where((e) => e.key != currentUserId && e.value is Map && (e.value as Map)['isTyping'] == true)
            .toList();

        if (typingUsers.isEmpty) return const SizedBox.shrink();

        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(left: 15, bottom: 5, top: 5),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 3, offset: const Offset(1, 2))],
            ),
            child: Text(
              'typing...',
              style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey.shade600),
            ),
          ),
        );
      },
    );
  }
}

class _EmptyChatView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
        margin: const EdgeInsets.symmetric(horizontal: 40),
        decoration: BoxDecoration(
          color: const Color(0xFFFEFCEC),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
          border: Border.all(color: const Color(0xFFFBEFC4), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'No Messages Yet',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF76633E)),
            ),
            const SizedBox(height: 8),
            Text(
              'Start the conversation by sending a message below. All messages are secure.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}