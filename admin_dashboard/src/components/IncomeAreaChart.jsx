import React, { useState } from 'react';
import { Activity, ShieldCheck, Laptop } from 'lucide-react';

export default function IncomeAreaChart({ licenses = [] }) {
  const [metricType, setMetricType] = useState('all'); // 'all' | 'active'
  const [hoveredPoint, setHoveredPoint] = useState(null);

  // Growth curve points (10 time intervals)
  const dataPoints = [
    { label: 'أسبوع 1', total: 10, active: 8, devices: 12 },
    { label: 'أسبوع 2', total: 15, active: 14, devices: 19 },
    { label: 'أسبوع 3', total: 18, active: 16, devices: 25 },
    { label: 'أسبوع 4', total: 22, active: 20, devices: 31 },
    { label: 'أسبوع 5', total: 26, active: 24, devices: 38 },
    { label: 'أسبوع 6', total: 31, active: 29, devices: 44 },
    { label: 'أسبوع 7', total: 35, active: 32, devices: 49 },
    { label: 'أسبوع 8', total: Math.max(licenses.length, 38), active: 35, devices: 52 },
  ];

  const maxVal = 60;
  const width = 500;
  const height = 180;
  const paddingX = 20;
  const paddingY = 20;

  // Convert points to SVG coordinates
  const coords = dataPoints.map((d, i) => {
    const val = metricType === 'all' ? d.devices : d.active;
    const x = paddingX + (i / (dataPoints.length - 1)) * (width - 2 * paddingX);
    const y = height - paddingY - (val / maxVal) * (height - 2 * paddingY);
    return { ...d, x, y, val };
  });

  // Construct smooth bezier curve path
  const pathD = coords.reduce((acc, pt, i, arr) => {
    if (i === 0) return `M ${pt.x} ${pt.y}`;
    const prev = arr[i - 1];
    const cp1x = prev.x + (pt.x - prev.x) / 2;
    const cp1y = prev.y;
    const cp2x = prev.x + (pt.x - prev.x) / 2;
    const cp2y = pt.y;
    return `${acc} C ${cp1x} ${cp1y}, ${cp2x} ${cp2y}, ${pt.x} ${pt.y}`;
  }, '');

  // Fill area path (closed down to bottom)
  const lastX = coords[coords.length - 1].x;
  const firstX = coords[0].x;
  const areaD = `${pathD} L ${lastX} ${height} L ${firstX} ${height} Z`;

  return (
    <div className="p-6 rounded-2xl bg-white border border-slate-200 shadow-xs flex flex-col justify-between">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 mb-5">
        <div>
          <div className="flex items-center gap-2">
            <h3 className="text-sm font-bold text-slate-900">
              منحنى نمو الأجهزة والاتصال (Growth Trend)
            </h3>
            <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse" />
          </div>
          <p className="text-xs text-slate-500 mt-0.5">
            تطور حجم الأجهزة المرتبطة والاستهلاك الفعلي
          </p>
        </div>

        {/* Metric Selector Filter */}
        <div className="flex items-center gap-1 bg-slate-100 p-1 rounded-xl border border-slate-200/80 self-start sm:self-auto">
          <button
            onClick={() => setMetricType('all')}
            className={`px-3 py-1 rounded-lg text-xs font-bold transition-all ${
              metricType === 'all'
                ? 'bg-white text-blue-600 shadow-xs border border-slate-200/60'
                : 'text-slate-600 hover:text-slate-900'
            }`}
          >
            الأجهزة المرتبطة
          </button>
          <button
            onClick={() => setMetricType('active')}
            className={`px-3 py-1 rounded-lg text-xs font-bold transition-all ${
              metricType === 'active'
                ? 'bg-white text-blue-600 shadow-xs border border-slate-200/60'
                : 'text-slate-600 hover:text-slate-900'
            }`}
          >
            التراخيص النشطة
          </button>
        </div>
      </div>

      {/* Main KPI Stat */}
      <div className="flex items-baseline gap-3 mb-3">
        <div className="text-2xl font-black text-slate-900 font-mono tracking-tight">
          {metricType === 'all' ? '52 جهاز' : '35 ترخيص'}
        </div>
        <span className="text-xs font-bold text-blue-600 bg-blue-50 px-2 py-0.5 rounded-full border border-blue-200">
          معدل الربط 1.4 جهاز / ترخيص
        </span>
      </div>

      {/* Interactive SVG Spline Area Canvas */}
      <div className="relative w-full h-44">
        <svg
          viewBox={`0 0 ${width} ${height}`}
          className="w-full h-full overflow-visible"
          preserveAspectRatio="none"
        >
          <defs>
            <linearGradient id="mantisAreaGradient" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="#1677FF" stopOpacity="0.28" />
              <stop offset="85%" stopColor="#1677FF" stopOpacity="0.02" />
              <stop offset="100%" stopColor="#1677FF" stopOpacity="0" />
            </linearGradient>
          </defs>

          {/* Dotted Guide Lines */}
          <line x1={0} y1={height * 0.25} x2={width} y2={height * 0.25} stroke="#E2E8F0" strokeDasharray="3 3" />
          <line x1={0} y1={height * 0.55} x2={width} y2={height * 0.55} stroke="#E2E8F0" strokeDasharray="3 3" />
          <line x1={0} y1={height * 0.85} x2={width} y2={height * 0.85} stroke="#E2E8F0" strokeDasharray="3 3" />

          {/* Area Fill */}
          <path d={areaD} fill="url(#mantisAreaGradient)" />

          {/* Curve Spline Line */}
          <path
            d={pathD}
            fill="none"
            stroke="#1677FF"
            strokeWidth="2.75"
            strokeLinecap="round"
            strokeLinejoin="round"
          />

          {/* Interactive Points */}
          {coords.map((pt, i) => (
            <g
              key={i}
              className="cursor-pointer"
              onMouseEnter={() => setHoveredPoint(pt)}
              onMouseLeave={() => setHoveredPoint(null)}
            >
              <circle
                cx={pt.x}
                cy={pt.y}
                r={hoveredPoint?.label === pt.label ? "6" : "3.5"}
                fill="#FFFFFF"
                stroke="#1677FF"
                strokeWidth={hoveredPoint?.label === pt.label ? "3" : "2"}
                className="transition-all duration-200"
              />
            </g>
          ))}
        </svg>

        {/* Hover Floating Tooltip */}
        {hoveredPoint && (
          <div
            className="absolute z-30 pointer-events-none bg-slate-900 text-white text-[11px] font-mono px-2.5 py-1.5 rounded-lg shadow-xl"
            style={{
              left: `${(hoveredPoint.x / width) * 100}%`,
              top: `${(hoveredPoint.y / height) * 100 - 25}%`,
              transform: 'translate(-50%, -100%)'
            }}
          >
            <div className="font-bold text-slate-300">{hoveredPoint.label}</div>
            <div className="text-blue-300 font-extrabold">{hoveredPoint.val} {metricType === 'all' ? 'جهاز' : 'ترخيص'}</div>
          </div>
        )}
      </div>

      {/* Bottom X-Axis labels */}
      <div className="flex justify-between text-[10px] text-slate-400 mt-2 px-2 font-medium">
        {dataPoints.map((d, i) => (
          <span key={i}>{d.label}</span>
        ))}
      </div>
    </div>
  );
}
