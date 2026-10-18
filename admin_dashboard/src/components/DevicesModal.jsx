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
    if (!confirm(`هل أنت متأكد من إلغاء ربط هذا الجهاز (${device.device_name || 'جهاز غير معروف'})؟ سيتم تحرير مكان الترخيص ليتمكن العميل من التفعيل على جهاز جديد.`)) {
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
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40 backdrop-blur-xs">
      <div className="relative w-full max-w-2xl rounded-2xl bg-white border border-slate-200 shadow-xl overflow-hidden">
        
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-slate-100 bg-slate-50/50">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-xl bg-blue-50 text-blue-600 border border-blue-200">
              <Laptop className="w-5 h-5" />
            </div>
            <div>
              <h2 className="text-sm font-bold text-slate-900">
                الأجهزة المربوطة بترخيص: {license.client_name}
              </h2>
              <div className="text-xs font-mono font-bold text-blue-700 mt-0.5">
                {license.license_key}
              </div>
            </div>
          </div>

          <button
            onClick={onClose}
            className="p-1.5 rounded-lg text-slate-400 hover:text-slate-600 hover:bg-slate-100 transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Content */}
        <div className="p-6">
          <div className="flex items-center justify-between mb-4">
            <div className="text-xs text-slate-600 font-semibold">
              الأجهزة المسجلة: <span className="text-blue-700 font-bold">{devices.length}</span> من أصل <span className="text-slate-900 font-bold">{license.max_devices || 1}</span> جهاز مصرح
            </div>
          </div>

          {loading ? (
            <div className="py-10 text-center text-slate-400 text-xs">
              جاري فحص الأجهزة المعتمدة...
            </div>
          ) : devices.length === 0 ? (
            <div className="py-10 text-center rounded-2xl bg-slate-50 border border-slate-200">
              <Laptop className="w-8 h-8 text-slate-400 mx-auto mb-2" />
              <div className="text-xs font-bold text-slate-700">لا توجد أجهزة مربوطة بهذا الترخيص حتى الآن</div>
              <p className="text-[11px] text-slate-500 mt-1">
                عند فتح البرنامج وإدخال المفتاح سيتم توثيق الجهاز تلقائياً هنا
              </p>
            </div>
          ) : (
            <div className="space-y-3">
              {devices.map((dev) => (
                <div
                  key={dev.id}
                  className="rounded-xl p-4 bg-slate-50 border border-slate-200 flex flex-col sm:flex-row sm:items-center justify-between gap-4"
                >
                  <div className="space-y-1 flex-1">
                    <div className="flex items-center gap-2">
                      <span className="font-bold text-xs text-slate-900">
                        {dev.device_name || 'كمبيوتر كاشير ويندوز'}
                      </span>
                      <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-50 text-emerald-700 border border-emerald-200">
                        نشط ومعتمد
                      </span>
                    </div>

                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-1 text-[11px] text-slate-500 pt-1 font-mono">
                      <div className="truncate">
                        <span className="text-slate-400">GUID: </span>{dev.machine_guid || 'N/A'}
                      </div>
                      <div className="truncate">
                        <span className="text-slate-400">UUID: </span>{dev.install_uuid || 'N/A'}
                      </div>
                      <div>
                        <span className="text-slate-400">آخر اتصال: </span>{dev.last_checkin_at ? new Date(dev.last_checkin_at).toLocaleDateString('ar-EG') : 'اليوم'}
                      </div>
                      <div>
                        <span className="text-slate-400">IP: </span>{dev.last_ip || '127.0.0.1'}
                      </div>
                    </div>
                  </div>

                  <div>
                    <button
                      onClick={() => handleUnbind(dev)}
                      disabled={unbindingId === dev.id}
                      className="w-full sm:w-auto flex items-center justify-center gap-1.5 px-3 py-1.5 rounded-xl bg-rose-50 hover:bg-rose-100 border border-rose-200 text-rose-700 text-xs font-bold transition-colors disabled:opacity-50"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                      <span>{unbindingId === dev.id ? 'جاري الفصل...' : 'فك الارتباط'}</span>
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}

          <div className="mt-5 p-3 rounded-xl bg-blue-50 border border-blue-200 text-xs text-blue-800 flex items-start gap-2 leading-relaxed">
            <ShieldAlert className="w-4 h-4 text-blue-600 mt-0.5 shrink-0" />
            <p>
              إذا قام العميل بتغيير الويندوز أو شراء كمبيوتر جديد، انقر على «فك الارتباط» لتحرير الترخيص ليعمل فوراً على جهازه الجديد.
            </p>
          </div>
        </div>

        {/* Footer */}
        <div className="px-6 py-3 border-t border-slate-100 bg-slate-50/50 flex justify-end">
          <button
            onClick={onClose}
            className="px-4 py-1.5 rounded-xl bg-slate-200 hover:bg-slate-300 text-xs font-bold text-slate-700 transition-colors"
          >
            إغلاق
          </button>
        </div>

      </div>
    </div>
  );
}
