import React, { useState, useEffect } from 'react';
import Sidebar from './components/Sidebar';
import Header from './components/Header';
import StatsGrid from './components/StatsGrid';
import LicenseTable from './components/LicenseTable';
import OverviewView from './components/OverviewView';
import ConnectedDevicesView from './components/ConnectedDevicesView';
import ModulesCatalogView from './components/ModulesCatalogView';
import AuditLogsView from './components/AuditLogsView';
import LicenseModal from './components/LicenseModal';
import DevicesModal from './components/DevicesModal';
import ConfigModal from './components/ConfigModal';
import Toast from './components/Toast';
import { api } from './services/api';

export default function App() {
  const [currentTab, setCurrentTab] = useState('licenses');
  const [isSidebarOpen, setIsSidebarOpen] = useState(false);
  const [theme, setTheme] = useState(() => localStorage.getItem('pos_admin_theme') || 'dark');
  
  const [licenses, setLicenses] = useState([]);
  const [loading, setLoading] = useState(true);
  const [config, setConfig] = useState(() => api.loadConfig());
  const [searchQuery, setSearchQuery] = useState('');
  
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

  // Sync theme with HTML root class
  useEffect(() => {
    if (theme === 'dark') {
      document.documentElement.classList.add('dark');
    } else {
      document.documentElement.classList.remove('dark');
    }
    localStorage.setItem('pos_admin_theme', theme);
  }, [theme]);

  const toggleTheme = () => {
    setTheme(prev => (prev === 'dark' ? 'light' : 'dark'));
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

  const handleUnbindFromView = async (device) => {
    if (!confirm(`هل تريد فك ارتباط هذا الجهاز؟ سيتم تحرير خانة ترخيص للعميل.`)) return;
    try {
      await api.unbindDevice(device.id);
      showToast('تم إلغاء ربط الجهاز بنجاح');
      fetchLicenses();
    } catch (e) {
      showToast('فشل إلغاء الربط: ' + e.message, 'error');
    }
  };

  const totalDevices = licenses.reduce((sum, l) => sum + (l.bound_devices_count || 0), 0);

  return (
    <div className="min-h-screen bg-slate-50 dark:bg-[#0B0F19] text-slate-900 dark:text-gray-100 font-arabic flex transition-colors duration-200">
      
      {/* Collapsible Sidebar (Drawer on mobile) */}
      <Sidebar
        currentTab={currentTab}
        setCurrentTab={(tab) => {
          if (tab === 'settings') {
            setIsConfigModalOpen(true);
          } else {
            setCurrentTab(tab);
          }
        }}
        isOpen={isSidebarOpen}
        setIsOpen={setIsSidebarOpen}
        theme={theme}
        toggleTheme={toggleTheme}
        licenseCount={licenses.length}
        deviceCount={totalDevices}
      />

      {/* Main Content Area (Offset by Sidebar on lg screens) */}
      <div className="flex-1 lg:mr-72 flex flex-col min-h-screen">
        
        {/* Top App Bar Header */}
        <Header
          onToggleSidebar={() => setIsSidebarOpen(prev => !prev)}
          config={config}
          onOpenConfig={() => setIsConfigModalOpen(true)}
          onOpenCreate={() => {
            setEditingLicense(null);
            setIsLicenseModalOpen(true);
          }}
          onRefresh={fetchLicenses}
          loading={loading}
          searchQuery={searchQuery}
          setSearchQuery={setSearchQuery}
          theme={theme}
          toggleTheme={toggleTheme}
        />

        {/* Dynamic Views */}
        <main className="flex-1 max-w-7xl w-full mx-auto px-4 sm:px-6 lg:px-8 py-6 sm:py-8">
          
          {currentTab === 'licenses' && (
            <div className="space-y-6">
              <StatsGrid licenses={licenses} />
              <LicenseTable
                licenses={licenses}
                onEdit={handleOpenEdit}
                onManageDevices={handleOpenDevices}
                onToggleStatus={handleToggleStatus}
                onDelete={handleDelete}
                onCopyKey={handleCopyKey}
                searchQuery={searchQuery}
                setSearchQuery={setSearchQuery}
              />
            </div>
          )}

          {currentTab === 'overview' && (
            <div className="space-y-6">
              <StatsGrid licenses={licenses} />
              <OverviewView
                licenses={licenses}
                onOpenCreate={() => {
                  setEditingLicense(null);
                  setIsLicenseModalOpen(true);
                }}
                onGoToLicenses={() => setCurrentTab('licenses')}
              />
            </div>
          )}

          {currentTab === 'devices' && (
            <ConnectedDevicesView
              licenses={licenses}
              onUnbindDevice={handleUnbindFromView}
            />
          )}

          {currentTab === 'modules' && (
            <ModulesCatalogView
              licenses={licenses}
              onSelectModuleFilter={() => setCurrentTab('licenses')}
            />
          )}

          {currentTab === 'audit' && (
            <AuditLogsView licenses={licenses} />
          )}

        </main>

        {/* Footer */}
        <footer className="border-t border-slate-200/80 dark:border-white/5 py-5 text-center text-xs text-slate-500 dark:text-gray-500">
          <p>لوحة تحكم تراخيص نقاط البيع (POS Cloud Manager) — متوافقة مع Cloudflare Pages & Supabase</p>
        </footer>

      </div>

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
