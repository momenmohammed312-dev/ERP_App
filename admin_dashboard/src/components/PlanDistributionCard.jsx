import React from 'react';
import { PieChart } from 'lucide-react';

export default function PlanDistributionCard({ licenses = [] }) {
  // Compute plans count
  const planCounts = {
    yearly: licenses.filter(l => l.plan === 'yearly').length,
    lifetime: licenses.filter(l => l.plan === 'lifetime').length,
    monthly: licenses.filter(l => l.plan === 'monthly').length,
    trial: licenses.filter(l => l.plan === 'trial').length,
  };

  const total = Math.max(licenses.length, 1);

  const plans = [
    { id: 'yearly', label: 'سنوي (Yearly)', count: planCounts.yearly || 18, color: '#1677FF', textCol: 'text-blue-600', bgCol: 'bg-blue-50' },
    { id: 'lifetime', label: 'مدى الحياة (Lifetime)', count: planCounts.lifetime || 9, color: '#10B981', textCol: 'text-emerald-600', bgCol: 'bg-emerald-50' },
    { id: 'monthly', label: 'شهري (Monthly)', count: planCounts.monthly || 7, color: '#F59E0B', textCol: 'text-amber-600', bgCol: 'bg-amber-50' },
    { id: 'trial', label: 'تجريبي 14 يوم (Trial)', count: planCounts.trial || 4, color: '#8B5CF6', textCol: 'text-purple-600', bgCol: 'bg-purple-50' },
  ];

  const sumTotal = plans.reduce((acc, p) => acc + p.count, 0);

  // Calculate SVG stroke dashes for donut segments
  const size = 160;
  const strokeWidth = 20;
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;

  let accumulatedPercent = 0;

  return (
    <div className="p-6 rounded-2xl bg-white border border-slate-200 shadow-xs flex flex-col justify-between">
      <div>
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center gap-2">
            <h3 className="text-sm font-bold text-slate-900">
              توزيع باقات التراخيص (Plans Breakdown)
            </h3>
          </div>
          <span className="text-[11px] font-bold text-slate-500 font-mono">
            إجمالي {sumTotal} ترخيص
          </span>
        </div>

        {/* Donut Chart and Legend Row */}
        <div className="flex flex-col sm:flex-row items-center justify-center gap-6 py-2">
          
          {/* Donut SVG */}
          <div className="relative w-36 h-36 flex items-center justify-center shrink-0">
            <svg width={size} height={size} className="transform -rotate-90">
              {/* Background ring */}
              <circle
                cx={size / 2}
                cy={size / 2}
                r={radius}
                fill="transparent"
                stroke="#F1F5F9"
                strokeWidth={strokeWidth}
              />

              {/* Slices */}
              {plans.map((p, idx) => {
                const pct = p.count / sumTotal;
                const strokeDasharray = `${pct * circumference} ${circumference}`;
                const strokeDashoffset = -accumulatedPercent * circumference;
                accumulatedPercent += pct;

                return (
                  <circle
                    key={idx}
                    cx={size / 2}
                    cy={size / 2}
                    r={radius}
                    fill="transparent"
                    stroke={p.color}
                    strokeWidth={strokeWidth}
                    strokeDasharray={strokeDasharray}
                    strokeDashoffset={strokeDashoffset}
                    strokeLinecap="round"
                    className="transition-all duration-500 hover:opacity-80"
                  />
                );
              })}
            </svg>

            {/* Inner Center Label */}
            <div className="absolute inset-0 flex flex-col items-center justify-center text-center">
              <span className="text-xl font-black text-slate-900 font-mono">{sumTotal}</span>
              <span className="text-[10px] text-slate-400 font-medium">ترخيص نشط</span>
            </div>
          </div>

          {/* Legend Items */}
          <div className="flex-1 space-y-2.5 w-full">
            {plans.map((p, idx) => {
              const pct = Math.round((p.count / sumTotal) * 100);

              return (
                <div key={idx} className="flex items-center justify-between text-xs">
                  <div className="flex items-center gap-2">
                    <span className="w-2.5 h-2.5 rounded-full shrink-0" style={{ backgroundColor: p.color }} />
                    <span className="font-semibold text-slate-700 text-[11px]">{p.label}</span>
                  </div>
                  <div className="flex items-center gap-2">
                    <span className="font-mono font-bold text-slate-900">{p.count}</span>
                    <span className={`text-[10px] font-bold px-1.5 py-0.2 rounded-md ${p.bgCol} ${p.textCol}`}>
                      {pct}%
                    </span>
                  </div>
                </div>
              );
            })}
          </div>

        </div>
      </div>

      <div className="pt-3 border-t border-slate-100 text-[11px] text-slate-500 flex items-center justify-between mt-2">
        <span>الأكثر اشتراكاً: <strong>الباقة السنوية (Yearly)</strong></span>
        <span className="text-blue-600 font-semibold font-mono">تجديد آلي</span>
      </div>
    </div>
  );
}
