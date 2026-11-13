// First screen for anyone not signed in: sign up / sign in / continue as guest, with language switch.
import React from 'react';
import { KeyboardAvoidingView, Platform, ScrollView, StyleSheet, View } from 'react-native';
import Animated, { FadeIn, FadeInDown } from 'react-native-reanimated';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { UI } from '../game/assets';
import { Img, Segment, T } from '../ui/kit';
import { C, F } from '../ui/theme';
import Space from '../ui/Space';
import Account from './Account';
import { UI_PREFS, setUiPref } from '../prefs';

export default function Welcome({ toast }: { toast: (m: string, k?: string) => void }) {
  const ins = useSafeAreaInsets();
  return (
    <Animated.View entering={FadeIn.duration(300)} style={[StyleSheet.absoluteFill, { zIndex: 95, backgroundColor: C.bg }]}>
      <Space theme="stadium" dim={.1} />
      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        <ScrollView contentContainerStyle={{ paddingTop: ins.top + 16, paddingBottom: ins.bottom + 24, paddingHorizontal: 18 }} keyboardShouldPersistTaps="handled" showsVerticalScrollIndicator={false}>
          <View style={{ width: 150, alignSelf: 'flex-start' }}>
            <Segment value={UI_PREFS.lang} onChange={v => setUiPref('lang', v)} items={[['fa', 'FA'], ['en', 'EN']]} accent={C.cyan} />
          </View>
          <Animated.View entering={FadeInDown.delay(80).springify()} style={{ alignItems: 'center', marginTop: 8 }}>
            <Img src={UI.logo_nexora} style={{ width: 240, height: 120 }} />
            <T s="به نکسورا خوش آمدی" style={{ fontFamily: F.title, fontSize: 22, marginTop: 6, textAlign: 'center' }} />
            <T s="حساب بساز تا پیشرفت، دیسک‌ها و دوستانت روی هر گوشی همراهت باشند." style={{ color: C.dim, fontSize: 13, textAlign: 'center', marginTop: 6, lineHeight: 21 }} />
          </Animated.View>
          <Animated.View entering={FadeInDown.delay(180).springify()} style={{ marginTop: 18 }}>
            <Account toast={toast} />
          </Animated.View>
        </ScrollView>
      </KeyboardAvoidingView>
    </Animated.View>
  );
}
