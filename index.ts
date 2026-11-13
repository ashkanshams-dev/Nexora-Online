import React, { useEffect, useState } from 'react';
import { registerRootComponent } from 'expo';
import { Platform, View } from 'react-native';
import { loadPrefs } from './src/prefs';

// UI prefs (theme + language) must be applied before the app modules are evaluated,
// because their StyleSheets read the palette at import time. So the app tree is required lazily.
function Boot() {
  const [App, setApp] = useState<React.ComponentType | null>(null);
  useEffect(() => { loadPrefs().then(() => setApp(() => require('./App').default)); }, []);
  return App ? React.createElement(App) : React.createElement(View, { style: { flex: 1, backgroundColor: '#030614' } });
}

if (Platform.OS === 'web') {
  // Skia on web needs CanvasKit (WASM) loaded before any Skia module is evaluated
  const { LoadSkiaWeb } = require('@shopify/react-native-skia/lib/module/web');
  LoadSkiaWeb({ locateFile: (f: string) => '/' + f }).then(() => {
    registerRootComponent(Boot);
  });
} else {
  registerRootComponent(Boot);
}
