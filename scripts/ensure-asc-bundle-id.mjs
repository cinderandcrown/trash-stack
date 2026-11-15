/**
 * Ensure the App Store Connect / Developer bundle id exists.
 * Uses ASC API key from env (never prints secret material).
 *
 * Env: ASC_ISSUER_ID, ASC_KEY_ID, ASC_KEY_P8 (PEM contents), optional BUNDLE_ID / BUNDLE_NAME
 *
 * Note: For Trash Stack the bundle id com.cinderandcrown.trashstack is already
 * registered (App Store Connect Apple ID 6834995780). This script is idempotent.
 */
import crypto from 'node:crypto';

const BUNDLE_ID = process.env.BUNDLE_ID || 'com.cinderandcrown.trashstack';
const BUNDLE_NAME = process.env.BUNDLE_NAME || 'Trash Stack';
const issuerId = process.env.ASC_ISSUER_ID;
const keyId = process.env.ASC_KEY_ID;
const keyP8 = process.env.ASC_KEY_P8;

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

async function main() {
  const filter = encodeURIComponent(`identifier="${BUNDLE_ID}"`);
  const listed = await asc(`/v1/bundleIds?filter[identifier]=${BUNDLE_ID}&limit=5`);
  if (!listed.ok) {
    console.error('Failed to list bundle ids (status', listed.status + ')');
    process.exit(1);
  }
  const existing = listed.json?.data || [];
  if (existing.length) {
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
    // Concurrent create / already exists race
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

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
