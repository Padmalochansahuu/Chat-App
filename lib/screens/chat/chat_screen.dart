import 'dart:async';
import 'package:chatapp/notification/custom_notification.dart';
import 'package:chatapp/services/auth_services.dart';
import 'package:chatapp/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
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
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    _groupId = args?['groupId'];
    _recipientId = args?['userId'];
    _name = args?['username'] ?? args?['name'] ?? 'Unknown';
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
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
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
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
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
                leading: const Icon(Icons.delete_forever, color: Colors.red),
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
            ListTile(
              leading: const Icon(Icons.cancel),
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
    if (_currentUserId == null || (_recipientId == null && _groupId == null)) {
      return Scaffold(
        body: Center(
          child: Text('Invalid chat session', style: AppTheme.body),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_name ?? 'Chat', style: AppTheme.headline.copyWith(fontSize: 20, color: Colors.white)),
        backgroundColor: AppTheme.primaryColor,
        elevation: 2,
        actions: [
          IconButton(
            icon: const Icon(Icons.person, color: Colors.white),
            onPressed: () {
              Navigator.pushNamed(context, '/profile', arguments: {
                'entityId': _isGroup ? _groupId : _recipientId,
                'isGroup': _isGroup,
              });
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/pattern.png'), 
            fit: BoxFit.cover,
            opacity: 0.1, // Make it subtle
          ),
          color: Color(0xFFE5DDD5), 
        ),
        child: Column(
          children: [
            Expanded(
              child: Container(
                // Custom pattern overlay (if not using image)
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  image: DecorationImage(
                    image: _createPatternImage(),
                    repeat: ImageRepeat.repeat,
                    opacity: 0.05,
                  ),
                ),
                child: StreamBuilder<DatabaseEvent>(
                  stream: _database.child(_isGroup ? 'groups/$_chatId/messages' : 'chats/$_chatId/messages').onValue,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Error loading messages', style: AppTheme.body));
                    }
                    if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No messages yet',
                              style: AppTheme.body.copyWith(
                                color: Colors.grey[600],
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Start a conversation!',
                              style: AppTheme.body.copyWith(
                                color: Colors.grey[500],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    final messages = Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map)
                        .entries
                        .map((e) => {
                              'key': e.key,
                              ...Map<String, dynamic>.from(e.value as Map),
                            })
                        .toList()
                      ..sort((a, b) {
                        final aTimestamp = a['timestamp'] as int?;
                        final bTimestamp = b['timestamp'] as int?;
                        return (aTimestamp ?? 0).compareTo(bTimestamp ?? 0);
                      });

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16.0),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        final messageId = message['key'];
                        final isSentByMe = message['senderId'] == _currentUserId;
                        final isDeleted = message['deleted'] == true;
                        final isDeletedForMe = message['deletedFor'] != null &&
                            (message['deletedFor'] as Map).containsKey(_currentUserId) &&
                            message['deletedFor'][_currentUserId] == true;
                        final timestamp = message['timestamp'] as int?;
                        final time = timestamp != null
                            ? DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal()
                            : DateTime.now();
                        final formattedTime = '${time.hour}:${time.minute.toString().padLeft(2, '0')}';
                        final status = message['status']?.toString() ?? 'sent';

                        if (isDeleted || isDeletedForMe) {
                          return Align(
                            alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4.0),
                              padding: const EdgeInsets.all(12.0),
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(12.0),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 2,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Text(
                                'This message was deleted',
                                style: AppTheme.body.copyWith(
                                  color: Colors.black54,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          );
                        }

                        return GestureDetector(
                          onLongPress: () => _showDeleteOptions(messageId, isSentByMe),
                          child: Align(
                            alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4.0),
                              padding: const EdgeInsets.all(12.0),
                              decoration: BoxDecoration(
                                color: isSentByMe ? const Color(0xFFDCF8C6) : Colors.white, // WhatsApp colors
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(12.0),
                                  topRight: const Radius.circular(12.0),
                                  bottomLeft: Radius.circular(isSentByMe ? 12.0 : 4.0),
                                  bottomRight: Radius.circular(isSentByMe ? 4.0 : 12.0),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 3,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: isSentByMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  if (_isGroup && !isSentByMe)
                                    Text(
                                      message['senderUsername'] ?? 'Unknown',
                                      style: AppTheme.body.copyWith(
                                        fontSize: 12,
                                        color: AppTheme.primaryColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  Text(
                                    message['text'] ?? '',
                                    style: AppTheme.body.copyWith(
                                      color: Colors.black87,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4.0),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        formattedTime,
                                        style: AppTheme.body.copyWith(
                                          fontSize: 10,
                                          color: Colors.black54,
                                        ),
                                      ),
                                      if (isSentByMe)
                                        Padding(
                                          padding: const EdgeInsets.only(left: 4.0),
                                          child: Icon(
                                            status == 'seen' ? Icons.done_all : Icons.done,
                                            size: 12,
                                            color: status == 'seen' ? Colors.blue : Colors.grey,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            if (_chatId != null)
              StreamBuilder<DatabaseEvent>(
                stream:_database.child(_isGroup ? 'groups/$_chatId/typing' : 'chats/$_chatId/typing').onValue,
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
                    final typingData = Map<String, dynamic>.from(snapshot.data!.snapshot.value as Map);
                    final anyTyping = typingData.entries.any((entry) =>
                        (entry.value as Map)['isTyping'] == true && entry.key != _currentUserId);
                    if (anyTyping) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                        child: Row(
                          children: const [
                            SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                            ),
                            SizedBox(width: 8),
                            Text('Typing...', style: TextStyle(color: AppTheme.primaryColor)),
                          ],
                        ),
                      );
                    }
                  }
                  return const SizedBox.shrink();
                },
              ),
            Container(
              padding: const EdgeInsets.all(8.0),
              color: Colors.white.withOpacity(0.9),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24.0),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _messageController,
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                        ),
                        style: AppTheme.body,
                        maxLines: null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  FloatingActionButton(
                    mini: true,
                    onPressed: () {
                      if (_isGroup && _groupId != null) {
                        _sendMessage(_groupId!, _name!);
                      } else if (_recipientId != null) {
                        _sendMessage(_recipientId!, _name!);
                      }
                    },
                    backgroundColor: AppTheme.primaryColor,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Create a custom pattern for the background
  ImageProvider _createPatternImage() {
    return const AssetImage('assets/images/pattern.png'); // You can create a subtle pattern image
    // Alternatively, you can use a network image or create a custom painter
  }
}

// Custom Painter for creating patterns (Alternative approach)
class ChatBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withOpacity(0.05)
      ..strokeWidth = 1;

    // Create a subtle dot pattern
    for (double x = 0; x < size.width; x += 20) {
      for (double y = 0; y < size.height; y += 20) {
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}