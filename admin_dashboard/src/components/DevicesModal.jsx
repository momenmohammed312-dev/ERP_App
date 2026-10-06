import React, { useState, useEffect } from 'react';
import { X, Laptop, Trash2, Clock, MapPin, Hash, CheckCircle2, ShieldAlert } from 'lucide-react';
import { api } from '../services/api';

export default function DevicesModal({ isOpen, onClose, license, onDeviceUnbound }) {
  const [devices, setDevices] = useState([]);
  const [loading, setLoading] = useState(true);
  const [unbindingId, setUnbindingId] = useState(null);

  useEffect(() => {
    if (isOpen && license) {
      loadDevices();
    }
  }, [isOpen, license]);

  const loadDevices = async () => {
    setLoading(true);
    try {
      const data = await api.getDevices(license.id);
      setDevices(data);
    } catch (err) {
      console.error('Failed to load devices:', err);
    } finally {
      setLoading(false);
    }
  };

  const handleUnbind = async (device) => {
    if (!confirm(`هل أنت متأكد من إلغاء ربط هذا الجهاز (${device.device_name || 'جهاز غير معروف'})؟ سيتم تحرير خانة ترخيص ويمكن للعميل التفعيل على جهاز جديد.`)) {
      return;
    }

    setUnbindingId(device.id);
    try {
      await api.unbindDevice(device.id);
      setDevices(prev => prev.filter(d => d.id !== device.id));
      onDeviceUnbound();
    } catch (err) {
      alert('فشل إلغاء ربط الجهاز: ' + err.message);
    } finally {
      setUnbindingId(null);
    }
  };

  if (!isOpen || !license) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md">
      <div className="relative w-full max-w-2xl rounded-3xl bg-[#111827] border border-white/10 shadow-2xl overflow-hidden">
        
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-5 border-b border-white/5 bg-white/[0.02]">
          <div className="flex items-center gap-3">
            <div className="p-2.5 rounded-xl bg-blue-500/10 text-blue-400 border border-blue-500/20">
              <Laptop className="w-5 h-5" />
            </div>
            <div>
              <h2 className="text-base font-bold text-white">
                الأجهزة المرتبطة بترخيص: {license.client_name}
              </h2>
              <div className="text-xs font-mono text-indigo-400 mt-0.5">
                {license.license_key}
              </div>
            </div>
          </div>

          <button
            onClick={onClose}
            className="p-2 rounded-xl text-gray-400 hover:text-white hover:bg-white/5 transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Content */}
        <div className="p-6">
          <div className="flex items-center justify-between mb-4">
            <div className="text-xs text-gray-400">
              الأجهزة المستخدمة حالياً: <span className="font-bold text-white">{devices.length}</span> من أصل <span className="font-bold text-white">{license.max_devices || 1}</span> جهاز مصرح
            </div>
          </div>

          {loading ? (
            <div className="py-12 text-center text-gray-400 text-xs">
              جاري فحص الأجهزة المتصلة...
            </div>
          ) : devices.length === 0 ? (
            <div className="py-12 text-center rounded-2xl bg-white/[0.01] border border-white/5">
              <Laptop className="w-10 h-10 text-gray-600 mx-auto mb-2" />
              <div className="text-sm font-semibold text-gray-300">لا توجد أجهزة مربوطة بهذا الترخيص حتى الآن</div>
              <p className="text-xs text-gray-500 mt-1 max-w-xs mx-auto">
                عند قيام العميل بفتح البرنامج وإدخال المفتاح، سيتم تسجيل جهازه وتثبيته تلقائياً هنا
              </p>
            </div>
          ) : (
            <div className="space-y-3">
              {devices.map((dev) => (
                <div
                  key={dev.id}
                  className="rounded-2xl p-4 bg-surface-panel/50 border border-white/5 flex flex-col sm:flex-row sm:items-center justify-between gap-4 hover:border-white/10 transition-colors"
                >
                  <div className="space-y-1.5 flex-1">
                    <div className="flex items-center gap-2">
                      <span className="font-semibold text-sm text-white">
                        {dev.device_name || 'جهاز كمبيوتر POS'}
                      </span>
                      <span className="text-[10px] px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 font-medium">
                        مرتبط ونشط
                      </span>
                    </div>

                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-1 text-[11px] text-gray-400 pt-1">
                      <div className="flex items-center gap-1.5 font-mono truncate" title={dev.machine_guid}>
                        <Hash className="w-3 h-3 text-gray-500" />
                        <span className="text-gray-500">GUID:</span>
                        <span className="truncate">{dev.machine_guid || 'N/A'}</span>
                      </div>

                      <div className="flex items-center gap-1.5 font-mono truncate" title={dev.install_uuid}>
                        <Hash className="w-3 h-3 text-gray-500" />
                        <span className="text-gray-500">Install:</span>
                        <span className="truncate">{dev.install_uuid || 'N/A'}</span>
                      </div>

                      <div className="flex items-center gap-1.5">
                        <Clock className="w-3 h-3 text-gray-500" />
                        <span>آخر اتصال: {dev.last_checkin_at ? new Date(dev.last_checkin_at).toLocaleDateString('ar-EG') : 'غير متوفر'}</span>
                      </div>

                      <div className="flex items-center gap-1.5">
                        <MapPin className="w-3 h-3 text-gray-500" />
                        <span>IP: {dev.last_ip || '127.0.0.1'}</span>
                      </div>
                    </div>
                  </div>

                  {/* Unbind CTA */}
                  <div>
                    <button
                      onClick={() => handleUnbind(dev)}
                      disabled={unbindingId === dev.id}
                      className="w-full sm:w-auto flex items-center justify-center gap-1.5 px-3.5 py-2 rounded-xl bg-rose-500/10 hover:bg-rose-500/20 border border-rose-500/20 text-rose-300 text-xs font-semibold transition-colors disabled:opacity-50"
                      title="فصل الجهاز ليتمكن العميل من التفعيل على جهاز جديد"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                      <span>{unbindingId === dev.id ? 'جاري الفصل...' : 'إلغاء الربط'}</span>
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}

          {/* Device Tip Note */}
          <div className="mt-6 p-3.5 rounded-2xl bg-indigo-500/5 border border-indigo-500/15 flex items-start gap-2.5 text-xs text-indigo-300">
            <ShieldAlert className="w-4 h-4 text-indigo-400 mt-0.5 shrink-0" />
            <p className="leading-relaxed">
              إذا قام العميل بتغيير الويندوز أو شراء كمبيوتر جديد وظهرت له رسالة «تجاوز الحد الأقصى للأجهزة»، يمكنك بكل بساطة النقر على «إلغاء الربط» للجهاز القديم ليتمكن من التفعيل فوراً على جهازه الجديد.
            </p>
          </div>
        </div>

        {/* Footer */}
        <div className="px-6 py-4 border-t border-white/5 bg-white/[0.01] flex justify-end">
          <button
            onClick={onClose}
            className="px-5 py-2 rounded-xl bg-white/5 hover:bg-white/10 text-xs font-medium text-gray-300 transition-colors"
          >
            إغلاق
          </button>
        </div>

      </div>
    </div>
  );
}
