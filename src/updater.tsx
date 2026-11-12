// In-app updater (v8). On launch it asks GitHub for the latest release of this repo; every CI release
// carries "vc=<versionCode>" in its notes. When that is newer than the installed build, a sheet offers the
// update and downloads NEXORA.apk; Android then shows its own "Install / Update" screen (same signing key,
// so the game updates in place and keeps the player's data).
import React, { useEffect, useState } from 'react';
import { Linking, Platform, StyleSheet, View } from 'react-native';
import Constants from 'expo-constants';
import { C, G, faNum } from './ui/theme';
import { Btn, T } from './ui/kit';

const REPO = 'ashkanshams-dev/Nexora-Online';
const MY_VC = Number((Constants.expoConfig as any)?.android?.versionCode || 0);
const MY_VER = String(Constants.expoConfig?.version || '');

type Rel = { vc: number; ver: string; url: string; page: string; notes: string; mb: number };

export async function checkUpdate(): Promise<Rel | null> {
  if (Platform.OS !== 'android' || !MY_VC) return null;
  const ctl = new AbortController(); const to = setTimeout(() => ctl.abort(), 8000);
  try {
    const r = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, { headers: { Accept: 'application/vnd.github+json' }, signal: ctl.signal });
    if (!r.ok) return null;
    const j: any = await r.json();
    const body = String(j?.body || '');
    const vc = Number(/vc=(\d+)/.exec(body)?.[1] || 0);
    const ver = /ver=([\w.\-]+)/.exec(body)?.[1] || '';
    const a = (j?.assets || []).find((x: any) => /\.apk$/i.test(x?.name || ''));
    if (!vc || vc <= MY_VC || !a?.browser_download_url) return null;
    const notes = (/---notes---\n([\s\S]*)$/.exec(body)?.[1] || '').trim();
    return { vc, ver, url: a.browser_download_url, page: j.html_url, notes, mb: Math.round((a.size || 0) / 1048576) };
  } catch { return null; } finally { clearTimeout(to); }
}

export function UpdateGate() {
  const [rel, setRel] = useState<Rel | null>(null);
  const [busy, setBusy] = useState(false);
  useEffect(() => { const t = setTimeout(() => checkUpdate().then(setRel), 2500); return () => clearTimeout(t); }, []);
  if (!rel) return null;
  return (
    <View style={s.wrap} pointerEvents="box-none">
      <View style={s.card}>
        <T s="نسخه‌ی جدید NEXORA آماده‌ست!" style={s.h} />
        <T s={`${faNum(MY_VER)} ← ${faNum(rel.ver || String(rel.vc))}${rel.mb ? `  •  ${faNum(rel.mb)} مگابایت` : ''}`} style={s.sub} />
        {!!rel.notes && <T s={rel.notes.slice(0, 400)} style={s.notes} />}
        <View style={{ flexDirection: 'row', gap: 10, marginTop: 14 }}>
          <Btn label={busy ? 'در حال دانلود…' : 'به‌روزرسانی'} colors={G.green} style={{ flex: 1 }} disabled={busy}
            onPress={() => { setBusy(true); Linking.openURL(rel.url).catch(() => Linking.openURL(rel.page)); setTimeout(() => setBusy(false), 4000); }} />
          <Btn label="بعداً" colors={G.dark} small onPress={() => setRel(null)} />
        </View>
        <T s="بعد از دانلود، فایل را باز کنید و «به‌روزرسانی» را بزنید. اطلاعات بازی حفظ می‌شود." style={s.tip} />
      </View>
    </View>
  );
}

const s = StyleSheet.create({
  wrap: { position: "absolute", left: 0, right: 0, top: 0, bottom: 0, justifyContent: 'center', alignItems: 'center', backgroundColor: 'rgba(3,5,18,.72)', zIndex: 999, elevation: 999 },
  card: { width: '86%', maxWidth: 420, padding: 20, borderRadius: 22, backgroundColor: 'rgba(12,18,48,.98)', borderWidth: 1, borderColor: C.cyan },
  h: { color: '#fff', fontSize: 19, textAlign: 'center' },
  sub: { color: C.cyan, fontSize: 13, textAlign: 'center', marginTop: 6 },
  notes: { color: '#cfd8ff', fontSize: 13, marginTop: 12, lineHeight: 21, textAlign: 'right' },
  tip: { color: '#8f9bc8', fontSize: 11, marginTop: 12, textAlign: 'center' },
});
