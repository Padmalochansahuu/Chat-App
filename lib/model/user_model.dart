import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UserModel {
  final String uid;
  final String username;
  final String email;
  final String? photoUrl;
  final bool isOnline;
  final DateTime? lastSeen;
  final String lastMessage;

  UserModel({
    required this.uid,
    required this.username,
    required this.email,
    this.photoUrl,
    required this.isOnline,
    this.lastSeen,
    required this.lastMessage,
  });

  // Create from Firebase User
  factory UserModel.fromFirebaseUser(User user) {
    return UserModel(
      uid: user.uid,
      username: user.displayName ?? 'Unknown',
      email: user.email ?? '',
      photoUrl: user.photoURL,
      isOnline: false,
      lastSeen: null,
      lastMessage: 'No messages yet',
    );
  }

  // Convert to JSON for Firestore - FIXED: Removed uid field
  Map<String, dynamic> toJson() {
    return {
      // 'uid': uid, // REMOVED - uid is stored as document ID
      'username': username,
      'email': email,
      'photoUrl': photoUrl,
      'isOnline': isOnline,
      'lastSeen': lastSeen != null ? Timestamp.fromDate(lastSeen!) : null,
      'lastMessage': lastMessage,
    };
  }

  // Create from Firestore document - FIXED: Get uid from document ID
  factory UserModel.fromJson(Map<String, dynamic> json, {String? docId}) {
    return UserModel(
      uid: docId ?? json['uid'] as String, // Use docId if provided, fallback to json['uid']
      username: json['username'] as String,
      email: json['email'] as String,
      photoUrl: json['photoUrl'] as String?,
      isOnline: json['isOnline'] as bool? ?? false,
      lastSeen: (json['lastSeen'] as Timestamp?)?.toDate(),
      lastMessage: json['lastMessage'] as String? ?? 'No messages yet',
    );
  }

  // NEW: Create from Firestore DocumentSnapshot
  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id, // Get uid from document ID
      username: data['username'] as String,
      email: data['email'] as String,
      photoUrl: data['photoUrl'] as String?,
      isOnline: data['isOnline'] as bool? ?? false,
      lastSeen: (data['lastSeen'] as Timestamp?)?.toDate(),
      lastMessage: data['lastMessage'] as String? ?? 'No messages yet',
    );
  }
}