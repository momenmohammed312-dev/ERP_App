import React, { useState } from 'react';
import { 
  Search, Copy, Check, Laptop, Clock, 
  Layers, Edit2, Trash2, PowerOff, CheckCircle2, 
  AlertCircle, Filter, Calendar, MoreHorizontal, Sparkles 
} from 'lucide-react';
import { ERP_MODULES } from '../config/modules';

export default function LicenseTable({ 
  licenses, 
  onEdit, 
  onManageDevices, 
  onToggleStatus, 
  onDelete, 
  onCopyKey,
  searchQuery,
  setSearchQuery,
  onQuickRenew
}) {
  const [filter, setFilter] = useState('all');
  const [selectedModuleFilter, setSelectedModuleFilter] = useState('all');
  const [copiedKey, setCopiedKey] = useState(null);

  const handleCopy = (key) => {
    navigator.clipboard.writeText(key);
    setCopiedKey(key);
    onCopyKey(key);
    setTimeout(() => setCopiedKey(null), 2000);
  };

  const getDaysRemaining = (expiryDate) => {
    if (!expiryDate) return 9999;
    const diff = new Date(expiryDate) - new Date();
    return Math.ceil(diff / (1000 * 60 * 60 * 24));
  };

  const filteredLicenses = licenses.filter(lic => {
    const matchesSearch = 
      lic.client_name?.toLowerCase().includes((searchQuery || '').toLowerCase()) ||
      lic.license_key?.toLowerCase().includes((searchQuery || '').toLowerCase()) ||
      lic.client_phone?.includes(searchQuery || '') ||
      lic.notes?.toLowerCase().includes((searchQuery || '').toLowerCase());

    const isExpired = lic.expires_at ? new Date(lic.expires_at) <= new Date() : false;
    const isSuspended = lic.status === 'suspended';
    const isTrial = lic.plan === 'trial';

    let matchesStatus = true;
    if (filter === 'active') matchesStatus = lic.status === 'active' && !isExpired;
    else if (filter === 'suspended') matchesStatus = isSuspended;
    else if (filter === 'expired') matchesStatus = isExpired;
    else if (filter === 'trial') matchesStatus = isTrial;

    let matchesModule = true;
    if (selectedModuleFilter !== 'all') {
      matchesModule = (lic.features || []).includes(selectedModuleFilter);
    }

    return matchesSearch && matchesStatus && matchesModule;
  });

  return (
    <div className="rounded-2xl border border-slate-200/80 dark:border-white/5 bg-white dark:bg-[#111827] shadow-sm overflow-hidden">
      
      {/* Table Toolbar & Filters (Mantis / Material Tabs) */}
      <div className="p-4 sm:p-5 border-b border-slate-200/80 dark:border-white/5 flex flex-col lg:flex-row lg:items-center justify-between gap-4">
        
        {/* Status Filter Tabs */}
        <div className="flex items-center gap-1 p-1 rounded-xl bg-slate-100 dark:bg-white/[0.04] border border-slate-200/60 dark:border-white/5 text-xs overflow-x-auto">
          {[
            { id: 'all', label: 'الكل' },
            { id: 'active', label: 'النشطة' },
            { id: 'suspended', label: 'المعلقة' },
            { id: 'expired', label: 'المنتهية' },
            { id: 'trial', label: 'التجريبية' },
          ].map((tab) => (
            <button
              key={tab.id}
              onClick={() => setFilter(tab.id)}
              className={`px-3 py-1.5 rounded-lg font-semibold transition-all whitespace-nowrap ${
                filter === tab.id
                  ? 'bg-white dark:bg-indigo-600 text-slate-900 dark:text-white shadow-sm'
                  : 'text-slate-500 dark:text-gray-400 hover:text-slate-900 dark:hover:text-white'
              }`}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {/* Search & Module Dropdown */}
        <div className="flex flex-col sm:flex-row items-stretch sm:items-center gap-2.5">
          
          {/* Module Filter */}
          <div className="relative">
            <select
              value={selectedModuleFilter}
              onChange={(e) => setSelectedModuleFilter(e.target.value)}
              className="w-full sm:w-auto px-3.5 py-2 rounded-xl bg-slate-50 dark:bg-white/[0.03] border border-slate-200 dark:border-white/10 text-xs font-medium text-slate-700 dark:text-gray-300 focus:outline-none focus:border-indigo-500"
            >
              <option value="all">تصفية بحسب الموديول (الكل)</option>
              {ERP_MODULES.map(m => (
                <option key={m.id} value={m.id}>
                  {m.name.split(' ')[0]} ({m.category === 'addon' ? 'إضافي' : 'أساسي'})
                </option>
              ))}
            </select>
          </div>

          {/* Search Box on mobile / table */}
          <div className="relative sm:w-64">
            <Search className="w-3.5 h-3.5 text-slate-400 dark:text-gray-500 absolute right-3 top-1/2 -translate-y-1/2" />
            <input
              type="text"
              placeholder="بحث في الجدول..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full pr-9 pl-3 py-2 rounded-xl bg-slate-50 dark:bg-white/[0.03] border border-slate-200 dark:border-white/10 text-xs text-slate-900 dark:text-white placeholder-slate-400 dark:placeholder-gray-500 focus:outline-none focus:border-indigo-500"
            />
          </div>

        </div>

      </div>

      {/* Table Content */}
      <div className="overflow-x-auto">
        <table className="w-full text-right text-xs">
          <thead>
            <tr className="border-b border-slate-200/80 dark:border-white/5 bg-slate-50/70 dark:bg-white/[0.01] text-[11px] font-bold text-slate-500 dark:text-gray-400 uppercase tracking-wider">
              <th className="py-3.5 px-5">العميل / المحل</th>
              <th className="py-3.5 px-5">مفتاح الترخيص</th>
              <th className="py-3.5 px-5">الباقة والصلاحية</th>
              <th className="py-3.5 px-5">الموديولات المتاحة</th>
              <th className="py-3.5 px-5">الأجهزة</th>
              <th className="py-3.5 px-5">الحالة</th>
              <th className="py-3.5 px-5 text-center">إجراءات سريعة</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-100 dark:divide-white/5">
            {filteredLicenses.length === 0 ? (
              <tr>
                <td colSpan="7" className="py-12 text-center text-slate-400 dark:text-gray-500">
                  <Layers className="w-8 h-8 mx-auto mb-2 opacity-40" />
                  <p className="text-xs font-medium">لا توجد تراخيص تطابق البحث الحالي</p>
                </td>
              </tr>
            ) : (
              filteredLicenses.map((lic) => {
                const days = getDaysRemaining(lic.expires_at);
                const isExpired = lic.expires_at ? days <= 0 : false;
                const isSuspended = lic.status === 'suspended';
                const isLifetime = !lic.expires_at || days > 3000;
                const featuresList = lic.features || [];

                return (
                  <tr key={lic.id} className="hover:bg-slate-50/80 dark:hover:bg-white/[0.02] transition-colors group">
                    
                    {/* Client Info */}
                    <td className="py-3.5 px-5">
                      <div className="font-bold text-slate-900 dark:text-white text-xs">
                        {lic.client_name || 'بدون اسم'}
                      </div>
                      <div className="text-[11px] text-slate-500 dark:text-gray-400 font-mono mt-0.5">
                        {lic.client_phone || 'لا يوجد هاتف'}
                      </div>
                      {lic.notes && (
                        <div className="text-[10px] text-slate-400 dark:text-gray-500 mt-0.5 max-w-[200px] truncate" title={lic.notes}>
                          {lic.notes}
                        </div>
                      )}
                    </td>

                    {/* License Key */}
                    <td className="py-3.5 px-5">
                      <div className="flex items-center gap-1.5">
                        <span className="font-mono text-xs bg-slate-100 dark:bg-black/30 text-indigo-700 dark:text-indigo-300 px-2 py-1 rounded-lg border border-slate-200 dark:border-indigo-500/20 select-all font-semibold">
                          {lic.license_key}
                        </span>
                        <button
                          onClick={() => handleCopy(lic.license_key)}
                          className="p-1 rounded-md text-slate-400 hover:text-slate-700 dark:hover:text-white transition-all"
                          title="نسخ المفتاح"
                        >
                          {copiedKey === lic.license_key ? (
                            <Check className="w-3.5 h-3.5 text-emerald-500" />
                          ) : (
                            <Copy className="w-3.5 h-3.5" />
                          )}
                        </button>
                      </div>
                    </td>

                    {/* Expiry & Plan */}
                    <td className="py-3.5 px-5">
                      <div className="font-semibold text-slate-800 dark:text-gray-200">
                        {lic.plan === 'trial' ? 'تجريبي (14 يوم)' :
                         lic.plan === 'monthly' ? 'اشتراك شهري' :
                         lic.plan === 'yearly' ? 'اشتراك سنوي' : 'مدى الحياة'}
                      </div>
                      <div className="mt-1">
                        {isLifetime ? (
                          <span className="inline-flex items-center gap-1 text-[10px] font-semibold text-purple-700 dark:text-purple-300 bg-purple-50 dark:bg-purple-500/10 px-2 py-0.5 rounded-full border border-purple-200 dark:border-purple-500/20">
                            <Sparkles className="w-2.5 h-2.5" /> دائم (Lifetime)
                          </span>
                        ) : isExpired ? (
                          <span className="inline-flex items-center gap-1 text-[10px] font-semibold text-rose-700 dark:text-rose-400 bg-rose-50 dark:bg-rose-500/10 px-2 py-0.5 rounded-full border border-rose-200 dark:border-rose-500/20">
                            <Clock className="w-2.5 h-2.5" /> منتهي الصلاحية
                          </span>
                        ) : (
                          <span className="inline-flex items-center gap-1 text-[10px] font-medium text-emerald-700 dark:text-emerald-400 bg-emerald-50 dark:bg-emerald-500/10 px-2 py-0.5 rounded-full border border-emerald-200 dark:border-emerald-500/20">
                            متبقي {days} يوم
                          </span>
                        )}
                      </div>
                    </td>

                    {/* Modular Feature Pills */}
                    <td className="py-3.5 px-5 max-w-xs">
                      <div className="flex flex-wrap gap-1 items-center">
                        {featuresList.slice(0, 3).map(fId => {
                          const mod = ERP_MODULES.find(m => m.id === fId);
                          const isAddon = mod?.category === 'addon';
                          return (
                            <span 
                              key={fId}
                              className={`text-[10px] px-2 py-0.5 rounded-md border font-medium ${
                                isAddon
                                  ? 'bg-purple-50 text-purple-700 border-purple-200 dark:bg-purple-500/10 dark:text-purple-300 dark:border-purple-500/20'
                                  : 'bg-indigo-50 text-indigo-700 border-indigo-200 dark:bg-indigo-500/10 dark:text-indigo-300 dark:border-indigo-500/20'
                              }`}
                            >
                              {mod?.name.split(' ')[0] || fId}
                            </span>
                          );
                        })}
                        {featuresList.length > 3 && (
                          <span className="text-[10px] text-slate-500 dark:text-gray-400 bg-slate-100 dark:bg-white/5 px-1.5 py-0.5 rounded-md font-mono">
                            +{featuresList.length - 3}
                          </span>
                        )}
                        <button
                          onClick={() => onEdit(lic)}
                          className="text-[10px] text-indigo-600 dark:text-indigo-400 hover:underline mr-1 font-semibold"
                        >
                          تعديل
                        </button>
                      </div>
                    </td>

                    {/* Devices */}
                    <td className="py-3.5 px-5">
                      <button
                        onClick={() => onManageDevices(lic)}
                        className="flex items-center gap-1.5 text-xs text-slate-700 dark:text-gray-300 hover:text-indigo-600 dark:hover:text-white bg-slate-50 dark:bg-white/[0.04] px-2.5 py-1 rounded-lg border border-slate-200 dark:border-white/10 transition-colors"
                        title="عرض وإدارة أجهزة العميل"
                      >
                        <Laptop className="w-3.5 h-3.5 text-indigo-600 dark:text-indigo-400" />
                        <span className="font-mono font-semibold">{lic.bound_devices_count || 0} / {lic.max_devices || 1}</span>
                      </button>
                    </td>

                    {/* Status Pill Toggle */}
                    <td className="py-3.5 px-5">
                      <button
                        onClick={() => onToggleStatus(lic)}
                        className={`inline-flex items-center gap-1.5 text-xs font-semibold px-2.5 py-0.5 rounded-full border transition-all ${
                          isSuspended
                            ? 'bg-rose-50 text-rose-700 border-rose-200 dark:bg-rose-500/10 dark:text-rose-400 dark:border-rose-500/20'
                            : isExpired
                            ? 'bg-amber-50 text-amber-700 border-amber-200 dark:bg-amber-500/10 dark:text-amber-400 dark:border-amber-500/20'
                            : 'bg-emerald-50 text-emerald-700 border-emerald-200 dark:bg-emerald-500/10 dark:text-emerald-400 dark:border-emerald-500/20'
                        }`}
                        title="انقر للتبديل (نشط / تجميد)"
                      >
                        <span className={`w-1.5 h-1.5 rounded-full ${isSuspended ? 'bg-rose-500' : isExpired ? 'bg-amber-500' : 'bg-emerald-500'}`} />
                        <span>{isSuspended ? 'معلق / موقوف' : isExpired ? 'منتهي' : 'نشط'}</span>
                      </button>
                    </td>

                    {/* Quick Actions */}
                    <td className="py-3.5 px-5 text-center">
                      <div className="flex items-center justify-center gap-1">
                        <button
                          onClick={() => onEdit(lic)}
                          className="p-1.5 rounded-lg text-slate-400 hover:text-slate-700 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-white/5 transition-colors"
                          title="تعديل الترخيص والموديولات"
                        >
                          <Edit2 className="w-3.5 h-3.5" />
                        </button>
                        <button
                          onClick={() => onDelete(lic)}
                          className="p-1.5 rounded-lg text-slate-400 hover:text-rose-600 hover:bg-rose-50 dark:hover:bg-rose-500/10 transition-colors"
                          title="حذف الترخيص"
                        >
                          <Trash2 className="w-3.5 h-3.5" />
                        </button>
                      </div>
                    </td>

                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>

    </div>
  );
}
