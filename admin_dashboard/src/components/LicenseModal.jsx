import React, { useState, useEffect } from 'react';
import { 
  X, KeyRound, Sparkles, Calendar, Laptop, 
  Layers, CheckSquare, Square, Shield, Check, Info 
} from 'lucide-react';
import { ERP_MODULES, LICENSE_PLANS } from '../config/modules';
import { api } from '../services/api';

export default function LicenseModal({ isOpen, onClose, onSave, editingLicense }) {
  const [formData, setFormData] = useState({
    client_name: '',
    client_phone: '',
    license_key: '',
    plan: 'yearly',
    expires_at: '',
    max_devices: 1,
    status: 'active',
    features: [],
    notes: '',
  });

  const [errors, setErrors] = useState({});

  useEffect(() => {
    if (editingLicense) {
      setFormData({
        ...editingLicense,
        expires_at: editingLicense.expires_at ? editingLicense.expires_at.split('T')[0] : '',
        features: editingLicense.features || [],
      });
    } else {
      // Default new license
      const defaultFeatures = ERP_MODULES.filter(m => m.defaultEnabled).map(m => m.id);
      const defaultExpiry = new Date();
      defaultExpiry.setDate(defaultExpiry.getDate() + 365);

      setFormData({
        client_name: '',
        client_phone: '',
        license_key: api.generateRandomKey('POS'),
        plan: 'yearly',
        expires_at: defaultExpiry.toISOString().split('T')[0],
        max_devices: 1,
        status: 'active',
        features: defaultFeatures,
        notes: '',
      });
    }
    setErrors({});
  }, [editingLicense, isOpen]);

  if (!isOpen) return null;

  const handlePlanChange = (planId) => {
    const selectedPlan = LICENSE_PLANS.find(p => p.id === planId);
    if (!selectedPlan) return;

    const newExpiry = new Date();
    newExpiry.setDate(newExpiry.getDate() + selectedPlan.days);

    let newFeatures = [...formData.features];
    if (selectedPlan.defaultModules === 'all') {
      newFeatures = ERP_MODULES.map(m => m.id);
    } else if (selectedPlan.defaultModules === 'core') {
      newFeatures = ERP_MODULES.filter(m => m.category === 'core').map(m => m.id);
    }

    setFormData(prev => ({
      ...prev,
      plan: planId,
      expires_at: newExpiry.toISOString().split('T')[0],
      features: newFeatures,
    }));
  };

  const toggleFeature = (featureId) => {
    setFormData(prev => {
      const exists = prev.features.includes(featureId);
      const updated = exists
        ? prev.features.filter(id => id !== featureId)
        : [...prev.features, featureId];
      return { ...prev, features: updated };
    });
  };

  const handleSelectAllModules = () => {
    setFormData(prev => ({ ...prev, features: ERP_MODULES.map(m => m.id) }));
  };

  const handleSelectCoreModules = () => {
    setFormData(prev => ({ ...prev, features: ERP_MODULES.filter(m => m.category === 'core').map(m => m.id) }));
  };

  const handleClearModules = () => {
    setFormData(prev => ({ ...prev, features: [] }));
  };

  const handleGenerateKey = () => {
    setFormData(prev => ({
      ...prev,
      license_key: api.generateRandomKey('POS')
    }));
  };

  const handleSubmit = (e) => {
    e.preventDefault();
    const newErrors = {};

    if (!formData.client_name.trim()) newErrors.client_name = 'اسم العميل مطلوب';
    if (!formData.license_key.trim()) newErrors.license_key = 'مفتاح الترخيص مطلوب';
    if (!formData.expires_at) newErrors.expires_at = 'تاريخ الانتهاء مطلوب';

    if (Object.keys(newErrors).length > 0) {
      setErrors(newErrors);
      return;
    }

    onSave({
      ...formData,
      expires_at: new Date(formData.expires_at).toISOString(),
    });
  };

  const coreModules = ERP_MODULES.filter(m => m.category === 'core');
  const addonModules = ERP_MODULES.filter(m => m.category === 'addon');

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md overflow-y-auto">
      <div className="relative w-full max-w-4xl rounded-3xl bg-[#111827] border border-white/10 shadow-2xl overflow-hidden my-8">
        
        {/* Modal Header */}
        <div className="flex items-center justify-between px-6 py-5 border-b border-white/5 bg-white/[0.02]">
          <div className="flex items-center gap-3">
            <div className="p-2.5 rounded-xl bg-indigo-600/20 text-indigo-400 border border-indigo-500/20">
              <KeyRound className="w-5 h-5" />
            </div>
            <div>
              <h2 className="text-lg font-bold text-white">
                {editingLicense ? 'تعديل بيانات وترخيص العميل' : 'إصدار ترخيص جديد لنظام POS'}
              </h2>
              <p className="text-xs text-gray-400">
                حدد مدة الترخيص، الوحدات المسموح بها، والأجهزة المصرحة
              </p>
            </div>
          </div>

          <button
            onClick={onClose}
            className="p-2 rounded-xl text-gray-400 hover:text-white hover:bg-white/5 transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Form Body */}
        <form onSubmit={handleSubmit} className="p-6 space-y-6">
          
          {/* Section 1: Client & Key */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-semibold text-gray-300 mb-1.5">
                اسم العميل أو اسم المحل / الشركة *
              </label>
              <input
                type="text"
                placeholder="مثال: سوبر ماركت الأهرام"
                value={formData.client_name}
                onChange={(e) => setFormData({ ...formData, client_name: e.target.value })}
                className="w-full px-4 py-2.5 rounded-xl bg-surface-panel/80 border border-white/10 text-sm text-white focus:outline-none focus:border-indigo-500"
              />
              {errors.client_name && (
                <span className="text-[11px] text-rose-400 mt-1 block">{errors.client_name}</span>
              )}
            </div>

            <div>
              <label className="block text-xs font-semibold text-gray-300 mb-1.5">
                رقم هاتف العميل (للتواصل والتجديد)
              </label>
              <input
                type="text"
                placeholder="مثال: 01012345678"
                value={formData.client_phone}
                onChange={(e) => setFormData({ ...formData, client_phone: e.target.value })}
                className="w-full px-4 py-2.5 rounded-xl bg-surface-panel/80 border border-white/10 text-sm text-white focus:outline-none focus:border-indigo-500"
              />
            </div>

            <div className="md:col-span-2">
              <label className="block text-xs font-semibold text-gray-300 mb-1.5">
                مفتاح الترخيص (License Key) *
              </label>
              <div className="flex gap-2">
                <input
                  type="text"
                  placeholder="POS-XXXX-XXXX-XXXX"
                  value={formData.license_key}
                  onChange={(e) => setFormData({ ...formData, license_key: e.target.value })}
                  className="flex-1 font-mono tracking-wider px-4 py-2.5 rounded-xl bg-surface-panel/80 border border-white/10 text-sm text-indigo-300 focus:outline-none focus:border-indigo-500"
                />
                <button
                  type="button"
                  onClick={handleGenerateKey}
                  className="flex items-center gap-1.5 px-4 py-2.5 rounded-xl bg-white/5 hover:bg-white/10 border border-white/10 text-xs font-medium text-gray-200 transition-colors"
                >
                  <Sparkles className="w-3.5 h-3.5 text-indigo-400" />
                  <span>توليد كود تلقائي</span>
                </button>
              </div>
              {errors.license_key && (
                <span className="text-[11px] text-rose-400 mt-1 block">{errors.license_key}</span>
              )}
            </div>
          </div>

          {/* Section 2: Plan & Expiration */}
          <div className="rounded-2xl p-4 bg-surface-panel/40 border border-white/5 space-y-4">
            <div className="flex items-center justify-between">
              <span className="text-xs font-bold uppercase tracking-wider text-indigo-400">
                الباقة وصلاحية الترخيص
              </span>
            </div>

            {/* Plan Selector Buttons */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2.5">
              {LICENSE_PLANS.map(p => (
                <button
                  key={p.id}
                  type="button"
                  onClick={() => handlePlanChange(p.id)}
                  className={`p-3 rounded-xl border text-right transition-all ${
                    formData.plan === p.id
                      ? 'bg-indigo-600/20 border-indigo-500 text-white shadow-lg shadow-indigo-600/10'
                      : 'bg-white/[0.02] border-white/5 text-gray-400 hover:text-white hover:bg-white/5'
                  }`}
                >
                  <div className="text-xs font-bold mb-1">{p.name}</div>
                  <div className="text-[10px] text-gray-400">{p.days} يوم</div>
                </button>
              ))}
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 pt-2">
              <div>
                <label className="block text-xs text-gray-400 mb-1">تاريخ انتهاء الصلاحية</label>
                <input
                  type="date"
                  value={formData.expires_at}
                  onChange={(e) => setFormData({ ...formData, expires_at: e.target.value })}
                  className="w-full px-3.5 py-2 rounded-xl bg-surface-panel border border-white/10 text-xs text-white focus:outline-none focus:border-indigo-500"
                />
              </div>

              <div>
                <label className="block text-xs text-gray-400 mb-1">الحد الأقصى للأجهزة المصرحة</label>
                <input
                  type="number"
                  min="1"
                  max="50"
                  value={formData.max_devices}
                  onChange={(e) => setFormData({ ...formData, max_devices: parseInt(e.target.value) || 1 })}
                  className="w-full px-3.5 py-2 rounded-xl bg-surface-panel border border-white/10 text-xs text-white focus:outline-none focus:border-indigo-500"
                />
              </div>

              <div>
                <label className="block text-xs text-gray-400 mb-1">حالة الترخيص</label>
                <select
                  value={formData.status}
                  onChange={(e) => setFormData({ ...formData, status: e.target.value })}
                  className="w-full px-3.5 py-2 rounded-xl bg-surface-panel border border-white/10 text-xs text-white focus:outline-none focus:border-indigo-500"
                >
                  <option value="active">نشط (يعمل طبيعي)</option>
                  <option value="suspended">معلق / موقوف مؤقتاً</option>
                </select>
              </div>
            </div>
          </div>

          {/* Section 3: Modular Feature Gating (الوحدات والميزات) */}
          <div className="rounded-2xl p-4 bg-surface-panel/40 border border-white/5 space-y-4">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 border-b border-white/5 pb-3">
              <div>
                <h3 className="text-sm font-bold text-white flex items-center gap-2">
                  <Layers className="w-4 h-4 text-indigo-400" />
                  <span>الوحدات والميزات المسموح بها (Feature Gating)</span>
                </h3>
                <p className="text-[11px] text-gray-400">
                  الوحدات التي لا يتم تحديدها ستختفي تماماً من قائمة البرنامج عند هذا العميل
                </p>
              </div>

              {/* Quick Presets */}
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={handleSelectAllModules}
                  className="px-2.5 py-1 rounded-lg bg-indigo-500/10 hover:bg-indigo-500/20 text-indigo-300 text-[11px] border border-indigo-500/20 transition-colors"
                >
                  تفعيل الكل
                </button>
                <button
                  type="button"
                  onClick={handleSelectCoreModules}
                  className="px-2.5 py-1 rounded-lg bg-white/5 hover:bg-white/10 text-gray-300 text-[11px] border border-white/10 transition-colors"
                >
                  الأساسي فقط
                </button>
                <button
                  type="button"
                  onClick={handleClearModules}
                  className="px-2.5 py-1 rounded-lg bg-white/5 hover:bg-white/10 text-gray-400 text-[11px] border border-white/10 transition-colors"
                >
                  إلغاء التحديد
                </button>
              </div>
            </div>

            {/* Core Modules Grid */}
            <div>
              <div className="text-[11px] font-bold text-gray-400 mb-2 uppercase tracking-wider">
                الوحدات الأساسية للـ POS:
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-2.5">
                {coreModules.map(mod => {
                  const isChecked = formData.features.includes(mod.id);
                  return (
                    <div
                      key={mod.id}
                      onClick={() => toggleFeature(mod.id)}
                      className={`cursor-pointer p-3 rounded-xl border transition-all flex items-start gap-2.5 select-none ${
                        isChecked 
                          ? 'bg-indigo-600/10 border-indigo-500/40 text-white' 
                          : 'bg-white/[0.01] border-white/5 text-gray-400 hover:border-white/10 hover:bg-white/[0.02]'
                      }`}
                    >
                      <div className={`mt-0.5 rounded-md p-0.5 ${isChecked ? 'bg-indigo-600 text-white' : 'border border-gray-600 text-transparent'}`}>
                        <Check className="w-3 h-3" />
                      </div>
                      <div className="flex-1">
                        <div className="text-xs font-semibold">{mod.name}</div>
                        <div className="text-[10px] text-gray-400 mt-0.5 leading-snug">{mod.description}</div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>

            {/* Addon Modules Grid */}
            <div className="pt-2">
              <div className="text-[11px] font-bold text-purple-400 mb-2 uppercase tracking-wider">
                الوحدات الإضافية والمتقدمة (Addons):
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-2.5">
                {addonModules.map(mod => {
                  const isChecked = formData.features.includes(mod.id);
                  return (
                    <div
                      key={mod.id}
                      onClick={() => toggleFeature(mod.id)}
                      className={`cursor-pointer p-3 rounded-xl border transition-all flex items-start gap-2.5 select-none ${
                        isChecked 
                          ? 'bg-purple-600/15 border-purple-500/50 text-white' 
                          : 'bg-white/[0.01] border-white/5 text-gray-400 hover:border-white/10 hover:bg-white/[0.02]'
                      }`}
                    >
                      <div className={`mt-0.5 rounded-md p-0.5 ${isChecked ? 'bg-purple-600 text-white' : 'border border-gray-600 text-transparent'}`}>
                        <Check className="w-3 h-3" />
                      </div>
                      <div className="flex-1">
                        <div className="text-xs font-semibold text-purple-200">{mod.name}</div>
                        <div className="text-[10px] text-gray-400 mt-0.5 leading-snug">{mod.description}</div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>

          </div>

          {/* Internal Notes */}
          <div>
            <label className="block text-xs font-semibold text-gray-300 mb-1.5">
              ملاحظات داخلية خاصة بالعميل
            </label>
            <textarea
              rows="2"
              placeholder="مثال: دفع كاش بالكامل، مطلوب تفعيل التصنيع بعد أسبوعين..."
              value={formData.notes}
              onChange={(e) => setFormData({ ...formData, notes: e.target.value })}
              className="w-full px-4 py-2 rounded-xl bg-surface-panel/80 border border-white/10 text-xs text-white focus:outline-none focus:border-indigo-500"
            />
          </div>

          {/* Modal Footer Actions */}
          <div className="flex items-center justify-end gap-3 pt-4 border-t border-white/5">
            <button
              type="button"
              onClick={onClose}
              className="px-5 py-2.5 rounded-xl bg-white/5 hover:bg-white/10 text-xs font-semibold text-gray-300 transition-colors"
            >
              إلغاء
            </button>
            <button
              type="submit"
              className="px-6 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-xs font-bold text-white shadow-lg shadow-indigo-600/30 transition-all active:scale-[0.98]"
            >
              {editingLicense ? 'حفظ التعديلات' : 'إصدار الترخيص الآن'}
            </button>
          </div>

        </form>

      </div>
    </div>
  );
}
