import React, { useState, useEffect } from 'react';
import { X, KeyRound, Sparkles, Check, Layers } from 'lucide-react';
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
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40 backdrop-blur-xs overflow-y-auto">
      <div className="relative w-full max-w-4xl rounded-2xl bg-white border border-slate-200 shadow-xl overflow-hidden my-6">
        
        {/* Modal Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-slate-100 bg-slate-50/50">
          <div className="flex items-center gap-3">
            <div className="p-2.5 rounded-xl bg-blue-50 text-blue-600 border border-blue-200/60">
              <KeyRound className="w-5 h-5" />
            </div>
            <div>
              <h2 className="text-base font-bold text-slate-900">
                {editingLicense ? 'تعديل ترخيص وموديولات العميل' : 'إصدار ترخيص جديد لنظام مدار ERP'}
              </h2>
              <p className="text-xs text-slate-500 font-medium">
                تحديد الصلاحيات والموديولات والأجهزة المصرحة للعميل
              </p>
            </div>
          </div>

          <button
            onClick={onClose}
            className="p-1.5 rounded-lg text-slate-400 hover:text-slate-600 hover:bg-slate-100 transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Modal Form */}
        <form onSubmit={handleSubmit} className="p-6 space-y-5">
          
          {/* Client Info */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <div>
              <label className="block text-xs font-bold text-slate-700 mb-1">
                اسم العميل أو اسم المحل / الشركة *
              </label>
              <input
                type="text"
                placeholder="مثال: سوبرماركت البركة"
                value={formData.client_name}
                onChange={(e) => setFormData({ ...formData, client_name: e.target.value })}
                className="w-full px-3.5 py-2.5 rounded-xl bg-slate-50 border border-slate-200 text-xs text-slate-900 focus:outline-none focus:border-blue-500 focus:bg-white"
              />
              {errors.client_name && (
                <span className="text-[11px] text-rose-600 font-semibold mt-1 block">{errors.client_name}</span>
              )}
            </div>

            <div>
              <label className="block text-xs font-bold text-slate-700 mb-1">
                رقم هاتف العميل
              </label>
              <input
                type="text"
                placeholder="مثال: 01012345678"
                value={formData.client_phone}
                onChange={(e) => setFormData({ ...formData, client_phone: e.target.value })}
                className="w-full px-3.5 py-2.5 rounded-xl bg-slate-50 border border-slate-200 text-xs text-slate-900 focus:outline-none focus:border-blue-500 focus:bg-white font-mono"
              />
            </div>

            <div className="md:col-span-2">
              <label className="block text-xs font-bold text-slate-700 mb-1">
                مفتاح الترخيص (License Key) *
              </label>
              <div className="flex gap-2">
                <input
                  type="text"
                  value={formData.license_key}
                  onChange={(e) => setFormData({ ...formData, license_key: e.target.value })}
                  className="flex-1 font-mono font-bold tracking-wider px-3.5 py-2.5 rounded-xl bg-slate-50 border border-slate-200 text-xs text-blue-700 focus:outline-none focus:border-blue-500 focus:bg-white"
                />
                <button
                  type="button"
                  onClick={handleGenerateKey}
                  className="flex items-center gap-1.5 px-4 py-2 rounded-xl bg-slate-100 hover:bg-slate-200 border border-slate-200 text-xs font-bold text-slate-700 transition-colors"
                >
                  <Sparkles className="w-3.5 h-3.5 text-blue-600" />
                  <span>توليد كود عشوائي</span>
                </button>
              </div>
              {errors.license_key && (
                <span className="text-[11px] text-rose-600 font-semibold mt-1 block">{errors.license_key}</span>
              )}
            </div>
          </div>

          {/* Plan & Expiry */}
          <div className="rounded-2xl p-4 bg-slate-50/70 border border-slate-200 space-y-3">
            <span className="text-xs font-bold text-slate-800">
              باقة الترخيص وفترة الصلاحية
            </span>

            {/* Plan Selector Buttons */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-2.5">
              {LICENSE_PLANS.map(p => (
                <button
                  key={p.id}
                  type="button"
                  onClick={() => handlePlanChange(p.id)}
                  className={`p-3 rounded-xl border text-right transition-all ${
                    formData.plan === p.id
                      ? 'bg-blue-50 border-blue-600 text-blue-900 shadow-xs'
                      : 'bg-white border-slate-200 text-slate-600 hover:border-slate-300'
                  }`}
                >
                  <div className="text-xs font-bold">{p.name}</div>
                  <div className="text-[11px] text-slate-500 mt-0.5">{p.days} يوم</div>
                </button>
              ))}
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 pt-1">
              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1">تاريخ الانتهاء</label>
                <input
                  type="date"
                  value={formData.expires_at}
                  onChange={(e) => setFormData({ ...formData, expires_at: e.target.value })}
                  className="w-full px-3 py-2 rounded-xl bg-white border border-slate-200 text-xs text-slate-900 focus:outline-none focus:border-blue-500"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1">الحد الأقصى للأجهزة المصرحة</label>
                <input
                  type="number"
                  min="1"
                  max="50"
                  value={formData.max_devices}
                  onChange={(e) => setFormData({ ...formData, max_devices: parseInt(e.target.value) || 1 })}
                  className="w-full px-3 py-2 rounded-xl bg-white border border-slate-200 text-xs text-slate-900 focus:outline-none focus:border-blue-500"
                />
              </div>

              <div>
                <label className="block text-xs font-semibold text-slate-600 mb-1">حالة الترخيص</label>
                <select
                  value={formData.status}
                  onChange={(e) => setFormData({ ...formData, status: e.target.value })}
                  className="w-full px-3 py-2 rounded-xl bg-white border border-slate-200 text-xs text-slate-900 focus:outline-none focus:border-blue-500"
                >
                  <option value="active">نشط (يعمل طبيعي)</option>
                  <option value="suspended">معلق / موقوف مؤقتاً</option>
                </select>
              </div>
            </div>
          </div>

          {/* Modular Feature Gating */}
          <div className="rounded-2xl p-4 bg-slate-50/70 border border-slate-200 space-y-3">
            <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 border-b border-slate-200/80 pb-3">
              <div>
                <h3 className="text-xs font-bold text-slate-900 flex items-center gap-1.5">
                  <Layers className="w-4 h-4 text-blue-600" />
                  <span>الموديولات والميزات المسموح بها للعميل (Modular Feature Gating)</span>
                </h3>
                <p className="text-[11px] text-slate-500">
                  الموديول الذي لا تختاره سيختفي تماماً وبأمان من قائمة برنامج العميل دون أي خطأ
                </p>
              </div>

              {/* Quick Presets */}
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={handleSelectAllModules}
                  className="px-2.5 py-1 rounded-lg bg-blue-50 hover:bg-blue-100 text-blue-700 text-xs font-bold border border-blue-200 transition-colors"
                >
                  تفعيل الكل
                </button>
                <button
                  type="button"
                  onClick={handleSelectCoreModules}
                  className="px-2.5 py-1 rounded-lg bg-white hover:bg-slate-100 text-slate-700 text-xs font-semibold border border-slate-200 transition-colors"
                >
                  الأساسي فقط
                </button>
                <button
                  type="button"
                  onClick={handleClearModules}
                  className="px-2.5 py-1 rounded-lg bg-white hover:bg-slate-100 text-slate-500 text-xs font-semibold border border-slate-200 transition-colors"
                >
                  إلغاء التحديد
                </button>
              </div>
            </div>

            {/* Core Modules Grid */}
            <div>
              <div className="text-[11px] font-bold text-blue-700 mb-2 uppercase">
                الوحدات الأساسية:
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
                          ? 'bg-blue-50/70 border-blue-300 text-slate-900' 
                          : 'bg-white border-slate-200 text-slate-600 hover:border-slate-300'
                      }`}
                    >
                      <div className={`mt-0.5 rounded p-0.5 ${isChecked ? 'bg-blue-600 text-white' : 'border border-slate-300 text-transparent'}`}>
                        <Check className="w-3 h-3" />
                      </div>
                      <div className="flex-1">
                        <div className="text-xs font-bold">{mod.name}</div>
                        <div className="text-[11px] text-slate-500 mt-0.5 leading-snug">{mod.description}</div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>

            {/* Addon Modules Grid */}
            <div className="pt-2">
              <div className="text-[11px] font-bold text-purple-700 mb-2 uppercase">
                الوحدات الإضافية المتقدمة:
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
                          ? 'bg-purple-50/70 border-purple-300 text-slate-900' 
                          : 'bg-white border-slate-200 text-slate-600 hover:border-slate-300'
                      }`}
                    >
                      <div className={`mt-0.5 rounded p-0.5 ${isChecked ? 'bg-purple-600 text-white' : 'border border-slate-300 text-transparent'}`}>
                        <Check className="w-3 h-3" />
                      </div>
                      <div className="flex-1">
                        <div className="text-xs font-bold text-purple-900">{mod.name}</div>
                        <div className="text-[11px] text-slate-500 mt-0.5 leading-snug">{mod.description}</div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>

          </div>

          {/* Notes */}
          <div>
            <label className="block text-xs font-bold text-slate-700 mb-1">
              ملاحظات داخلية
            </label>
            <textarea
              rows="2"
              placeholder="مثال: تم الاتفاق على اشتراك سنوي، مفعل له التصنيع..."
              value={formData.notes}
              onChange={(e) => setFormData({ ...formData, notes: e.target.value })}
              className="w-full px-3.5 py-2 rounded-xl bg-slate-50 border border-slate-200 text-xs text-slate-900 focus:outline-none focus:border-blue-500 focus:bg-white"
            />
          </div>

          {/* Actions */}
          <div className="flex items-center justify-end gap-3 pt-3 border-t border-slate-100">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 rounded-xl bg-slate-100 hover:bg-slate-200 text-xs font-bold text-slate-600 transition-colors"
            >
              إلغاء
            </button>
            <button
              type="submit"
              className="px-6 py-2 rounded-xl bg-blue-600 hover:bg-blue-500 text-xs font-bold text-white shadow-xs transition-all active:scale-[0.98]"
            >
              {editingLicense ? 'حفظ التعديلات' : 'إصدار الترخيص الآن'}
            </button>
          </div>

        </form>

      </div>
    </div>
  );
}
