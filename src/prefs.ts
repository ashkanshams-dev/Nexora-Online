// Device-level UI preferences (theme + language). Read once before the app tree is required
// (index.ts) so module-level styles pick up the theme; changing either reloads the JS bundle.
import AsyncStorage from '@react-native-async-storage/async-storage';
import { reloadAppAsync } from 'expo';
import { Lang, setLang } from './i18n';
import { applyTheme, ThemeName } from './ui/theme';

const KEY = 'nexora.ui.v1';
export type UiPrefs = { theme: ThemeName; lang: Lang };
export let UI_PREFS: UiPrefs = { theme: 'dark', lang: 'fa' };

export async function loadPrefs() {
  try { const s = await AsyncStorage.getItem(KEY); if (s) UI_PREFS = { ...UI_PREFS, ...JSON.parse(s) }; } catch { }
  applyTheme(UI_PREFS.theme); setLang(UI_PREFS.lang);
}
export async function setUiPref<K extends keyof UiPrefs>(k: K, v: UiPrefs[K]) {
  if (UI_PREFS[k] === v) return;
  UI_PREFS = { ...UI_PREFS, [k]: v };
  await AsyncStorage.setItem(KEY, JSON.stringify(UI_PREFS)).catch(() => {});
  try { await reloadAppAsync('ui-prefs'); } catch { applyTheme(UI_PREFS.theme); setLang(UI_PREFS.lang); }
}
