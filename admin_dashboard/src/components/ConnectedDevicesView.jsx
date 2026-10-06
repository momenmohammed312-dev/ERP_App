import React, { useState } from 'react';
import { 
  Laptop, Trash2, Clock, MapPin, Hash, 
  Search, ShieldCheck, CheckCircle2, AlertTriangle 
} from 'lucide-react';

export default function ConnectedDevicesView({ licenses, onUnbindDevice }) {
  const [search, setSearch] = useState('');

  // Collect all devices from mock / licenses
  const allDevices = licenses.flatMap(lic => {
    // If bound_devices array is not directly populated, we generate or read it
    const devs = lic.devices || [];
    if (devs.length > 0) {
      return devs.map(d => ({ ...d, client_name: lic.client_name, license_key: lic.license_key }));
    }
    // Fallback device if license has bound_devices_count > 0
    if (lic.bound_devices_count > 0) {
      return [{
        id: `dev-${lic.id}-main`,
        client_name: lic.client_name,
        license_key: lic.license_key,
        device_name: `${lic.client_name} - الجهاز الرئيسي`,
        machine_guid: `GUID-${lic.license_key.slice(-8)}`,
        install_uuid: `UUID-${lic.id}`,
        last_ip: '192.168.1.100',
        last_checkin_at: new Date().toISOString(),
        status: 'active'
      }];
    }
    return [];
  });

  const filtered = allDevices.filter(d => 
    d.client_name?.toLowerCase().includes(search.toLowerCase()) ||
    d.device_name?.toLowerCase().includes(search.toLowerCase()) ||
    d.license_key?.toLowerCase().includes(search.toLowerCase()) ||
    d.machine_guid?.toLowerCase().includes(search.toLowerCase())
  );

  return (
    <div className="space-y-6">
      
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 p-6 rounded-2xl bg-white dark:bg-[#111827] border border-slate-200/80 dark:border-white/5 shadow-sm">
        <div className="flex items-center gap-3">
          <div className="p-2.5 rounded-xl bg-blue-600 text-white shadow-md shadow-blue-600/30">
            <Laptop className="w-5 h-5" />
          </div>
          <div>
            <h2 className="text-lg font-bold text-slate-900 dark:text-white">
              الأجهزة والنقاط المرتبطة بالنظام
            </h2>
            <p className="text-xs text-slate-500 dark:text-gray-400">
              متابعة كمبيوترات الكاشير والهواتف وفك الارتباط لتحرير التراخيص
            </p>
          </div>
        </div>

        <div className="relative sm:w-72">
          <Search className="w-4 h-4 text-slate-400 absolute right-3 top-1/2 -translate-y-1/2" />
          <input
            type="text"
            placeholder="بحث باسم الجهاز أو العميل..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="w-full pr-9 pl-3 py-2 rounded-xl bg-slate-50 dark:bg-white/[0.04] border border-slate-200 dark:border-white/10 text-xs text-slate-900 dark:text-white placeholder-slate-400 focus:outline-none focus:border-indigo-500"
          />
        </div>
      </div>

      {/* Devices List Table */}
      <div className="rounded-2xl border border-slate-200/80 dark:border-white/5 bg-white dark:bg-[#111827] shadow-sm overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-right text-xs">
            <thead>
              <tr className="border-b border-slate-200/80 dark:border-white/5 bg-slate-50/70 dark:bg-white/[0.01] text-[11px] font-bold text-slate-500 dark:text-gray-400 uppercase tracking-wider">
                <th className="py-3.5 px-5">الجهاز / نقطة البيع</th>
                <th className="py-3.5 px-5">العميل والمفتاح</th>
                <th className="py-3.5 px-5">مُعرّف العتاد (Hardware GUID)</th>
                <th className="py-3.5 px-5">آخر مزامنة و IP</th>
                <th className="py-3.5 px-5">الحالة</th>
                <th className="py-3.5 px-5 text-center">إلغاء الربط</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100 dark:divide-white/5">
              {filtered.length === 0 ? (
                <tr>
                  <td colSpan="6" className="py-12 text-center text-slate-400 dark:text-gray-500">
                    <Laptop className="w-8 h-8 mx-auto mb-2 opacity-40" />
                    <p className="text-xs font-medium">لا توجد أجهزة متصلة مسجلة</p>
                  </td>
                </tr>
              ) : (
                filtered.map(dev => (
                  <tr key={dev.id} className="hover:bg-slate-50/80 dark:hover:bg-white/[0.02] transition-colors">
                    
                    <td className="py-3.5 px-5">
                      <div className="font-bold text-slate-900 dark:text-white text-xs flex items-center gap-2">
                        <Laptop className="w-3.5 h-3.5 text-indigo-500" />
                        <span>{dev.device_name || 'كمبيوتر كاشير ويندوز'}</span>
                      </div>
                      <div className="text-[10px] text-slate-400 dark:text-gray-500 font-mono mt-0.5">
                        {dev.install_uuid || 'UUID N/A'}
                      </div>
                    </td>

                    <td className="py-3.5 px-5">
                      <div className="font-semibold text-slate-800 dark:text-gray-200">
                        {dev.client_name}
                      </div>
                      <div className="text-[10px] font-mono text-indigo-600 dark:text-indigo-400 mt-0.5">
                        {dev.license_key}
                      </div>
                    </td>

                    <td className="py-3.5 px-5 font-mono text-[11px] text-slate-600 dark:text-gray-400">
                      {dev.machine_guid || 'MachineGuid N/A'}
                    </td>

                    <td className="py-3.5 px-5 text-[11px]">
                      <div className="text-slate-700 dark:text-gray-300">
                        {dev.last_checkin_at ? new Date(dev.last_checkin_at).toLocaleDateString('ar-EG') : 'نشط اليوم'}
                      </div>
                      <div className="text-[10px] font-mono text-slate-400">
                        {dev.last_ip || '127.0.0.1'}
                      </div>
                    </td>

                    <td className="py-3.5 px-5">
                      <span className="inline-flex items-center gap-1 text-[10px] font-semibold text-emerald-700 dark:text-emerald-400 bg-emerald-50 dark:bg-emerald-500/10 px-2 py-0.5 rounded-full border border-emerald-200 dark:border-emerald-500/20">
                        <span className="w-1.5 h-1.5 rounded-full bg-emerald-500" />
                        متصل ومعتمد
                      </span>
                    </td>

                    <td className="py-3.5 px-5 text-center">
                      <button
                        onClick={() => onUnbindDevice(dev)}
                        className="px-2.5 py-1 rounded-lg text-rose-600 hover:bg-rose-50 dark:hover:bg-rose-500/10 border border-rose-200 dark:border-rose-500/20 text-[11px] font-semibold transition-colors"
                        title="إلغاء الربط لتحرير مكان الترخيص"
                      >
                        فك الارتباط
                      </button>
                    </td>

                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

    </div>
  );
}
