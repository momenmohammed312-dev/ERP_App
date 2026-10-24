'use strict';
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const REPO_ROOT = path.resolve(__dirname, '..');
const PRIV_KEY_PATH = path.join(REPO_ROOT, 'test', 'fixtures', 'license', 'test_private.pem');

const hardwareId = process.argv[2];
const outPath = process.argv[3];

if (!hardwareId || !outPath) {
  console.error('Usage: node gen_dev_license.js <hardwareId> <outPath>');
  process.exit(1);
}

function b64url(obj) {
  return Buffer.from(JSON.stringify(obj), 'utf8').toString('base64url');
}

function signLease(payload, pem) {
  const header = { alg: 'RS256', typ: 'JWT' };
  const unsigned = b64url(header) + '.' + b64url(payload);
  const signer = crypto.createSign('RSA-SHA256');
  signer.update(unsigned);
  const signature = signer.sign(pem, 'base64url');
  return unsigned + '.' + signature;
}

const privateKey = fs.readFileSync(PRIV_KEY_PATH, 'utf8');

const now = Math.floor(Date.now() / 1000);
const exp = now + 36500 * 86400; // 100 years = lifetime
const licenseKey = 'MO2-DEV-LIFETIME-SUPER';

const payload = {
  license_key: licenseKey,
  machine_guid: '',
  install_uuid: '',
  hardware_id: hardwareId,
  plan: 'professional',
  features: [
    'pos',
    'cash_sales',
    'credit_sales',
    'customers',
    'suppliers',
    'purchases',
    'inventory',
    'reports',
    'advanced_reports',
    'backup',
    'auto_backup',
    'staff_management',
    'attendance',
    'payroll',
    'custody',
    'damaged_goods',
    'manufacturing',
    'admin_dashboard',
    'api_access'
  ],
  license_expires_at: null,
  status: 'active',
  iat: now,
  exp: exp
};

const lease = signLease(payload, privateKey);

const envelope = {
  madar_license_envelope: 'v1',
  license_key: licenseKey,
  customer: 'مطور النظام (ترخيص دائم مدى الحياة)',
  type: 'paid',
  term_days: 36500,
  lifetime: true,
  device_clock_utc: new Date(now * 1000).toISOString(),
  device_clock_offset_seconds: 0,
  lease: lease
};

fs.mkdirSync(path.dirname(outPath), { recursive: true });
fs.writeFileSync(outPath, JSON.stringify(envelope, null, 2), 'utf8');
console.log('SUCCESS: Developer Lifetime License generated: ' + outPath);
