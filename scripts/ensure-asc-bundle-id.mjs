/**
 * Ensure App Store Connect / Developer portal prerequisites for signing:
 *  - bundle id exists (idempotent; already registered for Trash Stack)
 *  - at least one iOS device exists (needed for Xcode automatic signing
 *    to mint development profiles during archive on CI)
 *
 * Env: ASC_ISSUER_ID, ASC_KEY_ID, ASC_KEY_P8 (PEM). Never prints secrets.
 * Optional: BUNDLE_ID, BUNDLE_NAME
 *
 * ASC app Apple ID 6834995780 · bundle com.cinderandcrown.trashstack
 */
import crypto from 'node:crypto';

const BUNDLE_ID = process.env.BUNDLE_ID || 'com.cinderandcrown.trashstack';
const BUNDLE_NAME = process.env.BUNDLE_NAME || 'Trash Stack';
const issuerId = process.env.ASC_ISSUER_ID;
const keyId = process.env.ASC_KEY_ID;
const keyP8 = process.env.ASC_KEY_P8;

// Synthetic UDID reserved for CI automatic-signing bootstrap (not a real handset).
const CI_DEVICE_UDID = process.env.CI_DEVICE_UDID || '00008030-001A2C3D4E5F6789';
const CI_DEVICE_NAME = process.env.CI_DEVICE_NAME || 'Trash Stack CI Placeholder';

function b64url(input) {
  return Buffer.from(input)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function makeJwt() {
  if (!issuerId || !keyId || !keyP8) {
    throw new Error('ASC_ISSUER_ID, ASC_KEY_ID, and ASC_KEY_P8 are required');
  }
  const header = { alg: 'ES256', kid: keyId, typ: 'JWT' };
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: issuerId,
    iat: now,
    exp: now + 19 * 60,
    aud: 'appstoreconnect-v1',
  };
  const unsigned = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(payload))}`;
  const key = crypto.createPrivateKey(keyP8.replace(/\\n/g, '\n'));
  const sig = crypto.sign('sha256', Buffer.from(unsigned), { key, dsaEncoding: 'ieee-p1363' });
  return `${unsigned}.${sig.toString('base64').replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_')}`;
}

async function asc(path, { method = 'GET', body } = {}) {
  const token = makeJwt();
  const res = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = { raw: text };
  }
  return { ok: res.ok, status: res.status, json };
}

async function ensureBundleId() {
  const listed = await asc(`/v1/bundleIds?filter[identifier]=${BUNDLE_ID}&limit=5`);
  if (!listed.ok) {
    console.error('Failed to list bundle ids (status', listed.status + ')');
    process.exit(1);
  }
  if ((listed.json?.data || []).length) {
    console.log(`Bundle id already registered: ${BUNDLE_ID}`);
    return;
  }

  console.log(`Registering bundle id ${BUNDLE_ID}…`);
  const created = await asc('/v1/bundleIds', {
    method: 'POST',
    body: {
      data: {
        type: 'bundleIds',
        attributes: {
          identifier: BUNDLE_ID,
          name: BUNDLE_NAME,
          platform: 'IOS',
        },
      },
    },
  });
  if (!created.ok) {
    const detail = created.json?.errors?.[0]?.detail || `status ${created.status}`;
    if (/already|exists|duplicate/i.test(detail)) {
      console.log(`Bundle id already registered: ${BUNDLE_ID}`);
      return;
    }
    console.error('Failed to register bundle id:', detail);
    process.exit(1);
  }
  console.log(`Registered bundle id: ${BUNDLE_ID}`);
}

async function ensureCiDevice() {
  const listed = await asc('/v1/devices?limit=200&filter[platform]=IOS');
  if (!listed.ok) {
    console.error('Failed to list devices (status', listed.status + ')');
    process.exit(1);
  }
  const devices = listed.json?.data || [];
  if (devices.length) {
    console.log(`iOS devices already registered: ${devices.length}`);
    return;
  }

  console.log('No iOS devices on team — registering CI placeholder for automatic signing…');
  const created = await asc('/v1/devices', {
    method: 'POST',
    body: {
      data: {
        type: 'devices',
        attributes: {
          name: CI_DEVICE_NAME,
          platform: 'IOS',
          udid: CI_DEVICE_UDID,
        },
      },
    },
  });
  if (!created.ok) {
    const detail = created.json?.errors?.[0]?.detail || `status ${created.status}`;
    // Invalid UDID is possible; surface clearly so humans can register Nicholas's device.
    console.error('Failed to register CI placeholder device:', detail);
    console.error(
      'Register any iPhone UDID for the team in Certificates, Identifiers & Profiles, then re-run.'
    );
    process.exit(1);
  }
  console.log('Registered CI placeholder device for provisioning.');
}

await ensureBundleId();
await ensureCiDevice();
