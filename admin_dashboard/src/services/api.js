import { createClient } from '@supabase/supabase-js';

const CONFIG_KEY = 'pos_admin_config_v1';
const MOCK_STORAGE_KEY = 'pos_mock_licenses_v1';

// Default mock initial data if running locally without Supabase
const INITIAL_MOCK_LICENSES = [
  {
    id: 'lic-001',
    license_key: 'POS-DEMO-2026-X1',
    client_name: 'سوبر ماركت النور والبركة',
    client_phone: '01012345678',
    status: 'active',
    plan: 'yearly',
    expires_at: new Date(Date.now() + 180 * 24 * 3600 * 1000).toISOString(),
    max_devices: 2,
    bound_devices_count: 1,
    features: ['pos', 'cash_sales', 'credit_sales', 'inventory', 'customers', 'suppliers', 'reports', 'custody'],
    notes: 'عميل سنوي - تم إضافة العهد النثرية',
    created_at: new Date(Date.now() - 30 * 24 * 3600 * 1000).toISOString(),
  },
  {
    id: 'lic-002',
    license_key: 'POS-FACT-8890-M3',
    client_name: 'مصنع الأمل للحلويات والفرن',
    client_phone: '01198765432',
    status: 'active',
    plan: 'lifetime',
    expires_at: new Date(Date.now() + 3650 * 24 * 3600 * 1000).toISOString(),
    max_devices: 3,
    bound_devices_count: 2,
    features: ['pos', 'cash_sales', 'credit_sales', 'inventory', 'customers', 'suppliers', 'reports', 'manufacturing', 'staff_management', 'damaged_goods'],
    notes: 'باقة المصانع المتكاملة - مفعل له التصنيع والموظفين والهوالك',
    created_at: new Date(Date.now() - 60 * 24 * 3600 * 1000).toISOString(),
  },
  {
    id: 'lic-003',
    license_key: 'POS-TRIAL-3321-T9',
    client_name: 'محل البرنس للأدوات المنزلية (تجربة)',
    client_phone: '01234567890',
    status: 'active',
    plan: 'trial',
    expires_at: new Date(Date.now() + 10 * 24 * 3600 * 1000).toISOString(),
    max_devices: 1,
    bound_devices_count: 1,
    features: ['pos', 'cash_sales', 'inventory', 'customers'],
    notes: 'نسخة تجريبية مجانية 14 يوم - فقط الأساسيات بدون إضافات',
    created_at: new Date(Date.now() - 4 * 24 * 3600 * 1000).toISOString(),
  }
];

export class LicenseApiService {
  constructor() {
    this.config = this.loadConfig();
    this.supabase = null;
    this.initSupabase();
  }

  loadConfig() {
    try {
      const saved = localStorage.getItem(CONFIG_KEY);
      if (saved) return JSON.parse(saved);
    } catch (e) {
      console.error('Failed to load saved config:', e);
    }
    return {
      mode: 'simulator', // 'supabase' | 'simulator'
      supabaseUrl: import.meta.env.VITE_SUPABASE_URL || '',
      supabaseKey: import.meta.env.VITE_SUPABASE_KEY || '',
      simulatorUrl: 'http://localhost:8000',
    };
  }

  saveConfig(newConfig) {
    this.config = { ...this.config, ...newConfig };
    localStorage.setItem(CONFIG_KEY, JSON.stringify(this.config));
    this.initSupabase();
  }

  initSupabase() {
    if (this.config.mode === 'supabase' && this.config.supabaseUrl && this.config.supabaseKey) {
      try {
        this.supabase = createClient(this.config.supabaseUrl, this.config.supabaseKey);
      } catch (e) {
        console.error('Failed to initialize Supabase client:', e);
        this.supabase = null;
      }
    } else {
      this.supabase = null;
    }
  }

  // Generate standard random license key (e.g. POS-XXXX-XXXX-XXXX)
  generateRandomKey(prefix = 'POS') {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    const segment = (len = 4) => {
      let res = '';
      for (let i = 0; i < len; i++) {
        res += chars.charAt(Math.floor(Math.random() * chars.length));
      }
      return res;
    };
    return `${prefix}-${segment(4)}-${segment(4)}-${segment(4)}`;
  }

  // Local storage mock helpers
  _getMockLicenses() {
    try {
      const data = localStorage.getItem(MOCK_STORAGE_KEY);
      if (data) return JSON.parse(data);
    } catch (_) {}
    localStorage.setItem(MOCK_STORAGE_KEY, JSON.stringify(INITIAL_MOCK_LICENSES));
    return INITIAL_MOCK_LICENSES;
  }

  _saveMockLicenses(licenses) {
    localStorage.setItem(MOCK_STORAGE_KEY, JSON.stringify(licenses));
  }

  // --- Core API Methods ---

  async getLicenses() {
    if (this.supabase) {
      const { data, error } = await this.supabase
        .from('licenses')
        .select('*, devices(count)')
        .order('created_at', { ascending: false });

      if (error) throw error;
      return data.map(item => ({
        ...item,
        bound_devices_count: item.devices?.[0]?.count ?? 0,
      }));
    }

    // Try local simulator first if in simulator mode
    if (this.config.mode === 'simulator') {
      try {
        const res = await fetch(`${this.config.simulatorUrl}/admin/licenses`);
        if (res.ok) {
          const json = await res.json();
          return json.licenses;
        }
      } catch (_) {
        // Fallback to local storage if simulator is not running
      }
    }

    return this._getMockLicenses();
  }

  async createLicense(licenseData) {
    if (this.supabase) {
      const { data, error } = await this.supabase
        .from('licenses')
        .insert([{
          license_key: licenseData.license_key,
          client_name: licenseData.client_name,
          client_phone: licenseData.client_phone,
          status: licenseData.status || 'active',
          plan: licenseData.plan || 'yearly',
          expires_at: licenseData.expires_at,
          max_devices: licenseData.max_devices || 1,
          features: licenseData.features || [],
          notes: licenseData.notes || '',
        }])
        .select()
        .single();

      if (error) throw error;
      return data;
    }

    if (this.config.mode === 'simulator') {
      try {
        const res = await fetch(`${this.config.simulatorUrl}/admin/licenses`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(licenseData),
        });
        if (res.ok) {
          return await res.json();
        }
      } catch (_) {}
    }

    const licenses = this._getMockLicenses();
    const newRecord = {
      ...licenseData,
      id: 'lic-' + Date.now(),
      bound_devices_count: 0,
      created_at: new Date().toISOString(),
    };
    licenses.unshift(newRecord);
    this._saveMockLicenses(licenses);
    return newRecord;
  }

  async updateLicense(id, updates) {
    if (this.supabase) {
      const { data, error } = await this.supabase
        .from('licenses')
        .update(updates)
        .eq('id', id)
        .select()
        .single();

      if (error) throw error;
      return data;
    }

    if (this.config.mode === 'simulator') {
      try {
        const res = await fetch(`${this.config.simulatorUrl}/admin/licenses/${id}`, {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(updates),
        });
        if (res.ok) return await res.json();
      } catch (_) {}
    }

    const licenses = this._getMockLicenses();
    const index = licenses.findIndex(l => l.id === id);
    if (index !== -1) {
      licenses[index] = { ...licenses[index], ...updates };
      this._saveMockLicenses(licenses);
      return licenses[index];
    }
    throw new Error('الترخيص غير موجود');
  }

  async deleteLicense(id) {
    if (this.supabase) {
      const { error } = await this.supabase.from('licenses').delete().eq('id', id);
      if (error) throw error;
      return true;
    }

    const licenses = this._getMockLicenses().filter(l => l.id !== id);
    this._saveMockLicenses(licenses);
    return true;
  }

  async getDevices(licenseId) {
    if (this.supabase) {
      const { data, error } = await this.supabase
        .from('devices')
        .select('*')
        .eq('license_id', licenseId)
        .order('last_checkin_at', { ascending: false });

      if (error) throw error;
      return data;
    }

    // Mock devices
    return [
      {
        id: 'dev-1',
        license_id: licenseId,
        device_name: 'POS-CASHIER-MAIN (Windows 11)',
        machine_guid: '9A7B6C-WIN11-LOCAL-4819',
        install_uuid: 'uuid-desktop-pos-alpha',
        last_ip: '192.168.1.105',
        last_checkin_at: new Date(Date.now() - 3600 * 1000 * 2).toISOString(),
        created_at: new Date(Date.now() - 3600 * 1000 * 48).toISOString(),
      }
    ];
  }

  async unbindDevice(deviceId) {
    if (this.supabase) {
      const { error } = await this.supabase.from('devices').delete().eq('id', deviceId);
      if (error) throw error;
      return true;
    }
    return true;
  }
}

export const api = new LicenseApiService();
