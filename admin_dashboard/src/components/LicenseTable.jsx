import React, { useState } from 'react';
import { 
  Search, Copy, Check, SlidersHorizontal, Laptop, 
  Calendar, Layers, MoreVertical, Edit2, Trash2, 
  PowerOff, CheckCircle2, AlertCircle, Clock 
} from 'lucide-react';
import { ERP_MODULES } from '../config/modules';

export default function LicenseTable({ 
  licenses, 
  onEdit, 
  onManageDevices, 
  onToggleStatus, 
  onDelete, 
  onCopyKey 
}) {
  const [search, setSearch] = useState('');
  const [filter, setFilter] = useState('all');
  const [copiedKey, setCopiedKey] = useState(null);

  const handleCopy = (key) => {
    navigator.clipboard.writeText(key);
    setCopiedKey(key);
    onCopyKey(key);
    setTimeout(() => setCopiedKey(null), 2000);
  };

  const getDaysRemaining = (expiryDate) => {
    const diff = new Date(expiryDate) - new Date();
    const days = Math.ceil(diff / (1000 * 60 * 60 * 24));
    return days;
  };

  const filteredLicenses = licenses.filter(lic => {
    const matchesSearch = 
      lic.client_name?.toLowerCase().includes(search.toLowerCase()) ||
      lic.license_key?.toLowerCase().includes(search.toLowerCase()) ||
      lic.client_phone?.includes(search);

    const isExpired = new Date(lic.expires_at) <= new Date();

    if (filter === 'active') return matchesSearch && lic.status === 'active' && !isExpired;
    if (filter === 'suspended') return matchesSearch && lic.status === 'suspended';
    if (filter === 'expired') return matchesSearch && isExpired;
    return matchesSearch;
  });

  return (
    <div className="rounded-3xl border border-white/5 bg-[#111827]/70 backdrop-blur-xl overflow-hidden shadow-2xl">
      
      {/* Table Toolbar */}
      <div className="p-5 border-b border-white/5 flex flex-col md:flex-row md:items-center justify-between gap-4">
        
        {/* Search Input */}
        <div className="relative flex-1 max-w-md">
          <Search className="w-4 h-4 text-gray-400 absolute right-3.5 top-1/2 -translate-y-1/2" />
          <input
            type="text"
            placeholder="بحث باسم العميل، رقم الهاتف، أو كود المفتاح..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pr-10 pl-4 py-2.5 rounded-xl bg-surface-panel/80 border border-white/5 text-sm text-white placeholder-gray-500 focus:outline-none focus:border-indigo-500 transition-colors"
          />
        </div>

        {/* Filter Pills */}
        <div className="flex items-center gap-1.5 p-1 rounded-xl bg-surface-panel/60 border border-white/5 text-xs">
          {[
            { id: 'all', label: 'الكل' },
            { id: 'active', label: 'نشط' },
            { id: 'suspended', label: 'معلق' },
            { id: 'expired', label: 'منتهي' },
          ].map((item) => (
            <button
              key={item.id}
              onClick={() => setFilter(item.id)}
              className={`px-3 py-1.5 rounded-lg font-medium transition-all ${
                filter === item.id
                  ? 'bg-indigo-600 text-white shadow-sm'
                  : 'text-gray-400 hover:text-gray-200'
              }`}
            >
              {item.label}
            </button>
          ))}
        </div>

      </div>

      {/* Table Content */}
      <div className="overflow-x-auto">
        <table className="w-full text-right text-sm">
          <thead>
            <tr className="border-b border-white/5 bg-white/[0.02] text-xs font-semibold text-gray-400 uppercase tracking-wider">
              <th className="py-4 px-6">العميل / المحل</th>
              <th className="py-4 px-6">مفتاح الترخيص</th>
              <th className="py-4 px-6">الصلاحية والباقة</th>
              <th className="py-4 px-6">الوحدات المفعلة (Modules)</th>
              <th className="py-4 px-6">الأجهزة</th>
              <th className="py-4 px-6">الحالة</th>
              <th className="py-4 px-6 text-center">إجراءات</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-white/5">
            {filteredLicenses.length === 0 ? (
              <tr>
                <td colSpan="7" className="py-12 text-center text-gray-500">
                  لا توجد تراخيص مطابقة لخيارات البحث
                </td>
              </tr>
            ) : (
              filteredLicenses.map((lic) => {
                const days = getDaysRemaining(lic.expires_at);
                const isExpired = days <= 0;
                const isSuspended = lic.status === 'suspended';
                const featuresList = lic.features || [];

                return (
                  <tr key={lic.id} className="hover:bg-white/[0.02] transition-colors group">
                    
                    {/* Client Info */}
                    <td className="py-4 px-6">
                      <div className="font-semibold text-white">
                        {lic.client_name || 'بدون اسم'}
                      </div>
                      <div className="text-xs text-gray-400 mt-0.5">
                        {lic.client_phone || 'لا يوجد هاتف'}
                      </div>
                      {lic.notes && (
                        <div className="text-[11px] text-gray-500 mt-1 max-w-[200px] truncate" title={lic.notes}>
                          {lic.notes}
                        </div>
                      )}
                    </td>

                    {/* License Key */}
                    <td className="py-4 px-6">
                      <div className="flex items-center gap-2">
                        <span className="font-mono text-xs bg-black/40 text-indigo-300 px-2.5 py-1 rounded-lg border border-indigo-500/20 select-all">
                          {lic.license_key}
                        </span>
                        <button
                          onClick={() => handleCopy(lic.license_key)}
                          className="p-1 rounded-md text-gray-400 hover:text-white hover:bg-white/5 transition-all"
                          title="نسخ المفتاح"
                        >
                          {copiedKey === lic.license_key ? (
                            <Check className="w-3.5 h-3.5 text-emerald-400" />
                          ) : (
                            <Copy className="w-3.5 h-3.5" />
                          )}
                        </button>
                      </div>
                    </td>

                    {/* Expiry and Plan */}
                    <td className="py-4 px-6">
                      <div className="text-xs font-medium text-gray-200">
                        {lic.plan === 'trial' ? 'نسخة تجريبية' :
                         lic.plan === 'monthly' ? 'اشتراك شهري' :
                         lic.plan === 'yearly' ? 'اشتراك سنوي' : 'مدى الحياة'}
                      </div>
                      <div className="flex items-center gap-1.5 mt-1">
                        {isExpired ? (
                          <span className="inline-flex items-center gap-1 text-[11px] font-semibold text-rose-400 bg-rose-500/10 px-2 py-0.5 rounded-full border border-rose-500/20">
                            <Clock className="w-3 h-3" /> منتهي الصلاحية
                          </span>
                        ) : (
                          <span className="inline-flex items-center gap-1 text-[11px] font-medium text-emerald-400 bg-emerald-500/10 px-2 py-0.5 rounded-full border border-emerald-500/20">
                            متبقي {days} يوم
                          </span>
                        )}
                      </div>
                    </td>

                    {/* Enabled Modules */}
                    <td className="py-4 px-6 max-w-xs">
                      <div className="flex flex-wrap gap-1 items-center">
                        {featuresList.slice(0, 3).map(fId => {
                          const mod = ERP_MODULES.find(m => m.id === fId);
                          return (
                            <span 
                              key={fId}
                              className={`text-[10px] px-2 py-0.5 rounded-md border font-medium ${
                                mod?.category === 'addon'
                                  ? 'bg-purple-500/10 text-purple-300 border-purple-500/20'
                                  : 'bg-indigo-500/10 text-indigo-300 border-indigo-500/20'
                              }`}
                            >
                              {mod?.name.split(' ')[0] || fId}
                            </span>
                          );
                        })}
                        {featuresList.length > 3 && (
                          <span className="text-[10px] text-gray-400 bg-white/5 px-1.5 py-0.5 rounded-md">
                            +{featuresList.length - 3} إضافية
                          </span>
                        )}
                        <button
                          onClick={() => onEdit(lic)}
                          className="text-[11px] text-indigo-400 hover:text-indigo-300 underline mr-1"
                        >
                          تعديل
                        </button>
                      </div>
                    </td>

                    {/* Devices */}
                    <td className="py-4 px-6">
                      <button
                        onClick={() => onManageDevices(lic)}
                        className="flex items-center gap-1.5 text-xs text-gray-300 hover:text-white bg-surface-panel/80 hover:bg-surface-hover px-2.5 py-1.5 rounded-xl border border-white/5 transition-colors"
                        title="عرض وإدارة الأجهزة المتصلة"
                      >
                        <Laptop className="w-3.5 h-3.5 text-indigo-400" />
                        <span>{lic.bound_devices_count || 0} / {lic.max_devices || 1}</span>
                      </button>
                    </td>

                    {/* Status */}
                    <td className="py-4 px-6">
                      <button
                        onClick={() => onToggleStatus(lic)}
                        className={`inline-flex items-center gap-1.5 text-xs font-semibold px-2.5 py-1 rounded-full border transition-all ${
                          isSuspended
                            ? 'bg-rose-500/10 text-rose-400 border-rose-500/20 hover:bg-rose-500/20'
                            : isExpired
                            ? 'bg-amber-500/10 text-amber-400 border-amber-500/20'
                            : 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20 hover:bg-emerald-500/20'
                        }`}
                        title="انقر لتغيير الحالة (تجميد / تنشيط)"
                      >
                        <span className={`w-1.5 h-1.5 rounded-full ${isSuspended ? 'bg-rose-400' : isExpired ? 'bg-amber-400' : 'bg-emerald-400'}`} />
                        <span>{isSuspended ? 'معلق / موقوف' : isExpired ? 'منتهي' : 'نشط'}</span>
                      </button>
                    </td>

                    {/* Actions */}
                    <td className="py-4 px-6 text-center">
                      <div className="flex items-center justify-center gap-1">
                        <button
                          onClick={() => onEdit(lic)}
                          className="p-1.5 rounded-lg text-gray-400 hover:text-white hover:bg-white/5 transition-colors"
                          title="تعديل البيانات والوحدات"
                        >
                          <Edit2 className="w-4 h-4" />
                        </button>
                        <button
                          onClick={() => onDelete(lic)}
                          className="p-1.5 rounded-lg text-gray-400 hover:text-rose-400 hover:bg-rose-500/10 transition-colors"
                          title="حذف الترخيص"
                        >
                          <Trash2 className="w-4 h-4" />
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
