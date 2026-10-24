#!/usr/bin/env node
'use strict';

/**
 * MADAR — مُصدِّر تراخيص محلية موقَّعة (FEAT-011)
 *
 * يُصدر وثيقة `.madarlicense` موقَّعة RS256، بدون أي اتصال بالشبكة وبأي
 * اعتمادية خارجية (Node built-ins فقط).
 *
 *   node tools/license_issuer.js --type trial --days 7 \
 *     --machine-guid <GUID> --features pos,cash_sales,inventory \
 *     --out C:\secure\customer-1.madarlicense
 *
 * يجب أن يطابق المخرج بايت-ببايت توقيع Cloudflare Worker المستقبلي على نفس
 * الـclaims التسعة:
 *   license_key · machine_guid · install_uuid · plan · features
 *   license_expires_at · status · iat · exp
 *
 * ⛔ المفتاح الخاص لا يدخل هذا المستودع أبداً. الحُرّاس أدناه ترفض أي مسار
 * داخل المستودع و`test_private.pem` صراحةً.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const REPO_ROOT = path.resolve(__dirname, '..');
const DAY = 86400;
const LIFETIME_DAYS = 36500;
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I

// ── helpers ────────────────────────────────────────────────────────────────

function fail(message, code = 1) {
  console.error('\n✖ ' + message + '\n');
  process.exit(code);
}

function isInside(child, parent) {
  const rel = path.relative(parent, child);
  return rel === '' || (!rel.startsWith('..') && !path.isAbsolute(rel));
}

/** Guards against the key or the output landing somewhere it must never go. */
function assertOutsideRepo(target, label) {
  if (isInside(target, REPO_ROOT)) {
    fail(
      label +
        ' مرفوض: المسار داخل المستودع (' +
        path.relative(REPO_ROOT, target) +
        ').\n' +
        '  المفتاح الخاص ووثائق الترخيص يجب أن يبقيا خارج git تماماً.\n' +
        '  استخدم مساراً مثل  E:\\Temp\\madar-keys\\  أو مجلداً خارج المشروع.',
    );
  }
}

function assertNotTestKey(keyPath) {
  const base = path.basename(keyPath).toLowerCase();
  if (base === 'test_private.pem') {
    fail(
      'المفتاح مرفوض: test_private.pem متتبَّع في git، وأي رخصة يوقّعها\n' +
        ' become غير صالحة تجارياً بمجرد تحويل LICENSE_PUBLIC_KEY إلى مفتاح الإنتاج.',
    );
  }

  const tracked = path.join(REPO_ROOT, 'test', 'fixtures', 'license', 'test_private.pem');
  if (fs.existsSync(tracked) && fs.existsSync(keyPath)) {
    const a = crypto.createHash('sha256').update(fs.readFileSync(keyPath)).digest('hex');
    const b = crypto.createHash('sha256').update(fs.readFileSync(tracked)).digest('hex');
    if (a === b) {
      fail(
        'المفتاح مرفوض: هو نفسه test_private.pem المتتبَّع في git (مطابق بالمحتوى).\n' +
          '  أي ترخيص موقَّع به يُرفض فور استخدام مفتاح الإنتاج.',
      );
    }
  }
}

// ── argument parsing ───────────────────────────────────────────────────────

const USAGE = `
مُصدِّر تراخيص MADAR — إصدار وثيقة .madarlicense موقَّعة RS256 بدون إنترنت.

الاستخدام:
  node tools/license_issuer.js [options]

الخيارات:
  --type trial|paid        نوع الترخيص (افتراضي: trial)
  --days N                 مدة بالأيام (للتجربة)  — بواحدة من: --days أو --months
  --months N               مدة بالأشهر (للدفع)     — 12 = سنة كاملة (365 يوماً)
  --lifetime               ترخيص مدى الحياة (exp = iat + ${LIFETIME_DAYS} يوماً)
  --features a,b,c         الميزات الممنوحة (مطلوب — لا قيم فارغة)
  --customer "اسم العميل"  اسم العميل (يُطبع في السجل فقط، لا يدخل التوقيع)
  --plan <name>            خطة صريحة: trial|basic|standard|professional|enterprise
  --bind machine|install|both|hardware|all   أي معرّف جهاز يُربط به الترخيص
                            (افتراضي: machine) · hardware = البصمة المعروضة على
                            شاشة التفعيل · all = الثلاثة معاً
  --machine-guid <GUID>    MachineGuid للجهاز (مطلوب مع machine|both|all)
  --install-uuid <UUID>    معرّف التثبيت (مطلوب مع install|both|all)
  --hardware-id <hash>     بصمة الجهاز الظاهرة على شاشة التفعيل
                            (مطلوب مع hardware|all)
  --key <path>             مسار المفتاح الخاص (أو MADAR_ISSUER_KEY_FILE)
  --out <path>             مسار ملف الإخراج (مطلوب، ويجب أن يكون خارج المستودع)
  --license-key <key>      مفتاح محدَّد بدل توليده تلقائياً
  --help                   هذه المساعدة

مثال (تجربة 7 أيام):
  node tools/license_issuer.js --type trial --days 7 \\
    --machine-guid 3F2504E0-4F89-41D3-9A0C-0305E82C3301 \\
    --features pos,cash_sales,inventory --out E:\\Temp\\c1.madarlicense

مثال (سنوي):
  node tools/license_issuer.js --type paid --months 12 \\
    --machine-guid 3F2504E0-4F89-41D3-9A0C-0305E82C3301 \\
    --features pos,manufacturing,custody --out E:\\Temp\\c2.madarlicense

مثال (ربط ببصمة الجهاز الظاهرة على شاشة التفعيل — للعميل بدون سيرفر):
  node tools/license_issuer.js --type paid --months 12 --bind hardware \\
    --hardware-id <الكود الظاهر على الشاشة> \\
    --features pos,cash_sales,mobile --out E:\\Temp\\c3.madarlicense
`;

function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith('--')) {
      args._.push(a);
      continue;
    }
    const eq = a.indexOf('=');
    if (eq !== -1) {
      args[a.slice(2, eq)] = a.slice(eq + 1);
      continue;
    }
    const name = a.slice(2);
    const next = argv[i + 1];
    if (next === undefined || next.startsWith('--')) {
      args[name] = true;
    } else {
      args[name] = next;
      i++;
    }
  }
  return args;
}

// ── signing (byte-identical to tools/license_simulator.js) ─────────────────

function b64url(obj) {
  return Buffer.from(JSON.stringify(obj), 'utf8').toString('base64url');
}

function signLease(payload, privateKeyPem) {
  const header = { alg: 'RS256', typ: 'JWT' };
  const unsigned = `${b64url(header)}.${b64url(payload)}`;
  const signer = crypto.createSign('RSA-SHA256');
  signer.update(unsigned);
  const signature = signer.sign(privateKeyPem, 'base64url');
  return `${unsigned}.${signature}`;
}

function generateLicenseKey() {
  const bytes = crypto.randomBytes(12);
  let body = '';
  for (const b of bytes) body += ALPHABET[b % ALPHABET.length];
  return 'MO2-' + body.slice(0, 4) + '-' + body.slice(4, 8) + '-' + body.slice(8, 12);
}

// ── main ───────────────────────────────────────────────────────────────────

function main() {
  const args = parseArgs(process.argv.slice(2));

  if (args.help || args.h) {
    console.log(USAGE);
    process.exit(0);
  }

  // ── key guards run first: nothing is written before they pass ────────────
  const keyArg = args.key || process.env.MADAR_ISSUER_KEY_FILE;
  if (!keyArg || keyArg === true) {
    fail(
      'لم يُحدَّد المفتاح الخاص.\n' +
        '  استخدم  --key <path>  أو  اضبط  MADAR_ISSUER_KEY_FILE.\n' +
        '  المفتاح يجب أن يكون RSA-2048 على الأقل، وخارج المستودع.',
    );
  }
  const keyPath = path.resolve(String(keyArg));
  assertOutsideRepo(keyPath, 'مسار المفتاح');
  assertNotTestKey(keyPath);
  if (!fs.existsSync(keyPath)) {
    fail('ملف المفتاح غير موجود: ' + keyPath);
  }
  const privateKeyPem = fs.readFileSync(keyPath, 'utf8');
  if (!privateKeyPem.includes('PRIVATE KEY')) {
    fail('الملف لا يبدو مفتاحاً خاصاً بصيغة PEM.');
  }

  // ── output guards ───────────────────────────────────────────────────────
  if (!args.out || args.out === true) {
    fail('لم يُحدَّد مسار الإخراج. استخدم  --out <path>.');
  }
  const outPath = path.resolve(String(args.out));
  assertOutsideRepo(outPath, 'مسار الإخراج');

  // ── term ────────────────────────────────────────────────────────────────
  const type = String(args.type || 'trial');
  if (type !== 'trial' && type !== 'paid') {
    fail('--type يجب أن يكون trial أو paid (القيمة: ' + type + ').');
  }

  let days;
  let lifetime = false;
  if (args.lifetime) {
    lifetime = true;
    days = LIFETIME_DAYS;
  } else if (args.days !== undefined && args.months !== undefined) {
    fail('لا يمكن تمرير --days و --months معاً.');
  } else if (args.days !== undefined) {
    days = Number(args.days);
    if (!Number.isInteger(days)) fail('--days يجب أن يكون عدداً صحيحاً.');
    if (days <= 0) fail('--days يجب أن يكون أكبر من صفر. (--days 0 مرفوض)');
  } else if (args.months !== undefined) {
    const months = Number(args.months);
    if (!Number.isInteger(months)) fail('--months يجب أن يكون عدداً صحيحاً.');
    if (months <= 0) fail('--months يجب أن يكون أكبر من صفر.');
    // سنة مدنية من لحظة الإصدار: 12 شهراً = 365 يوماً بالضبط.
    days = Math.round((months * 365) / 12);
  } else {
    fail(
      'لم تُحدَّد المدة. استخدم  --days N  أو  --months N  أو  --lifetime.\n' +
        '  (تجربة: 7 أيام · سنوي: --months 12)',
    );
  }

  // ── features ────────────────────────────────────────────────────────────
  if (args.features === undefined || args.features === true) {
    fail('--features مطلوب. مثال:  --features pos,cash_sales,inventory');
  }
  const features = String(args.features)
    .split(',')
    .map((f) => f.trim())
    .filter(Boolean);
  if (features.length === 0) {
    fail('--features فارغ. يجب تمرير ميزة واحدة على الأقل.');
  }

  // ── device binding ──────────────────────────────────────────────────────
  const bind = String(args.bind || 'machine');
  if (!['machine', 'install', 'both', 'hardware', 'all'].includes(bind)) {
    fail('--bind يجب أن يكون machine أو install أو both أو hardware أو all.');
  }
  const usesHardware = bind === 'hardware' || bind === 'all';
  const machineGuid =
    bind === 'install' || bind === 'hardware'
      ? ''
      : String(args['machine-guid'] || '');
  const installUuid =
    bind === 'machine' || bind === 'hardware'
      ? ''
      : String(args['install-uuid'] || '');
  const hardwareId = usesHardware
    ? String(args['hardware-id'] || '').trim()
    : '';
  if (
    (bind === 'machine' || bind === 'both' || bind === 'all') &&
    !machineGuid
  ) {
    fail('--machine-guid مطلوب مع --bind ' + bind + '.');
  }
  if (
    (bind === 'install' || bind === 'both' || bind === 'all') &&
    !installUuid
  ) {
    fail('--install-uuid مطلوب مع --bind ' + bind + '.');
  }
  if (usesHardware && !hardwareId) {
    fail('--hardware-id مطلوب مع --bind ' + bind + '.');
  }

  // ── plan ────────────────────────────────────────────────────────────────
  let plan;
  if (args.plan && args.plan !== true) {
    plan = String(args.plan);
  } else if (type === 'trial') {
    plan = 'trial';
  } else if (lifetime) {
    plan = 'lifetime';
  } else {
    plan = days >= 365 ? 'yearly' : 'monthly';
  }

  // ── claims ──────────────────────────────────────────────────────────────
  const nowSeconds = Math.floor(Date.now() / 1000);
  const iat = nowSeconds;
  const exp = iat + days * DAY;
  const licenseKey =
    args['license-key'] && args['license-key'] !== true
      ? String(args['license-key'])
      : generateLicenseKey();

  // Exactly the ten claims the client verifies — nothing more, nothing less.
  const payload = {
    license_key: licenseKey,
    machine_guid: machineGuid,
    install_uuid: installUuid,
    hardware_id: hardwareId,
    plan: plan,
    features: features,
    license_expires_at: lifetime ? null : new Date(exp * 1000).toISOString(),
    status: 'active',
    iat: iat,
    exp: exp,
  };

  const lease = signLease(payload, privateKeyPem);

  const envelope = {
    madar_license_envelope: 'v1',
    license_key: licenseKey,
    customer: args.customer && args.customer !== true ? String(args.customer) : null,
    type: type,
    term_days: days,
    lifetime: lifetime,
    device_clock_utc: new Date(nowSeconds * 1000).toISOString(),
    device_clock_offset_seconds: 0,
    lease: lease,
  };

  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, JSON.stringify(envelope, null, 2), 'utf8');

  // ── report ──────────────────────────────────────────────────────────────
  const expiry = new Date(exp * 1000).toISOString();
  console.log('\n✔ تم إصدار الترخيص\n');
  console.log('  الملف          : ' + outPath);
  console.log('  مفتاح الترخيص  : ' + licenseKey);
  console.log('  الخطة          : ' + plan + '  (' + type + ')');
  console.log('  المدة          : ' + days + ' يوماً');
  console.log('  الميزات        : ' + features.join('، '));
  console.log('  الربط بجهاز    : ' + bind +
    (machineGuid ? '  machine_guid=' + machineGuid : '') +
    (installUuid ? '  install_uuid=' + installUuid : '') +
    (hardwareId ? '  hardware_id=' + hardwareId : ''));
  console.log('  صادر في       : ' + envelope.device_clock_utc + '  (iat=' + iat + ')');
  console.log('  ينتهي في      : ' + expiry + '  (exp=' + exp + ')');
  console.log('');
  console.log('  إزاحة ساعة الجهاز (device_clock_offset_seconds): 0');
  console.log('    لا يوجد مرجع موثوق بدون إنترنت، Falمن المهم أن تكون ساعة');
  console.log('    جهاز العميل مضبوطة، وإلا عُدّت التجربة منتهية sooner.');
  console.log('\n  الخطوة التالية: انسخ الملف إلى جهاز العميل، ثم من شاشة التفعيل');
  console.log('  اضغط «استيراد رخصة من ملف».\n');
}

main();