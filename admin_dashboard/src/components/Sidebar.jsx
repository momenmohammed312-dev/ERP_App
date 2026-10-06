import React from 'react';
import { 
  KeyRound, LayoutDashboard, Laptop, Layers, 
  History, Settings, X, ShieldCheck, CheckCircle2 
} from 'lucide-react';

export default function Sidebar({ 
  currentTab, 
  setCurrentTab, 
  isOpen, 
  setIsOpen, 
  licenseCount, 
  deviceCount 
}) {
  const navItems = [
    {
      id: 'licenses',
      label: 'إدارة التراخيص والعملاء',
      icon: KeyRound,
      badge: licenseCount,
      badgeColor: 'bg-blue-50 text-blue-700 border border-blue-200',
    },
    {
      id: 'overview',
      label: 'المؤشرات والتحليلات',
      icon: LayoutDashboard,
    },
    {
      id: 'devices',
      label: 'الأجهزة والاتصالات المعتمدة',
      icon: Laptop,
      badge: deviceCount,
      badgeColor: 'bg-slate-100 text-slate-700 border border-slate-200',
    },
    {
      id: 'modules',
      label: 'كتالوج الموديولات (14 ميزة)',
      icon: Layers,
    },
    {
      id: 'audit',
      label: 'سجل العمليات والتدقيق',
      icon: History,
    },
    {
      id: 'settings',
      label: 'إعدادات الربط السحابي',
      icon: Settings,
    },
  ];

  return (
    <>
      {/* Mobile Backdrop */}
      {isOpen && (
        <div 
          onClick={() => setIsOpen(false)}
          className="fixed inset-0 z-40 bg-slate-900/40 backdrop-blur-sm lg:hidden transition-opacity"
        />
      )}

      {/* Sidebar Container */}
      <aside className={`
        fixed top-0 right-0 z-50 h-screen w-72 
        bg-white border-l border-slate-200
        shadow-sm lg:shadow-none 
        transition-transform duration-300 ease-in-out flex flex-col justify-between
        ${isOpen ? 'translate-x-0' : 'translate-x-full lg:translate-x-0'}
      `}>
        
        {/* Top Branding Section */}
        <div>
          <div className="h-20 px-6 flex items-center justify-between border-b border-slate-100">
            <div className="flex items-center gap-3">
              {/* Madar Official Logo */}
              <div className="w-11 h-11 rounded-xl bg-slate-50 border border-slate-200/80 p-1.5 flex items-center justify-center shadow-xs">
                <img 
                  src="/madar_logo.png" 
                  alt="شعار مدار ERP" 
                  className="w-full h-full object-contain"
                  onError={(e) => {
                    e.target.style.display = 'none';
                  }}
                />
              </div>

              <div>
                <div className="flex items-center gap-1.5">
                  <span className="font-extrabold text-base tracking-tight text-slate-900">
                    مِدار ERP
                  </span>
                  <span className="text-[10px] font-bold px-1.5 py-0.5 rounded bg-amber-50 text-amber-800 border border-amber-200">
                    Cloud
                  </span>
                </div>
                <p className="text-[11px] text-slate-500 font-medium">
                  منظومة إدارة التراخيص والموديولات
                </p>
              </div>
            </div>

            {/* Close Button on mobile */}
            <button
              onClick={() => setIsOpen(false)}
              className="lg:hidden p-1.5 rounded-lg text-slate-400 hover:text-slate-600 hover:bg-slate-100"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Nav Items */}
          <div className="px-3.5 py-5 space-y-1">
            <div className="px-3 mb-2 text-[11px] font-bold uppercase tracking-wider text-slate-400">
              القوائم الرئيسية
            </div>

            {navItems.map((item) => {
              const Icon = item.icon;
              const isActive = currentTab === item.id;

              return (
                <button
                  key={item.id}
                  onClick={() => {
                    setCurrentTab(item.id);
                    setIsOpen(false);
                  }}
                  className={`
                    w-full flex items-center justify-between px-3.5 py-2.5 rounded-xl text-xs font-semibold transition-all
                    ${isActive 
                      ? 'bg-blue-600 text-white shadow-sm shadow-blue-500/20' 
                      : 'text-slate-600 hover:bg-slate-50 hover:text-slate-900'}
                  `}
                >
                  <div className="flex items-center gap-3">
                    <Icon className={`w-4 h-4 ${isActive ? 'text-white' : 'text-slate-400'}`} />
                    <span>{item.label}</span>
                  </div>

                  {item.badge !== undefined && (
                    <span className={`text-[11px] px-2 py-0.5 rounded-full font-bold ${isActive ? 'bg-white/20 text-white' : item.badgeColor}`}>
                      {item.badge}
                    </span>
                  )}
                </button>
              );
            })}
          </div>
        </div>

        {/* Bottom System Status */}
        <div className="p-4 border-t border-slate-100 space-y-2.5">
          <div className="p-3 rounded-xl bg-slate-50 border border-slate-200/70 text-xs flex items-center gap-2.5">
            <span className="relative flex h-2 w-2">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
              <span className="relative inline-flex rounded-full h-2 w-2 bg-emerald-500"></span>
            </span>
            <div className="text-[11px] text-slate-600 leading-tight">
              <strong>محرك RS256 نشط:</strong> تشغيل أوفلاين 30 يوماً
            </div>
          </div>

          <div className="text-center text-[11px] text-slate-400">
            مِدار ERP — نظام التراخيص الذكي 2026
          </div>
        </div>

      </aside>
    </>
  );
}
