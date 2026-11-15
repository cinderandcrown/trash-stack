/**
 * AdMob unit ID placeholders for Trash Stack.
 * Leave empty / omit to use Google official TEST units (default in src/ads.js).
 * Replace with real AdMob IDs before production store builds.
 *
 * Never commit real production secrets that authorize billing — app IDs are public
 * by design in the native manifests; these are ad unit IDs only.
 */
window.TRASH_AD_CONFIG = {
  // When true (default), SDK initializes in test mode.
  useTestIds: true,
  // Optional hashed test device IDs from logcat / Xcode.
  testDeviceIds: [],
  // Real unit ID placeholders (unused while useTestIds / empty):
  interstitial: {
    ios: '', // e.g. 'ca-app-pub-xxxxxxxx/yyyyyyyy'
    android: '',
  },
  rewarded: {
    ios: '',
    android: '',
  },
};
