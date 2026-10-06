/**
 * Local Supabase Edge Function Simulator & Modular License Dashboard
 * 
 * Zero dependencies! Runs with: node tools/license_simulator.js
 * 
 * Features:
 * 1. Simulates Supabase Edge Function at POST http://localhost:8000/license_api
 * 2. Real RS256 JWT signing matching the Flutter app expectations
 * 3. Modular Feature Flags per client: Toggle specific modules (Manufacturing, Staff, Custody, etc.)
 * 4. Built-in Web UI at http://localhost:8000/ with checkboxes for every module!
 */

const http = require('http');
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const PORT = 8000;
const DB_FILE = path.join(__dirname, 'simulator_db.json');
const FIXTURES_DIR = path.join(__dirname, '..', 'test', 'fixtures', 'license');
const PRIV_KEY_PATH = path.join(FIXTURES_DIR, 'test_private.pem');
const PUB_KEY_PATH = path.join(FIXTURES_DIR, 'test_public.pem');

// 1. Load or Generate RSA Key Pair
let privateKeyPem, publicKeyPem;
if (fs.existsSync(PRIV_KEY_PATH) && fs.existsSync(PUB_KEY_PATH)) {
  privateKeyPem = fs.readFileSync(PRIV_KEY_PATH, 'utf8');
  publicKeyPem = fs.readFileSync(PUB_KEY_PATH, 'utf8');
} else {
  console.log('Generating fresh RSA 2048 keypair...');
  const pair = crypto.generateKeyPairSync('rsa', {
    modulusLength: 2048,
    publicKeyEncoding: { type: 'spki', format: 'pem' },
    privateKeyEncoding: { type: 'pkcs8', format: 'pem' }
  });
  privateKeyPem = pair.privateKey;
  publicKeyPem = pair.publicKey;
}

// All modular features available in the system
const ALL_MODULES = [
  { id: 'pos', name: 'الفواتير ونقاط البيع', core: true },
  { id: 'cash_sales', name: 'المبيعات النقدية', core: true },
  { id: 'inventory', name: 'المخزون والأصناف', core: true },
  { id: 'customers', name: 'إدارة العملاء', core: false },
  { id: 'suppliers', name: 'إدارة الموردين والمشتريات', core: false },
  { id: 'credit_sales', name: 'المبيعات الآجلة وحسابات الديون', core: false },
  { id: 'reports', name: 'التقارير الأساسية', core: true },
  { id: 'advanced_reports', name: 'التقارير المتقدمة والأرباح', core: false },
  { id: 'staff_management', name: 'إدارة الموظفين والورديات', core: false },
  { id: 'attendance', name: 'تسجيل الحضور والانصراف', core: false },
  { id: 'payroll', name: 'المرتبات والخصومات والسلف', core: false },
  { id: 'custody', name: 'العهد المالية', core: false },
  { id: 'damaged_goods', name: 'الهوالك والتوالف', core: false },
  { id: 'manufacturing', name: 'التصنيع ووصفات الإنتاج (BOM)', core: false },
  { id: 'auto_backup', name: 'النسخ الاحتياطي التلقائي', core: false }
];

// 2. Load or Initialize Local Database
let db = {
  licenses: [
    {
      id: '1',
      license_key: 'MO2-TEST-0001',
      customer_name: 'سوبرماركت الأمل (كل الموديولات)',
      phone: '01000000000',
      plan: 'standard',
      features: ALL_MODULES.map(m => m.id),
      max_devices: 1,
      expires_at: null, // lifetime
      status: 'active',
      created_at: new Date().toISOString()
    },
    {
      id: '2',
      license_key: 'MO2-TEST-BASIC',
      customer_name: 'محل تجريبي (بدون تصنيع وبدون موظفين)',
      phone: '01111111111',
      plan: 'basic',
      features: ['pos', 'cash_sales', 'inventory', 'customers', 'suppliers', 'reports'],
      max_devices: 1,
      expires_at: new Date(Date.now() + 30 * 24 * 3600 * 1000).toISOString(),
      status: 'active',
      created_at: new Date().toISOString()
    }
  ],
  devices: [],
  events: []
};

if (fs.existsSync(DB_FILE)) {
  try {
    db = JSON.parse(fs.readFileSync(DB_FILE, 'utf8'));
  } catch (e) {
    console.error('Error loading simulator_db.json, using defaults');
  }
}

function saveDb() {
  fs.writeFileSync(DB_FILE, JSON.stringify(db, null, 2), 'utf8');
}

// 3. JWT RS256 Signer
function createSignedLease(payload) {
  const header = { alg: 'RS256', typ: 'JWT' };
  const b64 = obj => Buffer.from(JSON.stringify(obj)).toString('base64url');
  const unsignedToken = `${b64(header)}.${b64(payload)}`;

  const signer = crypto.createSign('RSA-SHA256');
  signer.update(unsignedToken);
  const signature = signer.sign(privateKeyPem, 'base64url');

  return `${unsignedToken}.${signature}`;
}

// 4. HTTP Server
const server = http.createServer((req, res) => {
  // CORS Headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    res.writeHead(200);
    return res.end();
  }

  // API Endpoint: /license_api
  if (req.url === '/license_api' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      try {
        const data = JSON.parse(body);
        const { action, license_key, machine_guid, install_uuid, device_name, platform, app_version } = data;

        console.log(`[API ${action ? action.toUpperCase() : 'UNKNOWN'}] Key: ${license_key} | Machine: ${machine_guid} | Install: ${install_uuid}`);

        const lic = db.licenses.find(l => l.license_key === license_key);
        if (!lic) {
          res.writeHead(404, { 'Content-Type': 'application/json' });
          return res.end(JSON.stringify({ error: 'Invalid license key' }));
        }

        if (lic.status !== 'active') {
          res.writeHead(403, { 'Content-Type': 'application/json' });
          return res.end(JSON.stringify({ error: `License is ${lic.status}` }));
        }

        if (lic.expires_at && new Date(lic.expires_at) < new Date()) {
          res.writeHead(403, { 'Content-Type': 'application/json' });
          return res.end(JSON.stringify({ error: 'License expired' }));
        }

        // Device matching
        let dev = db.devices.find(d => 
          d.license_id === lic.id && 
          ((machine_guid && d.machine_guid === machine_guid) || (install_uuid && d.install_uuid === install_uuid))
        );

        if (!dev) {
          const activeDevs = db.devices.filter(d => d.license_id === lic.id && d.status === 'active');
          if (activeDevs.length >= (lic.max_devices || 1)) {
            res.writeHead(403, { 'Content-Type': 'application/json' });
            return res.end(JSON.stringify({ error: 'Device limit reached for this license. Contact support to transfer.' }));
          }

          dev = {
            id: 'dev_' + Date.now(),
            license_id: lic.id,
            machine_guid: machine_guid || '',
            install_uuid: install_uuid || '',
            device_name: device_name || 'Device',
            platform: platform || 'unknown',
            app_version: app_version || '1.0.0',
            status: 'active',
            first_seen: new Date().toISOString(),
            last_seen: new Date().toISOString()
          };
          db.devices.push(dev);
        } else {
          dev.last_seen = new Date().toISOString();
          if (machine_guid) dev.machine_guid = machine_guid;
          if (install_uuid) dev.install_uuid = install_uuid;
          if (device_name) dev.device_name = device_name;
        }

        saveDb();

        if (dev.status !== 'active') {
          res.writeHead(403, { 'Content-Type': 'application/json' });
          return res.end(JSON.stringify({ error: 'Device blocked' }));
        }

        // Generate lease (30 days or license expiry)
        const leaseDays = 30;
        let leaseExpiry = new Date(Date.now() + leaseDays * 24 * 3600 * 1000);
        if (lic.expires_at && new Date(lic.expires_at) < leaseExpiry) {
          leaseExpiry = new Date(lic.expires_at);
        }

        const nowSec = Math.floor(Date.now() / 1000);
        const expSec = Math.floor(leaseExpiry.getTime() / 1000);

        const leaseToken = createSignedLease({
          license_key: lic.license_key,
          machine_guid: machine_guid || dev.machine_guid,
          install_uuid: install_uuid || dev.install_uuid,
          plan: lic.plan,
          features: lic.features,
          license_expires_at: lic.expires_at,
          status: 'active',
          iat: nowSec,
          exp: expSec
        });

        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({
          status: 'success',
          lease_token: leaseToken,
          expires_at: leaseExpiry.toISOString(),
          server_time: new Date().toISOString()
        }));

      } catch (e) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: e.message }));
      }
    });
    return;
  }

  // React Admin Dashboard REST APIs
  if (req.url === '/admin/licenses' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    const enriched = db.licenses.map(lic => ({
      ...lic,
      client_name: lic.customer_name || lic.client_name,
      client_phone: lic.phone || lic.client_phone,
      bound_devices_count: db.devices.filter(d => d.license_id === lic.id && d.status === 'active').length
    }));
    return res.end(JSON.stringify({ licenses: enriched, devices: db.devices }));
  }

  if (req.url === '/admin/licenses' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      const data = JSON.parse(body);
      const randomKey = 'POS-' + crypto.randomBytes(2).toString('hex').toUpperCase() + '-' + crypto.randomBytes(2).toString('hex').toUpperCase() + '-' + crypto.randomBytes(2).toString('hex').toUpperCase();
      const newLic = {
        id: String(Date.now()),
        license_key: data.license_key || randomKey,
        customer_name: data.client_name || data.customer_name || 'عميل جديد',
        client_name: data.client_name || data.customer_name || 'عميل جديد',
        phone: data.client_phone || data.phone || '',
        client_phone: data.client_phone || data.phone || '',
        plan: data.plan || 'yearly',
        features: Array.isArray(data.features) ? data.features : ['pos', 'cash_sales', 'inventory', 'reports'],
        max_devices: parseInt(data.max_devices) || 1,
        expires_at: data.expires_at || null,
        status: data.status || 'active',
        notes: data.notes || '',
        created_at: new Date().toISOString()
      };
      db.licenses.unshift(newLic);
      saveDb();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify(newLic));
    });
    return;
  }

  if (req.url.startsWith('/admin/licenses/') && req.method === 'PATCH') {
    const id = req.url.split('/admin/licenses/')[1].split('?')[0];
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      const updates = JSON.parse(body);
      const lic = db.licenses.find(l => l.id === id);
      if (lic) {
        if (updates.features) lic.features = updates.features;
        if (updates.status) lic.status = updates.status;
        if (updates.client_name) { lic.client_name = updates.client_name; lic.customer_name = updates.client_name; }
        if (updates.client_phone) { lic.client_phone = updates.client_phone; lic.phone = updates.client_phone; }
        if (updates.expires_at !== undefined) lic.expires_at = updates.expires_at;
        if (updates.max_devices !== undefined) lic.max_devices = updates.max_devices;
        if (updates.notes !== undefined) lic.notes = updates.notes;
        saveDb();
        res.writeHead(200, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify(lic));
      }
      res.writeHead(404, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'License not found' }));
    });
    return;
  }

  // Dashboard REST APIs
  if (req.url === '/api/licenses' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ ...db, allModules: ALL_MODULES }));
  }

  if (req.url === '/api/create_license' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      const data = JSON.parse(body);
      const randomKey = 'MO2-' + crypto.randomBytes(3).toString('hex').toUpperCase() + '-' + crypto.randomBytes(3).toString('hex').toUpperCase();
      const newLic = {
        id: String(Date.now()),
        license_key: data.license_key || randomKey,
        customer_name: data.customer_name || 'عميل جديد',
        phone: data.phone || '',
        plan: data.plan || 'custom',
        features: Array.isArray(data.features) ? data.features : ['pos', 'cash_sales', 'inventory', 'reports'],
        max_devices: parseInt(data.max_devices) || 1,
        expires_at: data.days ? new Date(Date.now() + parseInt(data.days) * 24 * 3600 * 1000).toISOString() : null,
        status: 'active',
        created_at: new Date().toISOString()
      };
      db.licenses.unshift(newLic);
      saveDb();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ success: true, license: newLic }));
    });
    return;
  }

  if (req.url === '/api/update_features' && req.method === 'POST') {
    let body = '';
    req.on('data', chunk => { body += chunk; });
    req.on('end', () => {
      const data = JSON.parse(body);
      const lic = db.licenses.find(l => l.id === data.id);
      if (lic) {
        lic.features = data.features;
        saveDb();
        console.log(`[UPDATE FEATURES] License ${lic.license_key} updated to:`, lic.features);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ success: true, features: lic.features }));
      }
      res.writeHead(404);
      return res.end();
    });
    return;
  }

  if (req.url.startsWith('/api/toggle_status') && req.method === 'POST') {
    const url = new URL(req.url, `http://localhost:${PORT}`);
    const id = url.searchParams.get('id');
    const lic = db.licenses.find(l => l.id === id);
    if (lic) {
      lic.status = lic.status === 'active' ? 'suspended' : 'active';
      saveDb();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      return res.end(JSON.stringify({ success: true, status: lic.status }));
    }
    res.writeHead(404);
    return res.end();
  }

  if (req.url.startsWith('/api/delete_device') && req.method === 'POST') {
    const url = new URL(req.url, `http://localhost:${PORT}`);
    const id = url.searchParams.get('id');
    db.devices = db.devices.filter(d => d.id !== id);
    saveDb();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ success: true }));
  }

  // Serve React Admin Dashboard static files and SPA fallback
  const DIST_DIR = path.join(__dirname, '..', 'admin_dashboard', 'dist');
  const safePath = path.normalize(req.url.split('?')[0]);
  const requestedFile = path.join(DIST_DIR, safePath === '/' ? 'index.html' : safePath);

  if (fs.existsSync(requestedFile) && fs.statSync(requestedFile).isFile()) {
    const ext = path.extname(requestedFile).toLowerCase();
    const mimeTypes = {
      '.html': 'text/html; charset=utf-8',
      '.js': 'application/javascript; charset=utf-8',
      '.css': 'text/css; charset=utf-8',
      '.svg': 'image/svg+xml',
      '.png': 'image/png',
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.ico': 'image/x-icon',
      '.json': 'application/json',
      '.woff2': 'font/woff2'
    };
    res.writeHead(200, { 'Content-Type': mimeTypes[ext] || 'application/octet-stream' });
    return fs.createReadStream(requestedFile).pipe(res);
  }

  // SPA fallback for non-API HTML requests
  const isApi = req.url.startsWith('/admin/') || req.url.startsWith('/api/') || req.url.startsWith('/license_api');
  if (req.method === 'GET' && !isApi) {
    if (fs.existsSync(path.join(DIST_DIR, 'index.html'))) {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      return fs.createReadStream(path.join(DIST_DIR, 'index.html')).pipe(res);
    } else {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      return res.end(`
        <div style="font-family:Cairo,sans-serif; text-align:center; padding:60px 20px; direction:rtl; background:#f8fafc; color:#0f172a; min-height:100vh;">
          <h2 style="font-size:24px; font-weight:bold; margin-bottom:12px;">لوحة تحكم مدار ERP السحابية</h2>
          <p style="color:#64748b; font-size:15px; margin-bottom:24px;">يرجى تجميع حزمة لوحة التحكم (Build) أولاً عبر تشغيل الأمر:</p>
          <div style="background:#fff; border:1px solid #e2e8f0; display:inline-block; padding:12px 24px; border-radius:8px; font-family:monospace; font-weight:bold; color:#1677ff;">
            cd admin_dashboard && npm run build
          </div>
          <p style="color:#94a3b8; font-size:13px; margin-top:24px;">أو تشغيل خادم التطوير المباشر عبر: <code>cd admin_dashboard && npm run dev</code></p>
        </div>
      `);
    }
  }

  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Endpoint not found' }));
});

server.listen(PORT, () => {
  console.log(`=======================================================`);
  console.log(`🚀 خادم محاكاة التراخيص والموديولات يعمل الآن بنجاح!`);
  console.log(`📡 نقطة اتصال API للتطبيق: http://localhost:${PORT}/license_api`);
  console.log(`🖥️ لوحة التحكم التفاعلية بالمتصفح: http://localhost:${PORT}`);
  console.log(`=======================================================`);
});
