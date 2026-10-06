import React from 'react';
import { 
  ShieldCheck, AlertTriangle, Clock, Layers, 
  ArrowUpRight, Users, Plus, KeyRound, Sparkles 
} from 'lucide-react';
import { ERP_MODULES } from '../config/modules';

export default function OverviewView({ licenses, onOpenCreate, onGoToLicenses }) {
  const expiringSoon = licenses.filter(lic => {
    if (!lic.expires_at) return false;
    const diffDays = Math.ceil((new Date(lic.expires_at) - new Date()) / (1000 * 3600 * 24));
    return diffDays > 0 && diffDays <= 30;
  });

  return (
    <div className="space-y-6">
      
      {/* Alert Banner for Expiring Licenses (Mantis Alert) */}
      {expiringSoon.length > 0 && (
        <div className="p-4 rounded-2xl bg-amber-500/10 border border-amber-500/25 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-xl bg-amber-500/20 text-amber-500">
              <AlertTriangle className="w-5 h-5" />
            </div>
            <div>
              <h4 className="text-xs font-bold text-slate-900 dark:text-white">
                تنبيه: يوجد {expiringSoon.length} ترخيص ينتهي خلال أقل من 30 يوماً
              </h4>
              <p className="text-[11px] text-slate-500 dark:text-gray-400">
                يمكنك تجديد اشتراك العميل بنقرة زر واحدة دون الحاجة لتغيير المفتاح عنده
              </p>
            </div>
          </div>

          <button
            onClick={onGoToLicenses}
            className="px-3.5 py-1.5 rounded-xl bg-amber-500 text-slate-950 font-bold text-xs hover:bg-amber-400 transition-colors shrink-0"
          >
            عرض التراخيص المنتهية قريباً
          </button>
        </div>
      )}

      {/* Grid: Modules Adoption + Quick Actions */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        
        {/* Module Popularity (2 cols) */}
        <div className="lg:col-span-2 p-6 rounded-2xl bg-white dark:bg-[#111827] border border-slate-200/80 dark:border-white/5 shadow-sm space-y-4">
          <div className="flex items-center justify-between">
            <div>
              <h3 className="text-sm font-bold text-slate-900 dark:text-white">
                نسبة تفعيل الموديولات لدى العملاء
              </h3>
              <p className="text-xs text-slate-500 dark:text-gray-400">
                متابعة الموديولات الأكثر طلباً لترتيب أولويات التطوير
              </p>
            </div>
            <span className="text-xs font-semibold text-indigo-600 dark:text-indigo-400">
              إجمالي {ERP_MODULES.length} موديول
            </span>
          </div>

          <div className="space-y-3 pt-2">
            {ERP_MODULES.slice(0, 7).map(mod => {
              const activeCount = licenses.filter(l => l.status === 'active' && (l.features || []).includes(mod.id)).length;
              const percent = licenses.length > 0 ? Math.round((activeCount / licenses.length) * 100) : 0;

              return (
                <div key={mod.id} className="space-y-1">
                  <div className="flex justify-between text-xs">
                    <span className="font-medium text-slate-700 dark:text-gray-300">
                      {mod.name}
                    </span>
                    <span className="font-mono text-slate-500 dark:text-gray-400 font-semibold">
                      {percent}% ({activeCount} عميل)
                    </span>
                  </div>
                  <div className="w-full h-2 rounded-full bg-slate-100 dark:bg-white/5 overflow-hidden">
                    <div 
                      className={`h-full rounded-full ${mod.category === 'addon' ? 'bg-purple-600' : 'bg-indigo-600'}`}
                      style={{ width: `${Math.max(percent, 8)}%` }}
                    />
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Quick Launch Card (1 col) */}
        <div className="p-6 rounded-2xl bg-gradient-to-br from-indigo-900/40 via-indigo-950/30 to-[#111827] border border-indigo-500/20 shadow-sm flex flex-col justify-between">
          <div>
            <div className="p-3 rounded-xl bg-indigo-600 text-white w-max shadow-md shadow-indigo-600/30 mb-4">
              <KeyRound className="w-6 h-6" />
            </div>
            <h3 className="text-base font-bold text-slate-900 dark:text-white mb-2">
              إصدار ترخيص تجاري فوري
            </h3>
            <p className="text-xs text-slate-500 dark:text-gray-300 leading-relaxed">
              قم بإنشاء كود ترخيص جديد ومخصص لكل عميل مع اختيار الموديولات التي يحتاجها بدقة، وتحديد أجهزته المصرحة.
            </p>
          </div>

          <button
            onClick={onOpenCreate}
            className="mt-6 w-full flex items-center justify-center gap-2 py-3 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white text-xs font-bold shadow-md shadow-indigo-600/30 transition-all active:scale-[0.98]"
          >
            <Plus className="w-4 h-4" />
            <span>إنشاء ترخيص الآن</span>
          </button>
        </div>

      </div>

    </div>
  );
}
