import React, { useState } from 'react';
import { ScrollView, View } from 'react-native';
import { UI2 } from '../game/assets';
import { useStore } from '../store';
import { Btn, Enter, Img, Panel, Segment, T, Toggle } from '../ui/kit';
import { C, F, G } from '../ui/theme';
import Account from './Account';
import { ORACLE } from '../game/assets';
import { UI_PREFS, setUiPref } from '../prefs';

export default function Settings({ toast, replayIntro }: { toast: (m: string, k?: string) => void; replayIntro: () => void }) {
  const { p, set, reset } = useStore(); const [sure, setSure] = useState(false);
  const rows: [any, string, string, 'sound' | 'music' | 'haptics' | 'oracle'][] = [
    [UI2.c_mega, 'صداها', 'ضربه، گل، تماشاگر', 'sound'], [UI2.c_bell, 'موسیقی', 'موسیقی منو', 'music'], [UI2.x_gear, 'لرزش', 'بازخورد لمسی هنگام برخورد', 'haptics'], [ORACLE.idle, 'نمایش اوراکل', 'دستیار شناور، مربی بازی و راهنما', 'oracle'],
  ];
  return (
    <ScrollView contentContainerStyle={{ paddingHorizontal: 16, paddingBottom: 40 }} showsVerticalScrollIndicator={false} keyboardShouldPersistTaps="handled">
      <Enter i={0}>
        <Panel style={{ padding: 12, marginBottom: 10 }} accent="transparent">
          <T s="ظاهر و زبان" style={{ fontFamily: F.bold, fontSize: 15, textAlign: 'right', marginBottom: 8 }} />
          <Segment value={UI_PREFS.theme} onChange={v => setUiPref('theme', v)} items={[['dark', 'تم تیره'], ['light', 'تم روشن']]} accent={C.violet} />
          <View style={{ height: 8 }} />
          <Segment value={UI_PREFS.lang} onChange={v => setUiPref('lang', v)} items={[['fa', 'فارسی'], ['en', 'English']]} accent={C.cyan} />
          <T s="با تغییر، برنامه یک لحظه دوباره بارگذاری می‌شود" style={{ color: C.dim, fontSize: 11, textAlign: 'right', marginTop: 6 }} />
        </Panel>
      </Enter>
      <Enter i={0}><Account toast={toast} /></Enter>
      {rows.map(([img, n, d, k], i) => (
        <Enter key={k} i={i}>
          <Panel style={{ marginBottom: 10, padding: 12, flexDirection: 'row-reverse', alignItems: 'center' }} accent="transparent">
            <Img src={img} style={{ width: 44, height: 44 }} />
            <View style={{ flex: 1, marginHorizontal: 10, alignItems: 'flex-end' }}><T s={n} style={{ fontFamily: F.bold, fontSize: 15 }} /><T s={d} style={{ color: C.dim, fontSize: 11, marginTop: 1 }} /></View>
            <Toggle on={!!p[k]} onChange={v => set({ [k]: v } as any)} />
          </Panel>
        </Enter>
      ))}
      <Enter i={3}>
        <Panel style={{ padding: 12, marginBottom: 10 }} accent="transparent">
          <T s="بلندی صدا" style={{ fontFamily: F.bold, fontSize: 15, textAlign: 'right', marginBottom: 8 }} />
          <Segment value={p.volume ?? 1} onChange={v => set({ volume: v })} items={[[0.25, '۲۵٪'], [0.5, '۵۰٪'], [0.75, '۷۵٪'], [1, '۱۰۰٪']]} accent={C.cyan} />
        </Panel>
      </Enter>
      <Enter i={3}>
        <Panel style={{ padding: 12, marginBottom: 10 }} accent="transparent">
          <T s="کیفیت گرافیک" style={{ fontFamily: F.bold, fontSize: 15, textAlign: 'right' }} />
          <T s="روی گوشی‌های ضعیف «روان» را انتخاب کن" style={{ color: C.dim, fontSize: 11, textAlign: 'right', marginBottom: 8 }} />
          <Segment value={p.quality} onChange={v => set({ quality: v })} items={[['high', 'بالا'], ['low', 'روان']]} accent={C.violet} />
        </Panel>
      </Enter>
      <Enter i={4}>
        <Panel style={{ padding: 12, marginBottom: 10 }} accent="transparent">
          <T s="سختی پیش‌فرض ربات" style={{ fontFamily: F.bold, fontSize: 15, textAlign: 'right', marginBottom: 8 }} />
          <Segment value={p.aiLvl} onChange={v => set({ aiLvl: v })} items={[[0, 'آسان'], [1, 'معمولی'], [2, 'سخت']]} />
        </Panel>
      </Enter>
      <View style={{ marginTop: 8 }}><Btn label="پخش دوباره‌ی اینترو" small colors={G.dark} onPress={replayIntro} /></View>
      <View style={{ marginTop: 10 }}>
        <Btn label={sure ? 'مطمئنی؟ دوباره بزن' : 'پاک کردن پیشرفت'} small colors={G.red} onPress={() => { if (!sure) { setSure(true); return; } reset(); setSure(false); toast('پیشرفت پاک شد', 'ok'); }} />
      </View>
      <T s="NEXORA · Finger Soccer · v1.10.0" style={{ fontFamily: F.head, textAlign: 'center', color: C.dim2, fontSize: 10, letterSpacing: 2, marginTop: 24 }} />
    </ScrollView>
  );
}
