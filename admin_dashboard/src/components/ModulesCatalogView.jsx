import React from 'react';
import { Layers, ShieldCheck, Sparkles } from 'lucide-react';
import { ERP_MODULES } from '../config/modules';

export default function ModulesCatalogView({ licenses }) {
  const moduleUsage = ERP_MODULES.map(mod => {
    const activeClientsCount = licenses.filter(lic => 
      lic.status === 'active' && (lic.features || []).includes(mod.id)
    ).length;
    return {
      ...mod,
      activeClientsCount,
    };
  });

  const coreModules = moduleUsage.filter(m => m.category === 'core');
  const addonModules = moduleUsage.filter(m => m.category === 'addon');

  return (
    <div className="space-y-6">
      
      {/* Header Info */}
      <div className="p-6 rounded-2xl bg-white border border-slate-200/90 shadow-xs flex items-center gap-4">
        <div className="p-3 rounded-xl bg-blue-50 text-blue-600 border border-blue-200/60">
          <Layers className="w-6 h-6" />
        </div>
        <div>
          <h2 className="text-base font-extrabold text-slate-900">
            كتالوج موديولات منظومة مِدار ERP (14 موديول)
          </h2>
          <p className="text-xs text-slate-500 mt-0.5">
            عرض شامل لكافة الوحدات والخصائص وإحصائيات تفعيلها لدى العملاء
          </p>
        </div>
      </div>

      {/* Core Modules Grid */}
      <div>
        <div className="flex items-center gap-2 mb-3">
          <ShieldCheck className="w-4 h-4 text-blue-600" />
          <h3 className="text-xs font-bold text-slate-700 uppercase tracking-wider">
            الوحدات الأساسية (Core Modules)
          </h3>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {coreModules.map(mod => (
            <div
              key={mod.id}
              className="p-5 rounded-2xl bg-white border border-slate-200/90 shadow-xs hover:border-blue-300 transition-all flex flex-col justify-between"
            >
              <div>
                <div className="flex items-center justify-between mb-2">
                  <span className="text-xs font-bold text-slate-900">
                    {mod.name}
                  </span>
                  <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-blue-50 text-blue-700 border border-blue-200">
                    أساسي
                  </span>
                </div>
                <p className="text-xs text-slate-500 leading-relaxed mb-4">
                  {mod.description}
                </p>
              </div>

              <div className="pt-3 border-t border-slate-100 flex items-center justify-between text-xs">
                <span className="text-slate-500">
                  مفعل لدى: <strong className="text-slate-900 font-mono">{mod.activeClientsCount}</strong> عميل
                </span>
                <span className="text-[11px] font-mono text-blue-600 font-bold">
                  {mod.id}
                </span>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Addon Modules Grid */}
      <div className="pt-2">
        <div className="flex items-center gap-2 mb-3">
          <Sparkles className="w-4 h-4 text-purple-600" />
          <h3 className="text-xs font-bold text-slate-700 uppercase tracking-wider">
            الوحدات الإضافية والمتقدمة (Addons)
          </h3>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {addonModules.map(mod => (
            <div
              key={mod.id}
              className="p-5 rounded-2xl bg-white border border-purple-200/70 shadow-xs hover:border-purple-300 transition-all flex flex-col justify-between"
            >
              <div>
                <div className="flex items-center justify-between mb-2">
                  <span className="text-xs font-bold text-slate-900">
                    {mod.name}
                  </span>
                  <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-purple-50 text-purple-700 border border-purple-200">
                    ميزة إضافية
                  </span>
                </div>
                <p className="text-xs text-slate-500 leading-relaxed mb-4">
                  {mod.description}
                </p>
              </div>

              <div className="pt-3 border-t border-slate-100 flex items-center justify-between text-xs">
                <span className="text-slate-500">
                  مفعل لدى: <strong className="text-purple-700 font-mono font-bold">{mod.activeClientsCount}</strong> عميل
                </span>
                <span className="text-[11px] font-mono text-purple-600 font-bold">
                  {mod.id}
                </span>
              </div>
            </div>
          ))}
        </div>
      </div>

    </div>
  );
}
