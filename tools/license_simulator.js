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

  // Serve React Admin Dashboard static assets if built
  const DIST_DIR = path.join(__dirname, '..', 'admin_dashboard', 'dist');
  if (req.url.startsWith('/assets/')) {
    const filePath = path.join(DIST_DIR, req.url);
    if (fs.existsSync(filePath)) {
      const ext = path.extname(filePath);
      const mimeTypes = {
        '.js': 'application/javascript',
        '.css': 'text/css',
        '.svg': 'image/svg+xml',
        '.png': 'image/png',
        '.woff2': 'font/woff2'
      };
      res.writeHead(200, { 'Content-Type': mimeTypes[ext] || 'application/octet-stream' });
      return fs.createReadStream(filePath).pipe(res);
    }
  }

  // Serve React Admin Dashboard at / or /app
  if ((req.url === '/' || req.url === '/app') && fs.existsSync(path.join(DIST_DIR, 'index.html'))) {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return fs.createReadStream(path.join(DIST_DIR, 'index.html')).pipe(res);
  }

  // Classic Mini Web Dashboard (available at /legacy)
  if ((req.url === '/legacy' || req.url === '/') && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return res.end(`
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <title>لوحة التحكم في الموديولات والتراخيص</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <style>body { font-family: system-ui, sans-serif; }</style>
</head>
<body class="bg-gray-50 text-gray-800 p-6">
  <div class="max-w-7xl mx-auto space-y-6">
    <div class="flex flex-wrap justify-between items-center bg-white p-6 rounded-2xl shadow-sm border border-gray-100 gap-4">
      <div>
        <h1 class="text-2xl font-bold text-gray-900">لوحة تحكم خادم التراخيص والموديولات</h1>
        <p class="text-sm text-gray-500 mt-1">يمكنك فتح وقفل الموديولات (التصنيع، الموظفين، العهد...) لكل عميل على حدة بضغطة زر</p>
      </div>
      <button onclick="openCreateModal()" class="bg-indigo-600 hover:bg-indigo-700 text-white font-medium px-5 py-2.5 rounded-xl shadow-sm transition">
        + إنشاء ترخيص جديد
      </button>
    </div>

    <!-- Instructions Banner -->
    <div class="bg-blue-50 border border-blue-200 text-blue-900 p-4 rounded-xl text-sm leading-relaxed">
      💡 <strong>نقطة الاتصال بالتطبيق:</strong> <code class="bg-blue-100 text-blue-800 font-mono px-2 py-0.5 rounded">http://localhost:${PORT}/license_api</code><br>
      لتشغيل التطبيق وربطه فوراً بهذا المحاكي:
      <div class="mt-2 bg-blue-950 text-blue-100 font-mono p-2.5 rounded text-xs select-all">
        flutter run -d windows --dart-define=LICENSE_API_URL=http://localhost:${PORT}/license_api
      </div>
    </div>

    <!-- Licenses Table -->
    <div class="bg-white rounded-2xl shadow-sm border border-gray-100 overflow-hidden">
      <div class="p-4 border-b border-gray-100 font-semibold text-gray-700 flex justify-between items-center">
        <span>قائمة التراخيص والموديولات المفعلة</span>
        <button onclick="loadData()" class="text-xs text-indigo-600 hover:underline">تحديث البيانات 🔄</button>
      </div>
      <div class="overflow-x-auto">
        <table class="w-full text-right text-sm">
          <thead class="bg-gray-50 text-gray-500 font-medium">
            <tr>
              <th class="p-4">مفتاح الترخيص</th>
              <th class="p-4">العميل</th>
              <th class="p-4">الموديولات المتاحة</th>
              <th class="p-4">الانتهاء</th>
              <th class="p-4">الحالة</th>
              <th class="p-4">الأجهزة المرتبطة</th>
              <th class="p-4">الإجراءات</th>
            </tr>
          </thead>
          <tbody id="licensesTable" class="divide-y divide-gray-100"></tbody>
        </table>
      </div>
    </div>
  </div>

  <!-- Create Modal -->
  <div id="createModal" class="fixed inset-0 bg-black/40 hidden items-center justify-center p-4 z-50">
    <div class="bg-white rounded-2xl max-w-lg w-full p-6 space-y-4 max-h-[90vh] overflow-y-auto">
      <h3 class="text-lg font-bold">إنشاء ترخيص مخصص</h3>
      <div>
        <label class="block text-xs font-semibold text-gray-600 mb-1">اسم العميل</label>
        <input id="newCustomer" type="text" placeholder="مثال: مصنع الأمل" class="w-full border rounded-lg p-2.5 text-sm">
      </div>
      <div>
        <label class="block text-xs font-semibold text-gray-600 mb-1">رقم الهاتف</label>
        <input id="newPhone" type="text" placeholder="010..." class="w-full border rounded-lg p-2.5 text-sm">
      </div>
      <div>
        <label class="block text-xs font-semibold text-gray-600 mb-1">المدة</label>
        <select id="newDays" class="w-full border rounded-lg p-2.5 text-sm">
          <option value="14">تجربة (14 يوم)</option>
          <option value="30">شهر (30 يوم)</option>
          <option value="365">سنة (365 يوم)</option>
          <option value="">مدى الحياة (Lifetime)</option>
        </select>
      </div>
      <div>
        <label class="block text-xs font-semibold text-gray-600 mb-2">الموديولات المسموح بها لهذا العميل:</label>
        <div id="createModulesList" class="grid grid-cols-1 sm:grid-cols-2 gap-2 bg-gray-50 p-3 rounded-xl border max-h-56 overflow-y-auto"></div>
      </div>
      <div class="flex justify-end gap-2 pt-2">
        <button onclick="closeCreateModal()" class="px-4 py-2 border rounded-lg text-sm text-gray-600 hover:bg-gray-50">إلغاء</button>
        <button onclick="submitNewLicense()" class="px-5 py-2 bg-indigo-600 text-white rounded-lg text-sm font-medium hover:bg-indigo-700">إنشاء المفتاح</button>
      </div>
    </div>
  </div>

  <!-- Edit Modules Modal -->
  <div id="editModulesModal" class="fixed inset-0 bg-black/40 hidden items-center justify-center p-4 z-50">
    <div class="bg-white rounded-2xl max-w-lg w-full p-6 space-y-4 max-h-[90vh] overflow-y-auto">
      <h3 class="text-lg font-bold">تعديل الموديولات للعميل: <span id="editCustomerName" class="text-indigo-600"></span></h3>
      <input type="hidden" id="editLicenseId">
      <p class="text-xs text-gray-500">اختر أو ألغِ الموديولات، وسيطبق التعديل تلقائياً على برنامج العميل فور اتصاله بالإنترنت:</p>
      <div id="editModulesList" class="grid grid-cols-1 sm:grid-cols-2 gap-2 bg-gray-50 p-3 rounded-xl border max-h-64 overflow-y-auto"></div>
      <div class="flex justify-end gap-2 pt-2">
        <button onclick="closeEditModal()" class="px-4 py-2 border rounded-lg text-sm text-gray-600 hover:bg-gray-50">إلغاء</button>
        <button onclick="submitUpdateFeatures()" class="px-5 py-2 bg-emerald-600 text-white rounded-lg text-sm font-medium hover:bg-emerald-700">حفظ التعديلات فوراً</button>
      </div>
    </div>
  </div>

  <script>
    let currentData = { licenses: [], devices: [], allModules: [] };

    async function loadData() {
      const res = await fetch('/api/licenses');
      currentData = await res.json();
      renderTable();
      renderCreateModules();
    }

    function renderCreateModules() {
      const container = document.getElementById('createModulesList');
      container.innerHTML = currentData.allModules.map(m => \`
        <label class="flex items-center gap-2 text-xs p-1.5 hover:bg-white rounded cursor-pointer">
          <input type="checkbox" name="createModule" value="\${m.id}" \${m.core ? 'checked' : ''} class="rounded text-indigo-600">
          <span>\${m.name}</span>
        </label>
      \`).join('');
    }

    function renderTable() {
      const tbody = document.getElementById('licensesTable');
      tbody.innerHTML = '';

      currentData.licenses.forEach(l => {
        const devs = currentData.devices.filter(d => d.license_id === l.id);
        const expText = l.expires_at ? new Date(l.expires_at).toLocaleDateString('ar-EG') : 'مدى الحياة';
        const isSusp = l.status === 'suspended';

        let devHtml = devs.length ? devs.map(d => \`
          <div class="text-xs bg-gray-50 border rounded p-1.5 mb-1 flex justify-between items-center">
            <span>💻 \${d.device_name} (\${d.platform})</span>
            <button onclick="deleteDevice('\${d.id}')" class="text-red-500 hover:underline mr-2">فك الارتباط</button>
          </div>
        \`).join('') : '<span class="text-gray-400 text-xs">لا يوجد جهاز مرتبط بعد</span>';

        // Badges for active features
        const featBadges = (l.features || []).map(fid => {
          const mod = currentData.allModules.find(m => m.id === fid);
          return \`<span class="inline-block bg-indigo-50 text-indigo-700 text-[10px] px-1.5 py-0.5 rounded mr-1 mb-1 font-medium">\${mod ? mod.name : fid}</span>\`;
        }).join('');

        tbody.innerHTML += \`
          <tr class="hover:bg-gray-50/60 transition">
            <td class="p-4 font-mono text-xs font-bold text-indigo-700 select-all">\${l.license_key}</td>
            <td class="p-4 font-medium">\${l.customer_name}<div class="text-xs text-gray-400">\${l.phone || ''}</div></td>
            <td class="p-4 max-w-sm">
              <div class="flex flex-wrap max-h-20 overflow-y-auto mb-1">\${featBadges}</div>
              <button onclick="openEditModal('\${l.id}')" class="text-[11px] text-indigo-600 hover:underline font-semibold">تعديل الموديولات ⚙️</button>
            </td>
            <td class="p-4 text-xs font-medium">\${expText}</td>
            <td class="p-4">
              <span class="px-2.5 py-1 rounded-full text-xs font-semibold \${isSusp ? 'bg-red-100 text-red-700' : 'bg-emerald-100 text-emerald-700'}">
                \${isSusp ? 'موقوف ⛔' : 'نشط ✅'}
              </span>
            </td>
            <td class="p-4 max-w-xs">\${devHtml}</td>
            <td class="p-4">
              <button onclick="toggleStatus('\${l.id}')" class="text-xs px-3 py-1.5 rounded-lg border font-medium transition \${isSusp ? 'border-emerald-500 text-emerald-600 hover:bg-emerald-50' : 'border-red-500 text-red-600 hover:bg-red-50'}">
                \${isSusp ? 'تفعيل' : 'إيقاف'}
              </button>
            </td>
          </tr>
        \`;
      });
    }

    function openEditModal(licenseId) {
      const lic = currentData.licenses.find(l => l.id === licenseId);
      if (!lic) return;
      document.getElementById('editLicenseId').value = lic.id;
      document.getElementById('editCustomerName').textContent = lic.customer_name;

      const container = document.getElementById('editModulesList');
      container.innerHTML = currentData.allModules.map(m => {
        const checked = (lic.features || []).includes(m.id);
        return \`
          <label class="flex items-center gap-2 text-xs p-2 hover:bg-white rounded-lg border cursor-pointer">
            <input type="checkbox" name="editModule" value="\${m.id}" \${checked ? 'checked' : ''} class="rounded text-indigo-600">
            <span class="\${checked ? 'font-bold text-gray-900' : 'text-gray-600'}">\${m.name}</span>
          </label>
        \`;
      }).join('');

      document.getElementById('editModulesModal').classList.remove('hidden');
      document.getElementById('editModulesModal').classList.add('flex');
    }

    function closeEditModal() {
      document.getElementById('editModulesModal').classList.add('hidden');
      document.getElementById('editModulesModal').classList.remove('flex');
    }

    async function submitUpdateFeatures() {
      const id = document.getElementById('editLicenseId').value;
      const checkedBoxes = document.querySelectorAll('input[name="editModule"]:checked');
      const features = Array.from(checkedBoxes).map(cb => cb.value);

      await fetch('/api/update_features', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id, features })
      });
      closeEditModal();
      loadData();
    }

    function openCreateModal() { document.getElementById('createModal').classList.remove('hidden'); document.getElementById('createModal').classList.add('flex'); }
    function closeCreateModal() { document.getElementById('createModal').classList.add('hidden'); document.getElementById('createModal').classList.remove('flex'); }

    async function submitNewLicense() {
      const name = document.getElementById('newCustomer').value;
      const phone = document.getElementById('newPhone').value;
      const days = document.getElementById('newDays').value;
      const checkedBoxes = document.querySelectorAll('input[name="createModule"]:checked');
      const features = Array.from(checkedBoxes).map(cb => cb.value);

      await fetch('/api/create_license', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ customer_name: name, phone, days, features })
      });
      closeCreateModal();
      loadData();
    }

    async function toggleStatus(id) {
      await fetch('/api/toggle_status?id=' + id, { method: 'POST' });
      loadData();
    }

    async function deleteDevice(id) {
      if (confirm('هل تريد فك ارتباط هذا الجهاز؟ سيتمكن العميل من التفعيل على جهاز جديد.')) {
        await fetch('/api/delete_device?id=' + id, { method: 'POST' });
        loadData();
      }
    }

    loadData();
  </script>
</body>
</html>
    `);
  }

  res.writeHead(404);
  res.end('Not Found');
});

server.listen(PORT, () => {
  console.log(`=======================================================`);
  console.log(`🚀 خادم محاكاة التراخيص والموديولات يعمل الآن بنجاح!`);
  console.log(`📡 نقطة اتصال API للتطبيق: http://localhost:${PORT}/license_api`);
  console.log(`🖥️ لوحة التحكم التفاعلية بالمتصفح: http://localhost:${PORT}`);
  console.log(`=======================================================`);
});
