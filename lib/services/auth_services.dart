
import 'package:chatapp/model/user_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final DatabaseReference _database = FirebaseDatabase.instance.ref();

  Timer? _tokenRefreshTimer;
  Timer? _presenceTimer;
  StreamSubscription<User?>? _authStateSubscription;
  StreamSubscription<DatabaseEvent>? _connectedSubscription;

  FirebaseFirestore get firestore => _firestore;

  String _normalizeEmail(String email) {
    return email.trim().toLowerCase();
  }

  void initialize() {
    _startTokenRefreshTimer();
    _listenToAuthStateChanges();
  }

  void _listenToAuthStateChanges() {
    _authStateSubscription = _auth.authStateChanges().listen((User? user) async {
      if (user != null) {
        await refreshToken();
        _startPresenceMonitoring();
      } else {
        await updatePresence(false);
        _stopTokenRefreshTimer();
        _stopPresenceMonitoring();
      }
    });
  }

  void _startTokenRefreshTimer() {
    _stopTokenRefreshTimer();
    _tokenRefreshTimer = Timer.periodic(const Duration(minutes: 45), (timer) {
      refreshToken();
    });
  }

  void _stopTokenRefreshTimer() {
    _tokenRefreshTimer?.cancel();
    _tokenRefreshTimer = null;
  }

  void _startPresenceMonitoring() {
    _stopPresenceMonitoring();
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final presenceRef = _database.child('presence/${currentUser.uid}');
    final connectedRef = _database.child('.info/connected');

    _connectedSubscription = connectedRef.onValue.listen((event) async {
      if (event.snapshot.value == true) {
        try {
          await presenceRef.set({
            'isOnline': true,
            'lastSeen': ServerValue.timestamp,
            'username': currentUser.displayName ?? 'Unknown',
          });
          await presenceRef.onDisconnect().set({
            'isOnline': false,
            'lastSeen': ServerValue.timestamp,
            'username': currentUser.displayName ?? 'Unknown',
          });
          await _firestore.collection('users').doc(currentUser.uid).update({
            'isOnline': true,
            'lastSeen': Timestamp.now(),
          });
        } catch (e) {
          print('Presence connection error: $e');
          if (e.toString().contains('permission_denied')) {
            await refreshToken();
            try {
              await presenceRef.set({
                'isOnline': true,
                'lastSeen': ServerValue.timestamp,
                'username': currentUser.displayName ?? 'Unknown',
              });
              await presenceRef.onDisconnect().set({
                'isOnline': false,
                'lastSeen': ServerValue.timestamp,
                'username': currentUser.displayName ?? 'Unknown',
              });
            } catch (retryError) {
              print('Retry presence update failed: $retryError');
            }
          }
        }
      }
    }, onError: (error) {
      print('Connected subscription error: $error');
    });

    _presenceTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      try {
        if (await isAuthenticated()) {
          await presenceRef.update({
            'isOnline': true,
            'lastSeen': ServerValue.timestamp,
          });
          await _firestore.collection('users').doc(currentUser.uid).update({
            'isOnline': true,
            'lastSeen': Timestamp.now(),
          });
        }
      } catch (e) {
        print('Presence timer error: $e');
        if (e.toString().contains('permission_denied')) {
          await refreshToken();
        }
      }
    });
  }

  void _stopPresenceMonitoring() {
    _presenceTimer?.cancel();
    _presenceTimer = null;
    _connectedSubscription?.cancel();
    _connectedSubscription = null;
  }

  Future<UserModel?> checkSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');
    final currentUser = _auth.currentUser;

    if (userId != null && currentUser != null) {
      try {
        await currentUser.getIdToken(true);
        print('Session check: User found with ID: $userId');
        await updatePresence(true);
        return UserModel.fromFirebaseUser(currentUser);
      } catch (e) {
        print('Session check: Token refresh failed: $e');
        await _clearSession();
        return null;
      }
    }
    print('Session check: No user found');
    return null;
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userId');
    await prefs.remove('photoUrl');
  }

  Future<UserModel?> register(String username, String email, String password) async {
    try {
      final normalizedEmail = _normalizeEmail(email);
      print('Registering user with email: $normalizedEmail');
      final credential = await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      await credential.user?.updateDisplayName(username);
      if (credential.user != null) {
        final userModel = UserModel(
          uid: credential.user!.uid,
          username: username,
          email: normalizedEmail,
          photoUrl: null,
          isOnline: true,
          lastSeen: DateTime.now(),
          lastMessage: 'No messages yet',
        );
        await _firestore.collection('users').doc(credential.user!.uid).set(userModel.toJson());
        await updatePresence(true);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('userId', credential.user!.uid);
        print('Registration successful for user: ${credential.user!.uid}');
        return userModel;
      }
      return null;
    } catch (e) {
      print('Registration error: $e');
      rethrow;
    }
  }

  Future<UserModel?> login(String email, String password) async {
    try {
      final normalizedEmail = _normalizeEmail(email);
      print('Logging in with email: $normalizedEmail');
      final credential = await _auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );

      if (credential.user != null) {
        await credential.user!.getIdToken(true);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('userId', credential.user!.uid);
        await updatePresence(true);
        _startPresenceMonitoring();
        print('Login successful for user: ${credential.user!.uid}');
        return UserModel.fromFirebaseUser(credential.user!);
      }
      return null;
    } catch (e) {
      print('Login error: $e');
      rethrow;
    }
  }

  Future<bool> checkEmailExists(String email) async {
    try {
      final normalizedEmail = _normalizeEmail(email);
      print('Checking if email exists: $normalizedEmail');
      if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(normalizedEmail)) {
        print('Invalid email format: $normalizedEmail');
        throw FirebaseAuthException(
          code: 'invalid-email',
          message: 'The email address is badly formatted.',
        );
      }
      final signInMethods = await _auth.fetchSignInMethodsForEmail(normalizedEmail);
      print('Sign-in methods for $normalizedEmail: $signInMethods');
      return signInMethods.isNotEmpty;
    } catch (e) {
      print('Error checking email: $e');
      throw FirebaseAuthException(
        code: 'unknown-error',
        message: 'Unable to verify email. Please try again.',
      );
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    try {
      final normalizedEmail = _normalizeEmail(email);
      print('Initiating password reset for email: $normalizedEmail');
      if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(normalizedEmail)) {
        throw FirebaseAuthException(
          code: 'invalid-email',
          message: 'Please enter a valid email address.',
        );
      }
      final emailExists = await checkEmailExists(normalizedEmail);
      if (!emailExists) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'No account found with this email address.',
        );
      }
      await _auth.sendPasswordResetEmail(email: normalizedEmail);
      print('Password reset email sent successfully to: $normalizedEmail');
    } catch (e) {
      print('Error sending password reset email: $e');
      rethrow;
    }
  }

  Future<void> updatePresence(bool isOnline) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      await currentUser.getIdToken(true);
      final timestamp = Timestamp.now();
      final serverTimestamp = ServerValue.timestamp;

      await _firestore.collection('users').doc(currentUser.uid).update({
        'isOnline': isOnline,
        'lastSeen': timestamp,
      });

      final presenceRef = _database.child('presence/${currentUser.uid}');
      await presenceRef.update({
        'isOnline': isOnline,
        'lastSeen': serverTimestamp,
        'username': currentUser.displayName ?? 'Unknown',
      });

      if (isOnline) {
        await presenceRef.onDisconnect().update({
          'isOnline': false,
          'lastSeen': serverTimestamp,
        });
      }

      print('Presence updated: $isOnline for user: ${currentUser.uid}');
    } catch (e) {
      print('Error updating presence: $e');
      if (isOnline && e.toString().contains('permission_denied')) {
        await refreshToken();
        try {
          await _firestore.collection('users').doc(currentUser.uid).update({
            'isOnline': isOnline,
            'lastSeen': Timestamp.now(),
          });
          await _database.child('presence/${currentUser.uid}').update({
            'isOnline': isOnline,
            'lastSeen': ServerValue.timestamp,
            'username': currentUser.displayName ?? 'Unknown',
          });
        } catch (retryError) {
          print('Retry presence update failed: $retryError');
        }
      }
    }
  }

  Future<void> updateTypingStatus(String chatId, bool isTyping) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || chatId.isEmpty) return;

    if (!await refreshToken()) {
      print('Auth token refresh failed. Aborting typing status update.');
      return;
    }

    try {
      final typingRef = _database.child('chats/$chatId/typing/${currentUser.uid}');
      if (isTyping) {
        await typingRef.set({
          'isTyping': true,
          'timestamp': ServerValue.timestamp,
          'username': currentUser.displayName ?? 'Unknown',
        });
      } else {
        await typingRef.remove();
      }
      print('Typing status updated: $isTyping for chat: $chatId');
    } catch (e) {
      print('Error updating typing status: $e');
      if (e.toString().contains('permission_denied')) {
        await refreshToken();
      }
    }
  }

  Future<String?> createGroup(String groupName, List<String> memberIds) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null || groupName.isEmpty || memberIds.isEmpty) return null;

    if (!await refreshToken()) {
      print('Auth token refresh failed. Aborting group creation.');
      return null;
    }

    try {
      final groupId = _database.child('groups').push().key;
      if (groupId == null) throw Exception('Failed to generate group ID');

      final members = {for (var uid in [currentUser.uid, ...memberIds]) uid: true};
      await _database.child('groups/$groupId').set({
        'name': groupName,
        'members': members,
        'createdBy': currentUser.uid,
        'createdAt': ServerValue.timestamp,
        'lastMessage': 'Group created',
        'lastUpdated': ServerValue.timestamp,
      });

      await _database.child('groups/$groupId/messages').set({});
      print('Group created with ID: $groupId');
      return groupId;
    } catch (e) {
      print('Error creating group: $e');
      if (e.toString().contains('permission_denied')) {
        await refreshToken();
        return null;
      }
      return null;
    }
  }

  Future<void> updateUserProfile(String username, String? photoUrl, String? status) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      await refreshToken();
      final updateData = <String, dynamic>{
        'lastSeen': Timestamp.now(),
      };
      if (username.isNotEmpty) {
        await currentUser.updateDisplayName(username);
        updateData['username'] = username;
      }
      if (photoUrl != null) updateData['photoUrl'] = photoUrl;
      if (status != null) updateData['status'] = status;

      await _firestore.collection('users').doc(currentUser.uid).update(updateData);
      await _database.child('presence/${currentUser.uid}').update({
        'username': username.isNotEmpty ? username : currentUser.displayName ?? 'Unknown',
      });
      print('User profile updated for user: ${currentUser.uid}');
    } catch (e) {
      print('Error updating user profile: $e');
      if (e.toString().contains('permission_denied')) {
        await refreshToken();
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    print('Logging out user');
    final currentUser = _auth.currentUser;

    if (currentUser != null) {
      try {
        final userChatsSnapshot = await _database.child('chats').once();
        if (userChatsSnapshot.snapshot.value != null) {
          final chats = Map<String, dynamic>.from(userChatsSnapshot.snapshot.value as Map);
          final updates = <String, dynamic>{};

          for (var chatEntry in chats.entries) {
            final chatId = chatEntry.key;
            updates['chats/$chatId/typing/${currentUser.uid}'] = null;
          }

          if (updates.isNotEmpty) {
            await _database.update(updates);
            print('Cleared typing status for user: ${currentUser.uid}');
          }
        }
      } catch (e) {
        print('Error clearing typing status: $e');
      }

      await updatePresence(false);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userId');
    await prefs.remove('photoUrl');

    _stopTokenRefreshTimer();
    _stopPresenceMonitoring();

    await _auth.signOut();
    print('Logout successful');
  }

  User? getCurrentUser() {
    return _auth.currentUser;
  }

  Future<bool> isAuthenticated() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return false;

    try {
      await currentUser.getIdToken(true);
      return true;
    } catch (e) {
      print('Authentication check failed: $e');
      return false;
    }
  }

  Future<bool> refreshToken() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return false;

    try {
      await currentUser.getIdToken(true);
      print('Token refreshed successfully');
      return true;
    } catch (e) {
      print('Token refresh failed: $e');
      return false;
    }
  }

  Stream<bool> getUserOnlineStatus(String userId) {
    return _database.child('presence/$userId/isOnline').onValue.asBroadcastStream().map((event) {
      return event.snapshot.value == true;
    });
  }

  Stream<Map<String, dynamic>?> getTypingStatus(String chatId, String userId) {
    return _database.child('chats/$chatId/typing/$userId').onValue.asBroadcastStream().map((event) {
      if (event.snapshot.value != null) {
        return Map<String, dynamic>.from(event.snapshot.value as Map);
      }
      return null;
    });
  }

  Future<void> updateMessageStatus(String chatId, String messageId, String status) async {
    if (!await isAuthenticated()) return;

    try {
      await _database.child('chats/$chatId/messages/$messageId/status').set(status);
      print('Message status updated: $messageId -> $status');
    } catch (e) {
      print('Error updating message status: $e');
      if (e.toString().contains('permission_denied')) {
        await refreshToken();
      }
    }
  }

  Future<void> markChatMessagesAsSeen(String chatId, String currentUserId) async {
  if (!await isAuthenticated()) return;

  try {
    final messagesRef = _database.child('chats/$chatId/messages');
    final query = messagesRef.orderByChild('recipientId').equalTo(currentUserId);
    final snapshot = await query.once();

    if (snapshot.snapshot.value != null) {
      final messages = Map<String, dynamic>.from(snapshot.snapshot.value as Map);
      final updates = <String, dynamic>{};

      for (var entry in messages.entries) {
        final messageData = Map<String, dynamic>.from(entry.value as Map);
        if (messageData['status'] != 'seen' && messageData['recipientId'] == currentUserId) {
          updates['chats/$chatId/messages/${entry.key}/status'] = 'seen';
        }
      }

      // Reset unread count
      updates['chats/$chatId/unread/$currentUserId'] = 0;

      if (updates.isNotEmpty) {
        await _database.update(updates);
        print('Marked ${updates.length ~/ 2} messages as seen and reset unread count in chat: $chatId');
      }
    }
  } catch (e) {
    print('Error marking messages as seen: $e');
    if (e.toString().contains('permission_denied')) {
      await refreshToken();
    }
  }
}

  Future<void> markGroupMessagesAsSeen(String groupId, String currentUserId) async {
    if (!await isAuthenticated()) return;

    try {
      final messagesRef = _database.child('groups/$groupId/messages');
      final snapshot = await messagesRef.once();

      if (snapshot.snapshot.value != null) {
        final messages = Map<String, dynamic>.from(snapshot.snapshot.value as Map);
        final updates = <String, dynamic>{};
        final groupRef = _database.child('groups/$groupId');
        final groupSnapshot = await groupRef.once();
        final groupData = Map<String, dynamic>.from(groupSnapshot.snapshot.value as Map);
        final members = Map<String, dynamic>.from(groupData['members'] as Map);
        final memberCount = members.length;

        for (var entry in messages.entries) {
          final messageId = entry.key;
          final messageData = Map<String, dynamic>.from(entry.value as Map);
          if (messageData['seenBy'] == null) {
            messageData['seenBy'] = {};
          }
          final seenBy = Map<String, dynamic>.from(messageData['seenBy'] as Map);

          if (!seenBy.containsKey(currentUserId)) {
            seenBy[currentUserId] = true;
            updates['groups/$groupId/messages/$messageId/seenBy'] = seenBy;

            if (seenBy.length == memberCount) {
              updates['groups/$groupId/messages/$messageId/status'] = 'seen';
            }
          }
        }

        if (updates.isNotEmpty) {
          await _database.update(updates);
          print('Marked messages as seen in group: $groupId');
        }
      }
    } catch (e) {
      print('Error marking group messages as seen: $e');
      if (e.toString().contains('permission_denied')) {
        await refreshToken();
      }
    }
  }

  Stream<Map<String, dynamic>?> getGroupData(String groupId) {
    return _database.child('groups/$groupId').onValue.asBroadcastStream().map((event) {
      if (event.snapshot.value != null) {
        return Map<String, dynamic>.from(event.snapshot.value as Map);
      }
      return null;
    });
  }

  Future<void> initializeChat(String chatId, String senderId, String recipientId) async {
    try {
      await _database.child('chats/$chatId/members').update({
        senderId: true,
        recipientId: true,
      });
      print('Chat initialized for $chatId');
    } catch (e) {
      print('Error initializing chat: $e');
      if (e.toString().contains('permission_denied')) {
        await refreshToken();
      }
    }
  }

  void dispose() {
    _stopTokenRefreshTimer();
    _stopPresenceMonitoring();
    _authStateSubscription?.cancel();
  }
}
