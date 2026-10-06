import React from 'react';
import { ShieldCheck, Laptop, Clock, AlertTriangle } from 'lucide-react';

export default function StatsGrid({ licenses }) {
  const total = licenses.length;
  const active = licenses.filter(l => l.status === 'active' && new Date(l.expires_at) > new Date()).length;
  const suspendedOrExpired = licenses.filter(l => l.status === 'suspended' || new Date(l.expires_at) <= new Date()).length;
  const totalBoundDevices = licenses.reduce((sum, l) => sum + (l.bound_devices_count || 0), 0);

  const stats = [
    {
      label: 'إجمالي التراخيص',
      value: total,
      sub: 'تراخيص مسجلة بالنظام',
      icon: ShieldCheck,
      color: 'indigo',
      glow: 'glow-indigo',
    },
    {
      label: 'التراخيص النشطة',
      value: active,
      sub: 'تعمل حالياً بدون مشاكل',
      icon: ShieldCheck,
      color: 'emerald',
      glow: 'glow-emerald',
    },
    {
      label: 'معلقة أو منتهية',
      value: suspendedOrExpired,
      sub: 'بحاجة لتجديد أو موقوفة',
      icon: AlertTriangle,
      color: 'amber',
      glow: '',
    },
    {
      label: 'الأجهزة المرتبطة',
      value: totalBoundDevices,
      sub: 'كمبيوترات وهواتف متصلة',
      icon: Laptop,
      color: 'blue',
      glow: '',
    },
  ];

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
      {stats.map((stat, i) => {
        const Icon = stat.icon;
        return (
          <div
            key={i}
            className="group relative rounded-2xl p-[1px] bg-gradient-to-b from-white/10 to-white/0 hover:from-white/20 transition-all duration-300"
          >
            <div className="rounded-[calc(1rem-1px)] bg-[#111827]/90 p-5 backdrop-blur-xl h-full flex flex-col justify-between">
              <div className="flex items-center justify-between mb-4">
                <span className="text-sm font-medium text-gray-400">
                  {stat.label}
                </span>
                <div className={`p-2.5 rounded-xl bg-white/5 border border-white/5 text-${stat.color}-400 group-hover:scale-105 transition-transform`}>
                  <Icon className="w-5 h-5" />
                </div>
              </div>

              <div>
                <div className="text-3xl font-extrabold text-white tracking-tight mb-1">
                  {stat.value}
                </div>
                <div className="text-xs text-gray-500">
                  {stat.sub}
                </div>
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}
