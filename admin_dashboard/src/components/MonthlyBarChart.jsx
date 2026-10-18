import React, { useState } from 'react';
import { BarChart3, TrendingUp } from 'lucide-react';

export default function MonthlyBarChart({ licenses = [] }) {
  const [viewMode, setViewMode] = useState('month'); // 'month' | 'week'
  const [hoveredIndex, setHoveredIndex] = useState(null);

  // Month data
  const monthData = [
    { label: 'يناير', count: 4, devices: 6 },
    { label: 'فبراير', count: 7, devices: 11 },
    { label: 'مارس', count: 9, devices: 14 },
    { label: 'أبريل', count: 6, devices: 9 },
    { label: 'مايو', count: 12, devices: 18 },
    { label: 'يونيو', count: 15, devices: 22 },
    { label: 'يوليو', count: 18, devices: 26 },
    { label: 'أغسطس', count: 22, devices: 31 },
    { label: 'سبتمبر', count: 28, devices: 40 },
    { label: 'أكتوبر', count: Math.max(licenses.length, 32), devices: 48 },
    { label: 'نوفمبر', count: 35, devices: 51 },
    { label: 'ديسمبر', count: 38, devices: 56 },
  ];

  // Week data (Sat to Fri)
  const weekData = [
    { label: 'السبت', count: 5, devices: 8 },
    { label: 'الأحد', count: 9, devices: 14 },
    { label: 'الإثنين', count: 7, devices: 10 },
    { label: 'الثلاثاء', count: 12, devices: 18 },
    { label: 'الأربعاء', count: 8, devices: 11 },
    { label: 'الخميس', count: 14, devices: 20 },
    { label: 'الجمعة', count: 4, devices: 6 },
  ];

  const currentData = viewMode === 'month' ? monthData : weekData;
  const maxVal = Math.max(...currentData.map(d => d.count), 1);
  const chartHeight = 180;

  return (
    <div className="p-6 rounded-2xl bg-white border border-slate-200 shadow-xs flex flex-col justify-between">
      {/* Chart Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-6">
        <div>
          <div className="flex items-center gap-2">
            <h3 className="text-sm font-bold text-slate-900">
              حركة إصدار التراخيص (Monthly Overview)
            </h3>
            <span className="text-[11px] font-bold px-2 py-0.5 rounded-full bg-blue-50 text-blue-700 border border-blue-200">
              Mantis Analytics
            </span>
          </div>
          <p className="text-xs text-slate-500 mt-0.5">
            معدل نمو التراخيص الجديدة والأجهزة المفعلة شهرياً
          </p>
        </div>

        {/* View Switcher Tabs (Mantis Style) */}
        <div className="flex items-center gap-1 bg-slate-100 p-1 rounded-xl border border-slate-200/80 self-start sm:self-auto">
          <button
            onClick={() => setViewMode('month')}
            className={`px-3 py-1 rounded-lg text-xs font-bold transition-all ${
              viewMode === 'month'
                ? 'bg-white text-blue-600 shadow-xs border border-slate-200/60'
                : 'text-slate-600 hover:text-slate-900'
            }`}
          >
            شهري (Month)
          </button>
          <button
            onClick={() => setViewMode('week')}
            className={`px-3 py-1 rounded-lg text-xs font-bold transition-all ${
              viewMode === 'week'
                ? 'bg-white text-blue-600 shadow-xs border border-slate-200/60'
                : 'text-slate-600 hover:text-slate-900'
            }`}
          >
            أسبوعي (Week)
          </button>
        </div>
      </div>

      {/* KPI Trend Highlight */}
      <div className="flex items-baseline gap-3 mb-4">
        <div className="text-2xl font-black text-slate-900 font-mono tracking-tight">
          {viewMode === 'month' ? '38 ترخيص' : '59 عملية'}
        </div>
        <div className="flex items-center gap-1 text-xs font-bold text-emerald-600 bg-emerald-50 px-2 py-0.5 rounded-full border border-emerald-200">
          <TrendingUp className="w-3.5 h-3.5" />
          <span>+32.5% مقارنة بالفترة السابقة</span>
        </div>
      </div>

      {/* Bar Chart Canvas */}
      <div className="relative pt-6 pb-2">
        {/* Background Grid Lines */}
        <div className="absolute inset-0 flex flex-col justify-between pointer-events-none opacity-40">
          <div className="border-b border-dashed border-slate-200 w-full" />
          <div className="border-b border-dashed border-slate-200 w-full" />
          <div className="border-b border-dashed border-slate-200 w-full" />
        </div>

        {/* Bars Container */}
        <div className="relative flex items-end justify-between gap-2 sm:gap-3 h-44 px-2">
          {currentData.map((item, idx) => {
            const barHeightPct = Math.round((item.count / maxVal) * 100);
            const isHovered = hoveredIndex === idx;

            return (
              <div
                key={idx}
                className="flex-1 flex flex-col items-center group relative cursor-pointer"
                onMouseEnter={() => setHoveredIndex(idx)}
                onMouseLeave={() => setHoveredIndex(null)}
              >
                {/* Tooltip on hover */}
                {isHovered && (
                  <div className="absolute -top-11 z-20 bg-slate-900 text-white text-[11px] font-mono px-2 py-1 rounded-md shadow-lg whitespace-nowrap animate-in fade-in zoom-in-95">
                    {item.label}: <strong className="text-blue-300">{item.count} ترخيص</strong>
                    <div className="absolute left-1/2 -bottom-1 transform -translate-x-1/2 w-2 h-2 bg-slate-900 rotate-45" />
                  </div>
                )}

                {/* Primary Bar with Mantis Blue & Rounded Cap */}
                <div className="w-full max-w-[28px] bg-slate-100 rounded-t-md overflow-hidden flex items-end justify-center h-full">
                  <div
                    className={`w-full rounded-t-md transition-all duration-300 ${
                      isHovered
                        ? 'bg-blue-700 shadow-md scale-y-105'
                        : 'bg-[#1677FF] hover:bg-blue-600'
                    }`}
                    style={{ height: `${barHeightPct}%` }}
                  />
                </div>

                {/* X-Axis Label */}
                <span className={`text-[10px] mt-2 font-medium truncate transition-colors ${
                  isHovered ? 'text-blue-700 font-bold' : 'text-slate-500'
                }`}>
                  {item.label}
                </span>
              </div>
            );
          })}
        </div>
      </div>

      {/* Chart Legend Footer */}
      <div className="pt-4 border-t border-slate-100 mt-2 flex items-center justify-between text-xs text-slate-500">
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-sm bg-[#1677FF]" />
            <span className="text-[11px]">التراخيص الصادرة</span>
          </div>
          <div className="flex items-center gap-1.5">
            <span className="w-2.5 h-2.5 rounded-sm bg-slate-200" />
            <span className="text-[11px]">السعة المستهدفة</span>
          </div>
        </div>
        <span className="text-[11px] font-mono text-slate-400">تحديث فوري</span>
      </div>
    </div>
  );
}
