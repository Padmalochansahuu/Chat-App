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
        await _clearSession(); // Clear session to prevent auto-login
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

  // Future<bool> checkEmailExists(String email) async {
  //   try {
  //     final normalizedEmail = _normalizeEmail(email);
  //     print('Checking if email exists: $normalizedEmail');
  //     if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(normalizedEmail)) {
  //       print('Invalid email format: $normalizedEmail');
  //       throw FirebaseAuthException(
  //         code: 'invalid-email',
  //         message: 'The email address is badly formatted.',
  //       );
  //     }
  //     final signInMethods = await _auth.fetchSignInMethodsForEmail(normalizedEmail);
  //     print('Sign-in methods for $normalizedEmail: $signInMethods');
  //     return signInMethods.isNotEmpty;
  //   } catch (e) {
  //     print('Error checking email: $e');
  //     // Handle specific Firebase errors
  //     if (e is FirebaseAuthException && e.code == 'invalid-email') {
  //       throw e; // Rethrow invalid email errors
  //     }
  //     // For other errors (e.g., network issues), assume email might exist to avoid false negatives
  //     return true;
  //   }
  // }

  // Future<void> sendPasswordResetEmail(String email) async {
  //   try {
  //     final normalizedEmail = _normalizeEmail(email);
  //     print('Initiating password reset for email: $normalizedEmail');
  //     if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(normalizedEmail)) {
  //       throw FirebaseAuthException(
  //         code: 'invalid-email',
  //         message: 'Please enter a valid email address.',
  //       );
  //     }
  //     await _auth.sendPasswordResetEmail(email: normalizedEmail);
  //     print('Password reset email sent successfully to: $normalizedEmail');
  //   } catch (e) {
  //     print('Error sending password reset email: $e');
  //     // Handle specific Firebase errors
  //     if (e is FirebaseAuthException) {
  //       if (e.code == 'user-not-found') {
  //         throw FirebaseAuthException(
  //           code: 'user-not-found',
  //           message: 'No account found with this email address.',
  //         );
  //       } else if (e.code == 'invalid-email') {
  //         throw e;
  //       }
  //     }
  //     // For other errors, throw a generic error
  //     throw FirebaseAuthException(
  //       code: 'unknown-error',
  //       message: 'Unable to send password reset email. Please try again.',
  //     );
  //   }
  // }

// Updated methods in auth_services.dart

Future<bool> checkEmailExists(String email) async {
  try {
    final normalizedEmail = _normalizeEmail(email);
    print('Checking if email exists: $normalizedEmail');
    
    // Validate email format first
    if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(normalizedEmail)) {
      print('Invalid email format: $normalizedEmail');
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'The email address is badly formatted.',
      );
    }

    // Try to fetch sign-in methods
    final signInMethods = await _auth.fetchSignInMethodsForEmail(normalizedEmail);
    print('Sign-in methods for $normalizedEmail: $signInMethods');
    
    // If we get sign-in methods, the email definitely exists
    if (signInMethods.isNotEmpty) {
      print('Email exists - found sign-in methods: $signInMethods');
      return true;
    }
    
    // If empty array, try checking Firestore as backup
    // This helps catch cases where fetchSignInMethodsForEmail fails
    try {
      final userQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();
      
      if (userQuery.docs.isNotEmpty) {
        print('Email found in Firestore: $normalizedEmail');
        return true;
      }
    } catch (firestoreError) {
      print('Firestore check failed: $firestoreError');
      // Continue with the original result if Firestore check fails
    }
    
    print('Email not found: $normalizedEmail');
    return false;
    
  } catch (e) {
    print('Error checking email: $e');
    
    // Handle specific Firebase errors
    if (e is FirebaseAuthException) {
      if (e.code == 'invalid-email') {
        throw e; // Rethrow invalid email errors
      }
      // For other Firebase Auth errors, we'll be conservative and assume email exists
      // to avoid false negatives due to network issues or other temporary problems
      print('Firebase Auth error occurred, assuming email exists to be safe: ${e.code}');
      return true;
    }
    
    // For other errors (e.g., network issues), assume email might exist to avoid false negatives
    print('Unknown error occurred, assuming email exists to be safe');
    return true;
  }
}

// Alternative approach: Direct password reset with better error handling
Future<void> sendPasswordResetEmail(String email) async {
  try {
    final normalizedEmail = _normalizeEmail(email);
    print('Initiating password reset for email: $normalizedEmail');
    
    // Validate email format first
    if (!RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(normalizedEmail)) {
      throw FirebaseAuthException(
        code: 'invalid-email',
        message: 'Please enter a valid email address.',
      );
    }
    
    // Try to send password reset email directly
    // Firebase will handle the user existence check internally
    print('Sending password reset email to: $normalizedEmail');
    await _auth.sendPasswordResetEmail(email: normalizedEmail);
    print('Password reset email request processed for: $normalizedEmail');
    
    // Note: Firebase may not actually send an email if the user doesn't exist,
    // but it won't throw an error for security reasons
    
  } catch (e) {
    print('Error sending password reset email: $e');
    
    // Handle specific Firebase errors
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'user-not-found':
          // This error is rare with sendPasswordResetEmail, but handle it
          throw FirebaseAuthException(
            code: 'user-not-found',
            message: 'No account found with this email address.',
          );
        case 'invalid-email':
          throw e;
        case 'too-many-requests':
          throw FirebaseAuthException(
            code: 'too-many-requests',
            message: 'Too many requests. Please try again later.',
          );
        case 'network-request-failed':
          throw FirebaseAuthException(
            code: 'network-request-failed',
            message: 'Network error. Please check your connection.',
          );
        default:
          throw FirebaseAuthException(
            code: 'unknown-error',
            message: 'Unable to send password reset email. Please try again.',
          );
      }
    }
    
    // For other errors, throw a generic error
    throw FirebaseAuthException(
      code: 'unknown-error',
      message: 'Unable to send password reset email. Please try again.',
    );
  }
}

// Alternative: Enhanced email verification with multiple checks
Future<bool> verifyEmailExistsComprehensive(String email) async {
  try {
    final normalizedEmail = _normalizeEmail(email);
    print('Comprehensive email verification for: $normalizedEmail');
    
    // Step 1: Check Firebase Auth
    try {
      final signInMethods = await _auth.fetchSignInMethodsForEmail(normalizedEmail);
      if (signInMethods.isNotEmpty) {
        print('Email verified via Firebase Auth: $normalizedEmail');
        return true;
      }
    } catch (authError) {
      print('Firebase Auth check failed: $authError');
    }
    
    // Step 2: Check Firestore users collection
    try {
      final userQuery = await _firestore
          .collection('users')
          .where('email', isEqualTo: normalizedEmail)
          .limit(1)
          .get();
      
      if (userQuery.docs.isNotEmpty) {
        print('Email verified via Firestore: $normalizedEmail');
        return true;
      }
    } catch (firestoreError) {
      print('Firestore check failed: $firestoreError');
    }
    
    // Step 3: Try a different approach - attempt to create account with existing email
    // This will throw an error if email already exists
    try {
      // Create a temporary password for testing
      const tempPassword = 'TempPassword123!@#';
      await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: tempPassword,
      );
      
      // If we reach here, the email was available (didn't exist)
      // Delete the temporary account we just created
      final currentUser = _auth.currentUser;
      if (currentUser != null) {
        await currentUser.delete();
        print('Temporary account deleted');
      }
      
      print('Email is available (does not exist): $normalizedEmail');
      return false;
      
    } catch (createError) {
      if (createError is FirebaseAuthException && 
          createError.code == 'email-already-in-use') {
        print('Email verified via creation attempt: $normalizedEmail');
        return true;
      }
      print('Account creation test failed: $createError');
    }
    
    print('Could not definitively verify email existence: $normalizedEmail');
    return false;
    
  } catch (e) {
    print('Comprehensive email verification failed: $e');
    // Return true to be conservative - better to attempt reset than block valid users
    return true;
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

  Future<void> deleteMessageForMe(String chatId, String messageId, bool isGroup) async {
    if (!await isAuthenticated()) return;

    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      final messageRef = _database.child(isGroup ? 'groups/$chatId/messages/$messageId' : 'chats/$chatId/messages/$messageId');
      await messageRef.update({
        'deletedFor.${currentUser.uid}': true,
      });
      print('Message $messageId deleted for user ${currentUser.uid} in ${isGroup ? 'group' : 'chat'} $chatId');
    } catch (e) {
      print('Error deleting message for me: $e');
      if (e.toString().contains('permission_denied')) {
        await refreshToken();
      }
      rethrow;
    }
  }

  Future<void> deleteMessageForEveryone(String chatId, String messageId, bool isGroup) async {
    if (!await isAuthenticated()) return;

    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    try {
      final messageRef = _database.child(isGroup ? 'groups/$chatId/messages/$messageId' : 'chats/$chatId/messages/$messageId');
      final snapshot = await messageRef.once();
      if (snapshot.snapshot.value != null) {
        final messageData = Map<String, dynamic>.from(snapshot.snapshot.value as Map);
        if (messageData['senderId'] != currentUser.uid) {
          throw Exception('Only the sender can delete this message for everyone');
        }
        await messageRef.update({
          'deleted': true,
          'text': 'This message was deleted',
        });

        // Update lastMessage if this was the most recent message
        final messagesRef = _database.child(isGroup ? 'groups/$chatId/messages' : 'chats/$chatId/messages');
        final query = messagesRef.orderByChild('timestamp').limitToLast(1);
        final latestSnapshot = await query.once();
        if (latestSnapshot.snapshot.value != null) {
          final latestMessages = Map<String, dynamic>.from(latestSnapshot.snapshot.value as Map);
          if (latestMessages.containsKey(messageId)) {
            await _database.child(isGroup ? 'groups/$chatId' : 'chats/$chatId').update({
              'lastMessage': 'This message was deleted',
              'lastUpdated': ServerValue.timestamp,
            });
          }
        }

        print('Message $messageId deleted for everyone in ${isGroup ? 'group' : 'chat'} $chatId');
      }
    } catch (e) {
      print('Error deleting message for everyone: $e');
      if (e.toString().contains('permission_denied')) {
        await refreshToken();
      }
      rethrow;
    }
  }

  void dispose() {
    _stopTokenRefreshTimer();
    _stopPresenceMonitoring();
    _authStateSubscription?.cancel();
  }
}