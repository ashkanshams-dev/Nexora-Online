import 'dart:async';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SocialProfile {
  const SocialProfile({required this.id, required this.username, this.avatarUrl, this.displayName = '', this.bio = '', this.website = '', this.location = '', this.isPrivate = false, this.followers = 0, this.following = 0, this.posts = 0, this.isFollowing = false, this.isPending = false});
  final String id;
  final String username;
  final String? avatarUrl;
  final String displayName;
  final String bio;
  final String website;
  final String location;
  final bool isPrivate;
  final int followers;
  final int following;
  final int posts;
  final bool isFollowing;
  final bool isPending;

  factory SocialProfile.fromJson(Map<String, dynamic> j) => SocialProfile(
    id: '${j['id']}', username: '${j['username'] ?? ''}', avatarUrl: j['avatar_url'] as String?,
    displayName: '${j['display_name'] ?? ''}', bio: '${j['bio'] ?? ''}', website: '${j['website'] ?? ''}', location: '${j['location'] ?? ''}',
    isPrivate: j['is_private'] == true, followers: (j['followers'] as num?)?.toInt() ?? 0, following: (j['following'] as num?)?.toInt() ?? 0,
    posts: (j['posts'] as num?)?.toInt() ?? 0, isFollowing: j['is_following'] == true, isPending: j['is_pending'] == true,
  );
}

class SocialMessage {
  const SocialMessage({required this.id, required this.author, required this.text, required this.createdAt, this.read = false});
  final String id;
  final String author;
  final String text;
  final DateTime createdAt;
  final bool read;

  factory SocialMessage.fromJson(Map<String, dynamic> j) => SocialMessage(
    id: '${j['id']}', author: '${j['author'] ?? ''}', text: '${j['text'] ?? ''}',
    createdAt: DateTime.tryParse('${j['created_at'] ?? ''}')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
    read: j['read'] == true,
  );
}

class SocialProfileRepository {
  SocialProfileRepository(this.client);
  final SupabaseClient client;
  static const String avatarBucket = 'nx-media';
  String get me => client.auth.currentUser!.id;

  Future<SocialProfile> profile(String userId) async {
    final dynamic row = await client.rpc('nx_social_profile', params: <String, dynamic>{'p_user': userId});
    return SocialProfile.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<SocialProfile> updateProfile({required String username, String displayName = '', String bio = '', String website = '', String location = '', String? avatarUrl}) async {
    final dynamic row = await client.rpc('nx_social_update_profile', params: <String, dynamic>{
      'p_display_name': displayName, 'p_username': username, 'p_bio': bio, 'p_website': website, 'p_location': location, 'p_avatar_url': avatarUrl,
    });
    return SocialProfile.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<SocialProfile> toggleFollow(String targetId, {required bool follow}) async {
    final dynamic row = await client.rpc('nx_social_toggle_follow', params: <String, dynamic>{'p_target': targetId, 'p_follow': follow});
    return SocialProfile.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<SocialProfile> uploadAvatar(XFile file) async {
    final String name = file.name.toLowerCase();
    final String ext = name.endsWith('.png') ? 'png' : name.endsWith('.webp') ? 'webp' : 'jpg';
    final String mime = ext == 'png' ? 'image/png' : ext == 'webp' ? 'image/webp' : 'image/jpeg';
    final Uint8List bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > 5 * 1024 * 1024) throw const FormatException('avatar_too_large');
    final String path = '$me/avatar.$ext';
    await client.storage.from(avatarBucket).uploadBinary(path, bytes, fileOptions: FileOptions(contentType: mime, upsert: true));
    final String url = '${client.storage.from(avatarBucket).getPublicUrl(path)}?v=${DateTime.now().millisecondsSinceEpoch}';
    final SocialProfile current = await profile(me);
    return updateProfile(username: current.username, displayName: current.displayName, bio: current.bio, website: current.website, location: current.location, avatarUrl: url);
  }

  Future<SocialProfile> deleteAvatar() async {
    final SocialProfile current = await profile(me);
    for (final String ext in <String>['jpg', 'jpeg', 'png', 'webp']) {
      try { await client.storage.from(avatarBucket).remove(<String>['$me/avatar.$ext']); } catch (_) {}
    }
    return updateProfile(username: current.username, displayName: current.displayName, bio: current.bio, website: current.website, location: current.location, avatarUrl: null);
  }

  Future<String> openDirect(String targetId) async => '${await client.rpc('nx_open_direct', params: <String, dynamic>{'p_user': targetId})}';

  Future<SocialMessage> sendMessage(String chatId, String text) async {
    final dynamic row = await client.rpc('nx_send_message', params: <String, dynamic>{'p_chat': chatId, 'p_kind': 'text', 'p_text': text.trim(), 'p_payload': <String, dynamic>{}});
    return SocialMessage.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<List<SocialMessage>> messages(String chatId, {int limit = 100}) async {
    final int take = limit < 1 ? 1 : (limit > 100 ? 100 : limit);
    final List<dynamic> rows = await client.from('nx_messages').select('id, author, text, created_at, payload').eq('chat_id', chatId).eq('deleted', false).order('created_at').limit(take);
    return rows.map((dynamic e) => SocialMessage.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  Stream<List<SocialMessage>> messageStream(String chatId) {
    return client.from('nx_messages').stream(primaryKey: <String>['id']).eq('chat_id', chatId).order('created_at').map((List<Map<String, dynamic>> rows) => rows.where((Map<String, dynamic> r) => r['deleted'] != true).map(SocialMessage.fromJson).toList());
  }
}
