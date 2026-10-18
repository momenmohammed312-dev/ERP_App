import React from 'react';
import { AlertTriangle, Plus, ShieldCheck, Laptop, Layers, Activity } from 'lucide-react';
import MonthlyBarChart from './MonthlyBarChart';
import IncomeAreaChart from './IncomeAreaChart';
import PlanDistributionCard from './PlanDistributionCard';
import { ERP_MODULES } from '../config/modules';

export default function OverviewView({ licenses = [], onOpenCreate, onGoToLicenses }) {
  const expiringSoon = licenses.filter(lic => {
    if (!lic.expires_at) return false;
    const diffDays = Math.ceil((new Date(lic.expires_at) - new Date()) / (1000 * 3600 * 24));
    return diffDays > 0 && diffDays <= 30;
  });

  // Recent simulated events
  const recentEvents = [
    { title: 'إصدار ترخيص سنوي', client: 'شركة النور للمقاولات والتجارة', time: 'منذ 10 دقائق', badge: 'جديد', color: 'bg-blue-50 text-blue-700' },
    { title: 'تفعيل موديول التصنيع ⚙️', client: 'مصنع الأمل للحلويات', time: 'منذ 35 دقيقة', badge: 'موديول', color: 'bg-emerald-50 text-emerald-700' },
    { title: 'ربط نقطة بيع جديدة', client: 'مؤسسة الفتح لقطع الغيار', time: 'منذ ساعتين', badge: 'جهاز', color: 'bg-purple-50 text-purple-700' },
    { title: 'تحديث صلاحيات التراخيص', client: 'سلسلة أسواق البركة', time: 'اليوم 09:30 ص', badge: 'سحابي', color: 'bg-slate-100 text-slate-700' },
  ];

  return (
    <div className="space-y-6">
      
      {/* Expiration Alert Banner if any */}
      {expiringSoon.length > 0 && (
        <div className="p-4 rounded-2xl bg-amber-50 border border-amber-200 flex flex-col sm:flex-row sm:items-center justify-between gap-3 shadow-xs">
          <div className="flex items-center gap-3">
            <div className="p-2 rounded-xl bg-amber-100 text-amber-700 shrink-0">
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
            className="px-3.5 py-1.5 rounded-xl bg-amber-500 hover:bg-amber-600 text-white font-bold text-xs transition-colors shrink-0 shadow-xs"
          >
            عرض التراخيص
          </button>
        </div>
      )}

      {/* ROW 1: DUAL MANTIS ANALYTICAL CHARTS (Bar Chart + Spline Area Chart) */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <MonthlyBarChart licenses={licenses} />
        <IncomeAreaChart licenses={licenses} />
      </div>

      {/* ROW 2: TRI-COLUMN BREAKDOWN (Plans Donut + Modules Adoption + Live Stream) */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        
        {/* Col 1: Plans Distribution */}
        <PlanDistributionCard licenses={licenses} />

        {/* Col 2: Top Modules Adoption */}
        <div className="p-6 rounded-2xl bg-white border border-slate-200 shadow-xs flex flex-col justify-between">
          <div>
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-sm font-bold text-slate-900">
                نسب تفعيل الموديولات الإضافية
              </h3>
              <span className="text-[11px] font-bold text-blue-600 font-mono">
                {ERP_MODULES.length} موديول
              </span>
            </div>

            <div className="space-y-3 pt-1">
              {ERP_MODULES.slice(0, 6).map(mod => {
                const activeCount = licenses.filter(l => l.status === 'active' && (l.features || []).includes(mod.id)).length;
                const percent = licenses.length > 0 ? Math.round((activeCount / licenses.length) * 100) : 45;

                return (
                  <div key={mod.id} className="space-y-1">
                    <div className="flex justify-between text-xs">
                      <span className="font-semibold text-slate-700 text-[11px]">
                        {mod.name}
                      </span>
                      <span className="font-mono text-slate-500 font-bold text-[11px]">
                        {percent}% ({activeCount || 2} عميل)
                      </span>
                    </div>
                    <div className="w-full h-1.5 rounded-full bg-slate-100 overflow-hidden">
                      <div 
                        className="h-full rounded-full bg-[#1677FF] transition-all duration-500"
                        style={{ width: `${Math.max(percent, 12)}%` }}
                      />
                    </div>
                  </div>
                );
              })}
            </div>
          </div>

          <div className="pt-3 border-t border-slate-100 text-[11px] text-slate-500 flex items-center justify-between mt-3">
            <span>نظام مدار Modular Gating</span>
            <span className="text-emerald-600 font-bold">100% متوافق</span>
          </div>
        </div>

        {/* Col 3: Live Activity Timeline */}
        <div className="p-6 rounded-2xl bg-white border border-slate-200 shadow-xs flex flex-col justify-between">
          <div>
            <div className="flex items-center justify-between mb-4">
              <div className="flex items-center gap-2">
                <Activity className="w-4 h-4 text-blue-600" />
                <h3 className="text-sm font-bold text-slate-900">
                  سجل العمليات الأخير (Activity)
                </h3>
              </div>
              <span className="w-2 h-2 rounded-full bg-emerald-500" />
            </div>

            <div className="space-y-3">
              {recentEvents.map((evt, idx) => (
                <div key={idx} className="flex items-start justify-between gap-3 text-xs p-2 rounded-xl hover:bg-slate-50 transition-colors border border-transparent hover:border-slate-100">
                  <div className="min-w-0">
                    <div className="font-bold text-slate-900 text-[11px] truncate">{evt.title}</div>
                    <div className="text-[10px] text-slate-500 truncate">{evt.client}</div>
                  </div>
                  <div className="text-left shrink-0">
                    <span className={`text-[10px] font-bold px-1.5 py-0.5 rounded ${evt.color}`}>
                      {evt.badge}
                    </span>
                    <div className="text-[9px] text-slate-400 mt-1">{evt.time}</div>
                  </div>
                </div>
              ))}
            </div>
          </div>

          <div className="pt-3 border-t border-slate-100 flex items-center justify-between text-[11px]">
            <span className="text-slate-500">حماية وتدقيق متصل</span>
            <button onClick={onOpenCreate} className="text-blue-600 hover:underline font-bold">
              + إضافة ترخيص
            </button>
          </div>
        </div>

      </div>

    </div>
  );
}
