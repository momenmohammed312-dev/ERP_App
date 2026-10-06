import React from 'react';
import { 
  ShieldCheck, Laptop, Clock, AlertTriangle, 
  TrendingUp, CheckCircle2, ShieldAlert, Cpu 
} from 'lucide-react';

export default function StatsGrid({ licenses }) {
  const total = licenses.length;
  const active = licenses.filter(l => l.status === 'active' && new Date(l.expires_at) > new Date()).length;
  const suspendedOrExpired = licenses.filter(l => l.status === 'suspended' || new Date(l.expires_at) <= new Date()).length;
  const totalBoundDevices = licenses.reduce((sum, l) => sum + (l.bound_devices_count || 0), 0);

  const activeRate = total > 0 ? Math.round((active / total) * 100) : 100;

  const stats = [
    {
      title: 'إجمالي التراخيص المسجلة',
      value: total,
      trend: '+100% قاعدة العملاء',
      trendType: 'positive',
      icon: ShieldCheck,
      color: 'indigo',
    },
    {
      title: 'التراخيص النشطة حالياً',
      value: active,
      trend: `${activeRate}% نسبة التراخيص الفعالة`,
      trendType: 'positive',
      icon: CheckCircle2,
      color: 'emerald',
    },
    {
      title: 'تراخيص معلقة أو منتهية',
      value: suspendedOrExpired,
      trend: suspendedOrExpired > 0 ? `${suspendedOrExpired} بحاجة لمتابعة` : 'لا توجد متأخرات',
      trendType: suspendedOrExpired > 0 ? 'warning' : 'positive',
      icon: AlertTriangle,
      color: 'amber',
    },
    {
      title: 'الأجهزة المرتبطة والنقاط',
      value: totalBoundDevices,
      trend: 'أجهزة ويندوز وأندرويد',
      trendType: 'neutral',
      icon: Laptop,
      color: 'blue',
    },
  ];

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
      {stats.map((item, idx) => {
        const Icon = item.icon;

        return (
          <div
            key={idx}
            className="p-5 rounded-2xl bg-white dark:bg-[#111827] border border-slate-200/80 dark:border-white/5 shadow-sm hover:shadow-md transition-all group"
          >
            <div className="flex items-center justify-between mb-3">
              <span className="text-xs font-semibold text-slate-500 dark:text-gray-400">
                {item.title}
              </span>
              <div className="p-2 rounded-xl bg-slate-50 dark:bg-white/5 text-slate-700 dark:text-gray-300 group-hover:scale-105 transition-transform">
                <Icon className="w-4 h-4" />
              </div>
            </div>

            <div className="flex items-baseline justify-between">
              <div className="text-3xl font-extrabold tracking-tight text-slate-900 dark:text-white font-mono">
                {item.value}
              </div>

              <span className={`text-[11px] font-semibold px-2 py-0.5 rounded-full border ${
                item.trendType === 'positive'
                  ? 'bg-emerald-50 text-emerald-700 border-emerald-200 dark:bg-emerald-500/10 dark:text-emerald-400 dark:border-emerald-500/20'
                  : item.trendType === 'warning'
                  ? 'bg-rose-50 text-rose-700 border-rose-200 dark:bg-rose-500/10 dark:text-rose-400 dark:border-rose-500/20'
                  : 'bg-slate-50 text-slate-600 border-slate-200 dark:bg-white/5 dark:text-gray-400 dark:border-white/10'
              }`}>
                {item.trend}
              </span>
            </div>
          </div>
        );
      })}
    </div>
  );
}
