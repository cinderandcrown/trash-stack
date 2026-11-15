/**
 * AdMob facade for Trash Stack.
 * Uses Google official TEST ad unit IDs by default.
 * Real IDs can be supplied via window.TRASH_AD_CONFIG placeholders.
 */
import { Capacitor } from '@capacitor/core';
import {
  AdMob,
  AdmobConsentStatus,
  InterstitialAdPluginEvents,
  RewardAdPluginEvents,
} from '@capacitor-community/admob';

const TEST = {
  appId: {
    ios: 'ca-app-pub-3940256099942544~1458002511',
    android: 'ca-app-pub-3940256099942544~3347511713',
  },
  interstitial: {
    ios: 'ca-app-pub-3940256099942544/4411468910',
    android: 'ca-app-pub-3940256099942544/1033173712',
  },
  rewarded: {
    ios: 'ca-app-pub-3940256099942544/1712485313',
    android: 'ca-app-pub-3940256099942544/5224354917',
  },
};

function platform() {
  return Capacitor.getPlatform();
}

function cfg() {
  return (typeof window !== 'undefined' && window.TRASH_AD_CONFIG) || {};
}

function unit(kind) {
  const c = cfg();
  const p = platform();
  const custom = c[kind] && (c[kind][p] || c[kind].default);
  if (custom && String(custom).trim()) return String(custom).trim();
  return TEST[kind][p] || TEST[kind].android;
}

let ready = false;
let canRequestAds = true;
let sessionRuns = 0;
let oversSinceInterstitial = 0;
let interstitialReady = false;
let rewardReady = false;

async function requestTrackingIfNeeded() {
  if (platform() !== 'ios') return;
  try {
    const status = await AdMob.trackingAuthorizationStatus();
    // 0=notDetermined — request; otherwise leave as-is
    if (status && (status.status === 'notDetermined' || status.status === 0)) {
      await AdMob.requestTrackingAuthorization();
    }
  } catch (_) {}
}

async function runConsentFlow() {
  try {
    let info = await AdMob.requestConsentInfo({
      debugGeography: cfg().debugGeography,
      testDeviceIdentifiers: cfg().testDeviceIds || [],
    });
    if (
      info &&
      info.isConsentFormAvailable &&
      info.status === AdmobConsentStatus.REQUIRED
    ) {
      info = await AdMob.showConsentForm();
    }
    canRequestAds = !info || info.canRequestAds !== false;
  } catch (_) {
    canRequestAds = true;
  }
}

export async function initAds() {
  if (!Capacitor.isNativePlatform()) {
    ready = true;
    canRequestAds = true;
    return { ready, canRequestAds, mode: 'web-stub' };
  }
  await requestTrackingIfNeeded();
  await runConsentFlow();
  if (!canRequestAds) {
    ready = false;
    return { ready, canRequestAds, mode: 'consent-blocked' };
  }
  try {
    await AdMob.initialize({
      initializeForTesting: cfg().useTestIds !== false,
      testingDevices: cfg().testDeviceIds || [],
    });
    ready = true;
    await preloadInterstitial();
    await preloadRewarded();
  } catch (_) {
    ready = false;
  }
  return { ready, canRequestAds, mode: 'native' };
}

async function preloadInterstitial() {
  if (!ready || !canRequestAds || !Capacitor.isNativePlatform()) return;
  try {
    await AdMob.prepareInterstitial({ adId: unit('interstitial') });
    interstitialReady = true;
  } catch (_) {
    interstitialReady = false;
  }
}

async function preloadRewarded() {
  if (!ready || !canRequestAds || !Capacitor.isNativePlatform()) return;
  try {
    await AdMob.prepareRewardVideoAd({ adId: unit('rewarded') });
    rewardReady = true;
  } catch (_) {
    rewardReady = false;
  }
}

/** Call at the start of each run. */
export function noteRunStarted() {
  sessionRuns += 1;
}

/**
 * Interstitial rules:
 * - never in first 2 runs of a session
 * - at most one every 3 game overs
 * - never during play (caller must invoke between runs only)
 * - skipped when ads removed
 */
export async function maybeShowInterstitial({ adsRemoved } = {}) {
  if (adsRemoved) return false;
  oversSinceInterstitial += 1;
  if (sessionRuns <= 2) return false;
  if (oversSinceInterstitial < 3) return false;

  if (!Capacitor.isNativePlatform()) {
    // Web stub: no UI ad, just respect the cap.
    oversSinceInterstitial = 0;
    return false;
  }
  if (!ready || !canRequestAds) return false;
  try {
    if (!interstitialReady) await preloadInterstitial();
    if (!interstitialReady) return false;
    await AdMob.showInterstitial();
    oversSinceInterstitial = 0;
    interstitialReady = false;
    await preloadInterstitial();
    return true;
  } catch (_) {
    interstitialReady = false;
    return false;
  }
}

/**
 * Opt-in rewarded video. Resolves true if the user earned the reward.
 * Web stub auto-grants after a short delay so desktop testing works offline.
 */
export function showRewarded(reason) {
  return new Promise(async (resolve) => {
    if (!Capacitor.isNativePlatform()) {
      setTimeout(() => resolve(true), 600);
      return;
    }
    if (!ready || !canRequestAds) {
      resolve(false);
      return;
    }
    let settled = false;
    const finish = (ok) => {
      if (settled) return;
      settled = true;
      resolve(!!ok);
    };
    const rewardHandle = await AdMob.addListener(
      RewardAdPluginEvents.Rewarded,
      () => finish(true)
    ).catch(() => null);
    const dismissHandle = await AdMob.addListener(
      RewardAdPluginEvents.Dismissed,
      () => finish(false)
    ).catch(() => null);
    const failHandle = await AdMob.addListener(
      RewardAdPluginEvents.FailedToLoad,
      () => finish(false)
    ).catch(() => null);
    try {
      if (!rewardReady) await preloadRewarded();
      await AdMob.showRewardVideoAd();
      // If events never fire, fail-safe after timeout
      setTimeout(() => finish(false), 120000);
    } catch (_) {
      finish(false);
    } finally {
      setTimeout(() => {
        rewardHandle && rewardHandle.remove && rewardHandle.remove();
        dismissHandle && dismissHandle.remove && dismissHandle.remove();
        failHandle && failHandle.remove && failHandle.remove();
        preloadRewarded();
      }, 1500);
    }
  });
}

export function getAdDebugInfo() {
  return {
    ready,
    canRequestAds,
    sessionRuns,
    oversSinceInterstitial,
    platform: platform(),
    interstitialUnit: unit('interstitial'),
    rewardedUnit: unit('rewarded'),
    usingTestDefaults: !(cfg().interstitial && cfg().interstitial[platform()]),
  };
}

// Silence unused import warning for interstitial events in some bundlers
void InterstitialAdPluginEvents;
