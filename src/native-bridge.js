import { Capacitor } from '@capacitor/core';
import { Haptics, ImpactStyle, NotificationType } from '@capacitor/haptics';
import { Preferences } from '@capacitor/preferences';
import { StatusBar, Style } from '@capacitor/status-bar';
import { SplashScreen } from '@capacitor/splash-screen';
import { App } from '@capacitor/app';

const native = Capacitor.isNativePlatform();

async function prepareChrome() {
  if (!native) return;
  try {
    await StatusBar.hide();
  } catch (_) {}
  try {
    await StatusBar.setStyle({ style: Style.Dark });
  } catch (_) {}
  try {
    await StatusBar.setOverlaysWebView({ overlay: true });
  } catch (_) {}
}

async function hideSplash() {
  if (!native) return;
  try {
    await SplashScreen.hide({ fadeOutDuration: 220 });
  } catch (_) {}
}

/**
 * Map legacy vibrate durations to Capacitor haptics.
 * Short ticks → Light, medium → Medium, long clears → Heavy.
 */
async function haptic(ms) {
  if (!native) {
    try {
      if (navigator.vibrate) navigator.vibrate(ms);
    } catch (_) {}
    return;
  }
  try {
    if (ms >= 80) {
      await Haptics.impact({ style: ImpactStyle.Heavy });
    } else if (ms >= 30) {
      await Haptics.impact({ style: ImpactStyle.Medium });
    } else {
      await Haptics.impact({ style: ImpactStyle.Light });
    }
  } catch (_) {
    try {
      await Haptics.notification({ type: NotificationType.Success });
    } catch (__) {}
  }
}

async function getPref(key) {
  if (native) {
    const { value } = await Preferences.get({ key });
    return value;
  }
  try {
    return localStorage.getItem(key);
  } catch (_) {
    return null;
  }
}

async function setPref(key, value) {
  if (native) {
    await Preferences.set({ key, value });
    // Keep a localStorage mirror so web tooling / migrations stay consistent.
    try {
      localStorage.setItem(key, value);
    } catch (_) {}
    return;
  }
  try {
    localStorage.setItem(key, value);
  } catch (_) {}
}

/**
 * Prefer Capacitor Preferences on native. One-time migrate from localStorage
 * when Preferences is empty but localStorage still has progress.
 */
async function loadProgress(key) {
  let value = await getPref(key);
  if (value == null) {
    try {
      const legacy = localStorage.getItem(key);
      if (legacy != null) {
        value = legacy;
        if (native) {
          await Preferences.set({ key, value: legacy });
        }
      }
    } catch (_) {}
  }
  return value;
}

async function saveProgress(key, value) {
  await setPref(key, value);
}

async function consumeShotMode() {
  // CI sets Preferences key "trashStack.shot" = "game" before launch for screenshots.
  try {
    const { value } = await Preferences.get({ key: 'trashStack.shot' });
    if (value) {
      await Preferences.remove({ key: 'trashStack.shot' });
      return value;
    }
  } catch (_) {}
  try {
    const hash = (typeof location !== 'undefined' && location.hash) || '';
    if (hash.includes('shot=game')) return 'game';
  } catch (_) {}
  return null;
}

window.TrashNative = {
  isNative: native,
  platform: Capacitor.getPlatform(),
  prepareChrome,
  hideSplash,
  haptic,
  loadProgress,
  saveProgress,
  consumeShotMode,
  App,
};

document.documentElement.classList.toggle('native-app', native);
document.documentElement.dataset.platform = Capacitor.getPlatform();
