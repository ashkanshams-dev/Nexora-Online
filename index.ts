import { registerRootComponent } from 'expo';
import { Platform } from 'react-native';

if (Platform.OS === 'web') {
  // Skia on web needs CanvasKit (WASM) loaded before any Skia module is evaluated
  const { LoadSkiaWeb } = require('@shopify/react-native-skia/lib/module/web');
  LoadSkiaWeb({ locateFile: (f: string) => '/' + f }).then(() => {
    registerRootComponent(require('./App').default);
  });
} else {
  registerRootComponent(require('./App').default);
}
