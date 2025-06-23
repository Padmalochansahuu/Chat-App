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

  // Convert to JSON for Firestore
  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'username': username,
      'email': email,
      'photoUrl': photoUrl,
      'isOnline': isOnline,
      'lastSeen': lastSeen != null ? Timestamp.fromDate(lastSeen!) : null,
      'lastMessage': lastMessage,
    };
  }

  // Create from Firestore document
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      uid: json['uid'] as String,
      username: json['username'] as String,
      email: json['email'] as String,
      photoUrl: json['photoUrl'] as String?,
      isOnline: json['isOnline'] as bool? ?? false,
      lastSeen: (json['lastSeen'] as Timestamp?)?.toDate(),
      lastMessage: json['lastMessage'] as String? ?? 'No messages yet',
    );
  }
}