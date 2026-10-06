import React from 'react';
import { AlertTriangle, KeyRound, Plus } from 'lucide-react';
import { ERP_MODULES } from '../config/modules';

export default function OverviewView({ licenses, onOpenCreate, onGoToLicenses }) {
  const expiringSoon = licenses.filter(lic => {
    if (!lic.expires_at) return false;
    const diffDays = Math.ceil((new Date(lic.expires_at) - new Date()) / (1000 * 3600 * 24));
    return diffDays > 0 && diffDays <= 30;
  });

  return (
    <div className="space-y-6">
      
      {/* Alert Banner */}
      {expiringSoon.length > 0 && (
        <div className="p-4 rounded-2xl bg-amber-50 border border-amber-200 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-xl bg-amber-100 text-amber-700">
              <AlertTriangle className="w-5 h-5" />
            </div>
            <div>
              <h4 className="text-xs font-bold text-slate-900">
                تنبيه: يوجد {expiringSoon.length} ترخيص ينتهي خلال أقل من 30 يوماً
              </h4>
              <p className="text-[11px] text-slate-600">
                يمكنك تجديد اشتراك العميل بنقرة واحدة سحابياً دون الحاجة لتغيير المفتاح عنده
              </p>
            </div>
          </div>

          <button
            onClick={onGoToLicenses}
            className="px-3.5 py-1.5 rounded-xl bg-amber-500 hover:bg-amber-600 text-white font-bold text-xs transition-colors shrink-0"
          >
            عرض التراخيص
          </button>
        </div>
      )}

      {/* Grid: Modules Adoption + Quick Actions */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        
        {/* Module Adoption (2 cols) */}
        <div className="lg:col-span-2 p-6 rounded-2xl bg-white border border-slate-200/90 shadow-xs space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <h3 className="text-sm font-bold text-slate-900">
                نسبة تفعيل الموديولات لدى العملاء في مدار
              </h3>
              <p className="text-xs text-slate-500">
                متابعة الموديولات الأكثر نشاطاً لترتيب خطة التحديثات القادمة
              </p>
            </div>
            <span className="text-xs font-bold text-blue-700 font-mono">
              إجمالي {ERP_MODULES.length} موديول
            </span>
          </div>

          <div className="space-y-3 pt-1">
            {ERP_MODULES.slice(0, 7).map(mod => {
              const activeCount = licenses.filter(l => l.status === 'active' && (l.features || []).includes(mod.id)).length;
              const percent = licenses.length > 0 ? Math.round((activeCount / licenses.length) * 100) : 0;

              return (
                <div key={mod.id} className="space-y-1">
                  <div className="flex justify-between text-xs">
                    <span className="font-semibold text-slate-700">
                      {mod.name}
                    </span>
                    <span className="font-mono text-slate-500 font-bold">
                      {percent}% ({activeCount} عميل)
                    </span>
                  </div>
                  <div className="w-full h-2 rounded-full bg-slate-100 overflow-hidden">
                    <div 
                      className={`h-full rounded-full transition-all duration-500 ${mod.category === 'addon' ? 'bg-purple-600' : 'bg-blue-600'}`}
                      style={{ width: `${Math.max(percent, 8)}%` }}
                    />
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Quick Launch Card (1 col) */}
        <div className="p-6 rounded-2xl bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 text-white shadow-xs flex flex-col justify-between">
          <div>
            <div className="w-12 h-12 rounded-xl bg-white/10 p-2 border border-white/10 mb-4 flex items-center justify-center">
              <img src="/madar_logo.png" alt="مدار" className="w-full h-full object-contain invert brightness-200" />
            </div>
            <h3 className="text-base font-extrabold text-white mb-2">
              إصدار ترخيص تجاري فوري
            </h3>
            <p className="text-xs text-slate-300 leading-relaxed">
              قم بإنشاء كود ترخيص فوري مخصص لكل عميل بنظام مدار ERP، مع تفعيل الموديولات المختارة وتحديد الأجهزة المصرحة.
            </p>
          </div>

          <button
            onClick={onOpenCreate}
            className="mt-6 w-full flex items-center justify-center gap-2 py-3 rounded-xl bg-blue-600 hover:bg-blue-500 text-white text-xs font-bold shadow-md shadow-blue-600/30 transition-all active:scale-[0.98]"
          >
            <Plus className="w-4 h-4" />
            <span>إصدار ترخيص جديد الآن</span>
          </button>
        </div>

      </div>

    </div>
  );
}
