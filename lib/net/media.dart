// Pick an image from the gallery (resized/compressed by the picker) and upload it to Supabase Storage — port of src/net/media.ts.
import 'dart:math' as math;

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase.dart';

typedef UploadResult = ({bool ok, String? url, String? error, bool cancelled});

Future<UploadResult> pickAndUpload(String bucket, String uid, {required double size, bool square = false}) async {
  try {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: size, maxHeight: size, imageQuality: 82, requestFullMetadata: false);
    if (x == null) return (ok: false, url: null, error: '', cancelled: true);
    final bytes = await x.readAsBytes();
    final path = '$uid/${DateTime.now().millisecondsSinceEpoch}-${math.Random().nextInt(1 << 30).toRadixString(36)}.jpg';
    await supabase.storage.from(bucket).uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false));
    return (ok: true, url: supabase.storage.from(bucket).getPublicUrl(path), error: null, cancelled: false);
  } on StorageException {
    return (ok: false, url: null, error: 'آپلود عکس ناموفق بود', cancelled: false);
  } catch (_) {
    return (ok: false, url: null, error: 'انتخاب یا آپلود عکس ناموفق بود', cancelled: false);
  }
}
