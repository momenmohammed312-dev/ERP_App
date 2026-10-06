import React from 'react';
import { ShieldCheck, CheckCircle2, AlertTriangle, Laptop } from 'lucide-react';

export default function StatsGrid({ licenses }) {
  const total = licenses.length;
  const active = licenses.filter(l => l.status === 'active' && (!l.expires_at || new Date(l.expires_at) > new Date())).length;
  const suspendedOrExpired = licenses.filter(l => l.status === 'suspended' || (l.expires_at && new Date(l.expires_at) <= new Date())).length;
  const totalBoundDevices = licenses.reduce((sum, l) => sum + (l.bound_devices_count || 0), 0);

  const activeRate = total > 0 ? Math.round((active / total) * 100) : 100;

  const stats = [
    {
      title: 'إجمالي التراخيص المسجلة',
      value: total,
      trend: '+100% قاعدة العملاء',
      trendClass: 'bg-blue-50 text-blue-700 border-blue-200',
      icon: ShieldCheck,
      iconClass: 'bg-blue-50 text-blue-600',
    },
    {
      title: 'التراخيص النشطة',
      value: active,
      trend: `${activeRate}% نسبة الفعالية`,
      trendClass: 'bg-emerald-50 text-emerald-700 border-emerald-200',
      icon: CheckCircle2,
      iconClass: 'bg-emerald-50 text-emerald-600',
    },
    {
      title: 'تراخيص معلقة أو منتهية',
      value: suspendedOrExpired,
      trend: suspendedOrExpired > 0 ? `${suspendedOrExpired} بحاجة لتجديد` : 'لا توجد متأخرات',
      trendClass: suspendedOrExpired > 0 ? 'bg-rose-50 text-rose-700 border-rose-200' : 'bg-slate-50 text-slate-600 border-slate-200',
      icon: AlertTriangle,
      iconClass: suspendedOrExpired > 0 ? 'bg-rose-50 text-rose-600' : 'bg-slate-50 text-slate-500',
    },
    {
      title: 'الأجهزة المرتبطة والنقاط',
      value: totalBoundDevices,
      trend: 'بصمة عتاد GUID موثقة',
      trendClass: 'bg-slate-50 text-slate-700 border-slate-200',
      icon: Laptop,
      iconClass: 'bg-slate-50 text-slate-600',
    },
  ];

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
      {stats.map((item, idx) => {
        const Icon = item.icon;

        return (
          <div
            key={idx}
            className="p-5 rounded-2xl bg-white border border-slate-200/90 shadow-xs hover:border-slate-300 transition-all"
          >
            <div className="flex items-center justify-between mb-3">
              <span className="text-xs font-bold text-slate-500">
                {item.title}
              </span>
              <div className={`p-2 rounded-xl border border-slate-100 ${item.iconClass}`}>
                <Icon className="w-4 h-4" />
              </div>
            </div>

            <div className="flex items-baseline justify-between">
              <div className="text-3xl font-extrabold tracking-tight text-slate-900 font-mono">
                {item.value}
              </div>

              <span className={`text-[11px] font-bold px-2 py-0.5 rounded-full border ${item.trendClass}`}>
                {item.trend}
              </span>
            </div>
          </div>
        );
      })}
    </div>
  );
}
