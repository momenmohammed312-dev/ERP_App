import React, { useState, useEffect } from 'react';
import Header from './components/Header';
import StatsGrid from './components/StatsGrid';
import LicenseTable from './components/LicenseTable';
import LicenseModal from './components/LicenseModal';
import DevicesModal from './components/DevicesModal';
import ConfigModal from './components/ConfigModal';
import Toast from './components/Toast';
import { api } from './services/api';

export default function App() {
  const [licenses, setLicenses] = useState([]);
  const [loading, setLoading] = useState(true);
  const [config, setConfig] = useState(() => api.loadConfig());
  
  // Modals state
  const [isLicenseModalOpen, setIsLicenseModalOpen] = useState(false);
  const [editingLicense, setEditingLicense] = useState(null);
  
  const [isDevicesModalOpen, setIsDevicesModalOpen] = useState(false);
  const [selectedLicenseForDevices, setSelectedLicenseForDevices] = useState(null);
  
  const [isConfigModalOpen, setIsConfigModalOpen] = useState(false);

  // Toast state
  const [toast, setToast] = useState(null);

  const showToast = (message, type = 'success') => {
    setToast({ message, type });
    setTimeout(() => setToast(null), 3500);
  };

  const fetchLicenses = async () => {
    setLoading(true);
    try {
      const data = await api.getLicenses();
      setLicenses(data);
    } catch (err) {
      console.error('Failed to load licenses:', err);
      showToast('تعذر جلب التراخيص: ' + (err.message || 'خطأ في الاتصال'), 'error');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchLicenses();
  }, []);

  const handleCreateOrUpdate = async (formData) => {
    try {
      if (editingLicense) {
        await api.updateLicense(editingLicense.id, formData);
        showToast('تم تحديث بيانات وميزات الترخيص بنجاح');
      } else {
        await api.createLicense(formData);
        showToast('تم إصدار الترخيص الجديد بنجاح');
      }
      setIsLicenseModalOpen(false);
      setEditingLicense(null);
      fetchLicenses();
    } catch (err) {
      showToast('حدث خطأ أثناء الحفظ: ' + err.message, 'error');
    }
  };

  const handleToggleStatus = async (license) => {
    const newStatus = license.status === 'active' ? 'suspended' : 'active';
    try {
      await api.updateLicense(license.id, { status: newStatus });
      showToast(newStatus === 'active' ? 'تم تنشيط الترخيص بنجاح' : 'تم تجميد الترخيص ومصادرة الصلاحيات');
      fetchLicenses();
    } catch (err) {
      showToast('فشل تعديل الحالة: ' + err.message, 'error');
    }
  };

  const handleDelete = async (license) => {
    if (!confirm(`هل أنت متأكد من حذف ترخيص "${license.client_name}"؟ هذا الإجراء لا يمكن التراجع عنه.`)) {
      return;
    }

    try {
      await api.deleteLicense(license.id);
      showToast('تم حذف الترخيص');
      fetchLicenses();
    } catch (err) {
      showToast('فشل حذف الترخيص: ' + err.message, 'error');
    }
  };

  const handleOpenEdit = (license) => {
    setEditingLicense(license);
    setIsLicenseModalOpen(true);
  };

  const handleOpenDevices = (license) => {
    setSelectedLicenseForDevices(license);
    setIsDevicesModalOpen(true);
  };

  const handleCopyKey = (key) => {
    showToast(`تم نسخ المفتاح للحافظة: ${key}`);
  };

  return (
    <div className="min-h-screen bg-[#0B0F19] text-gray-100 flex flex-col justify-between selection:bg-indigo-500/30">
      
      {/* Background radial gradient glow */}
      <div className="fixed inset-0 pointer-events-none overflow-hidden z-0">
        <div className="absolute -top-40 -left-40 w-96 h-96 bg-indigo-600/10 rounded-full blur-[128px]"></div>
        <div className="absolute top-1/3 -right-40 w-96 h-96 bg-purple-600/10 rounded-full blur-[128px]"></div>
      </div>

      <div className="relative z-10 flex-1">
        {/* Navbar */}
        <Header
          config={config}
          onOpenConfig={() => setIsConfigModalOpen(true)}
          onOpenCreate={() => {
            setEditingLicense(null);
            setIsLicenseModalOpen(true);
          }}
          onRefresh={fetchLicenses}
          loading={loading}
        />

        {/* Main Content Area */}
        <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
          
          {/* Stats Metrics */}
          <StatsGrid licenses={licenses} />

          {/* Licenses Table */}
          <LicenseTable
            licenses={licenses}
            onEdit={handleOpenEdit}
            onManageDevices={handleOpenDevices}
            onToggleStatus={handleToggleStatus}
            onDelete={handleDelete}
            onCopyKey={handleCopyKey}
          />

        </main>
      </div>

      {/* Footer */}
      <footer className="relative z-10 border-t border-white/5 py-6 text-center text-xs text-gray-500">
        <p>نظام إدارة تراخيص وتفعيل نقاط البيع سحابياً © 2026 — جاهز للنشر على Cloudflare Pages & Supabase</p>
      </footer>

      {/* Modals */}
      <LicenseModal
        isOpen={isLicenseModalOpen}
        onClose={() => {
          setIsLicenseModalOpen(false);
          setEditingLicense(null);
        }}
        onSave={handleCreateOrUpdate}
        editingLicense={editingLicense}
      />

      <DevicesModal
        isOpen={isDevicesModalOpen}
        onClose={() => {
          setIsDevicesModalOpen(false);
          setSelectedLicenseForDevices(null);
        }}
        license={selectedLicenseForDevices}
        onDeviceUnbound={fetchLicenses}
      />

      <ConfigModal
        isOpen={isConfigModalOpen}
        onClose={() => setIsConfigModalOpen(false)}
        onSaveConfig={(newConfig) => {
          setConfig(newConfig);
          fetchLicenses();
        }}
      />

      {/* Toast notifications */}
      <Toast toast={toast} onClose={() => setToast(null)} />

    </div>
  );
}
