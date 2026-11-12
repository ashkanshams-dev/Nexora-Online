// Pick an image from the gallery, resize/compress it on device and upload it to Supabase Storage.
import * as ImagePicker from 'expo-image-picker';
import { ImageManipulator, SaveFormat } from 'expo-image-manipulator';
import { supabase } from './supabase';

const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
function b64ToBytes(b64: string) {
  const clean = b64.replace(/[^A-Za-z0-9+/]/g, '');
  const out = new Uint8Array(Math.floor(clean.length * 3 / 4));
  let o = 0;
  for (let i = 0; i < clean.length; i += 4) {
    const a = B64.indexOf(clean[i]), b = B64.indexOf(clean[i + 1]), c = B64.indexOf(clean[i + 2]), d = B64.indexOf(clean[i + 3]);
    out[o++] = (a << 2) | (b >> 4);
    if (c >= 0 && o < out.length) out[o++] = ((b & 15) << 4) | (c >> 2);
    if (d >= 0 && o < out.length) out[o++] = ((c & 3) << 6) | d;
  }
  return out.subarray(0, o);
}

export type UploadResult = { ok: true; url: string } | { ok: false; error: string; cancelled?: boolean };

export async function pickAndUpload(bucket: 'avatars' | 'chat', uid: string, opts: { size: number; square?: boolean }): Promise<UploadResult> {
  try {
    const perm = await ImagePicker.requestMediaLibraryPermissionsAsync();
    if (!perm.granted) return { ok: false, error: 'برای انتخاب عکس اجازه‌ی دسترسی به گالری لازم است' };
    const res = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], allowsEditing: !!opts.square, aspect: opts.square ? [1, 1] : undefined, quality: 1 });
    if (res.canceled || !res.assets?.[0]) return { ok: false, error: '', cancelled: true };
    const a = res.assets[0];
    const ctx = ImageManipulator.manipulate(a.uri);
    if ((a.width || 0) > opts.size || (a.height || 0) > opts.size) {
      if ((a.width || 0) >= (a.height || 0)) ctx.resize({ width: opts.size }); else ctx.resize({ height: opts.size });
    }
    const img = await ctx.renderAsync();
    const saved = await img.saveAsync({ compress: .82, format: SaveFormat.JPEG, base64: true });
    if (!saved.base64) return { ok: false, error: 'پردازش عکس ناموفق بود' };
    const path = `${uid}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.jpg`;
    const { error } = await supabase.storage.from(bucket).upload(path, b64ToBytes(saved.base64), { contentType: 'image/jpeg', upsert: false });
    if (error) return { ok: false, error: 'آپلود عکس ناموفق بود' };
    const { data } = supabase.storage.from(bucket).getPublicUrl(path);
    return { ok: true, url: data.publicUrl };
  } catch {
    return { ok: false, error: 'انتخاب یا آپلود عکس ناموفق بود' };
  }
}
