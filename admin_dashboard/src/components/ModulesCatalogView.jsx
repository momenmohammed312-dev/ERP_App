import React from 'react';
import { 
  Layers, CheckCircle2, ShieldCheck, Sparkles, 
  Users, Factory, DollarSign, AlertOctagon, 
  GitBranch, QrCode, CreditCard, ChevronLeft 
} from 'lucide-react';
import { ERP_MODULES } from '../config/modules';

export default function ModulesCatalogView({ licenses, onSelectModuleFilter }) {
  // Count how many licenses have each module
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
      <div className="p-6 rounded-2xl bg-gradient-to-r from-indigo-900/40 via-purple-900/20 to-sky-900/20 border border-indigo-500/20 dark:border-white/5">
        <div className="flex items-center gap-3 mb-2">
          <div className="p-2.5 rounded-xl bg-indigo-600 text-white shadow-md shadow-indigo-600/30">
            <Layers className="w-5 h-5" />
          </div>
          <div>
            <h2 className="text-lg font-bold text-slate-900 dark:text-white">
              كتالوج موديولات نظام ERP & POS
            </h2>
            <p className="text-xs text-slate-500 dark:text-gray-400">
              استعراض كافة الوحدات المتاحة ونسبة تفعيلها لدى العملاء المسجلين
            </p>
          </div>
        </div>
      </div>

      {/* Core Modules Grid */}
      <div>
        <div className="flex items-center gap-2 mb-3">
          <ShieldCheck className="w-4 h-4 text-indigo-600 dark:text-indigo-400" />
          <h3 className="text-sm font-bold text-slate-800 dark:text-gray-200 uppercase tracking-wider">
            الوحدات الأساسية لنظام نقاط البيع (Core Modules)
          </h3>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {coreModules.map(mod => (
            <div
              key={mod.id}
              className="p-5 rounded-2xl bg-white dark:bg-[#111827] border border-slate-200/80 dark:border-white/5 shadow-sm hover:border-indigo-500/40 transition-all flex flex-col justify-between"
            >
              <div>
                <div className="flex items-center justify-between mb-2">
                  <span className="text-xs font-bold text-slate-900 dark:text-white">
                    {mod.name}
                  </span>
                  <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-indigo-50 text-indigo-700 dark:bg-indigo-500/10 dark:text-indigo-300 border border-indigo-200 dark:border-indigo-500/20">
                    أساسي
                  </span>
                </div>
                <p className="text-xs text-slate-500 dark:text-gray-400 leading-relaxed mb-4">
                  {mod.description}
                </p>
              </div>

              <div className="pt-3 border-t border-slate-100 dark:border-white/5 flex items-center justify-between text-xs">
                <span className="text-slate-500 dark:text-gray-400">
                  مفعل لدى: <strong className="text-slate-900 dark:text-white font-mono">{mod.activeClientsCount}</strong> عميل
                </span>
                <span className="text-[11px] font-mono text-indigo-600 dark:text-indigo-400">
                  {mod.id}
                </span>
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Addon Modules Grid */}
      <div className="pt-4">
        <div className="flex items-center gap-2 mb-3">
          <Sparkles className="w-4 h-4 text-purple-600 dark:text-purple-400" />
          <h3 className="text-sm font-bold text-slate-800 dark:text-gray-200 uppercase tracking-wider">
            الوحدات الإضافية والمتقدمة (Addons Modules)
          </h3>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {addonModules.map(mod => (
            <div
              key={mod.id}
              className="p-5 rounded-2xl bg-white dark:bg-[#111827] border border-purple-200/60 dark:border-purple-500/20 shadow-sm hover:border-purple-500/50 transition-all flex flex-col justify-between"
            >
              <div>
                <div className="flex items-center justify-between mb-2">
                  <span className="text-xs font-bold text-slate-900 dark:text-white">
                    {mod.name}
                  </span>
                  <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-purple-50 text-purple-700 dark:bg-purple-500/10 dark:text-purple-300 border border-purple-200 dark:border-purple-500/20">
                    ميزة إضافية
                  </span>
                </div>
                <p className="text-xs text-slate-500 dark:text-gray-400 leading-relaxed mb-4">
                  {mod.description}
                </p>
              </div>

              <div className="pt-3 border-t border-slate-100 dark:border-white/5 flex items-center justify-between text-xs">
                <span className="text-slate-500 dark:text-gray-400">
                  مفعل لدى: <strong className="text-purple-700 dark:text-purple-300 font-mono">{mod.activeClientsCount}</strong> عميل
                </span>
                <span className="text-[11px] font-mono text-purple-600 dark:text-purple-400">
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
