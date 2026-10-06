import React from 'react';
import { 
  LayoutDashboard, KeyRound, Laptop, Layers, 
  History, Settings, ShieldCheck, X, Sparkles, 
  ExternalLink, Moon, Sun, ChevronRight, ChevronLeft
} from 'lucide-react';

export default function Sidebar({ 
  currentTab, 
  setCurrentTab, 
  isOpen, 
  setIsOpen, 
  theme, 
  toggleTheme,
  licenseCount,
  deviceCount
}) {
  const navItems = [
    {
      id: 'licenses',
      label: 'إدارة التراخيص',
      icon: KeyRound,
      badge: licenseCount,
      badgeColor: 'bg-indigo-500/10 text-indigo-500 dark:text-indigo-400 border border-indigo-500/20',
    },
    {
      id: 'overview',
      label: 'لوحة المؤشرات والإحصائيات',
      icon: LayoutDashboard,
    },
    {
      id: 'devices',
      label: 'الأجهزة والاتصالات',
      icon: Laptop,
      badge: deviceCount,
      badgeColor: 'bg-blue-500/10 text-blue-500 dark:text-blue-400 border border-blue-500/20',
    },
    {
      id: 'modules',
      label: 'كتالوج الموديولات والميزات',
      icon: Layers,
    },
    {
      id: 'audit',
      label: 'سجل العمليات والتدقيق',
      icon: History,
    },
    {
      id: 'settings',
      label: 'الإعدادات وقاعدة البيانات',
      icon: Settings,
    },
  ];

  return (
    <>
      {/* Mobile Backdrop Overlay */}
      {isOpen && (
        <div 
          onClick={() => setIsOpen(false)}
          className="fixed inset-0 z-40 bg-black/60 backdrop-blur-sm lg:hidden transition-opacity"
        />
      )}

      {/* Sidebar Container */}
      <aside className={`
        fixed top-0 right-0 z-50 h-screen w-72 
        bg-white dark:bg-[#0E131F] 
        border-l border-slate-200 dark:border-white/5 
        shadow-xl lg:shadow-none 
        transition-transform duration-300 ease-in-out flex flex-col justify-between
        ${isOpen ? 'translate-x-0' : 'translate-x-full lg:translate-x-0'}
      `}>
        
        {/* Sidebar Header */}
        <div>
          <div className="h-20 px-6 flex items-center justify-between border-b border-slate-100 dark:border-white/5">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl bg-gradient-to-tr from-indigo-600 via-indigo-500 to-sky-500 flex items-center justify-center shadow-md shadow-indigo-500/20 text-white">
                <KeyRound className="w-5 h-5" />
              </div>
              <div>
                <div className="flex items-center gap-1.5">
                  <span className="font-bold text-base tracking-tight text-slate-900 dark:text-white">
                    POS Cloud
                  </span>
                  <span className="text-[10px] font-bold px-1.5 py-0.5 rounded bg-indigo-50 text-indigo-600 dark:bg-indigo-500/10 dark:text-indigo-400 border border-indigo-200 dark:border-indigo-500/20">
                    Mantis M3
                  </span>
                </div>
                <p className="text-[11px] text-slate-500 dark:text-gray-400">
                  لوحة إدارة التراخيص والموديولات
                </p>
              </div>
            </div>

            {/* Mobile Close Button */}
            <button
              onClick={() => setIsOpen(false)}
              className="lg:hidden p-2 rounded-lg text-slate-400 hover:text-slate-600 dark:hover:text-white hover:bg-slate-100 dark:hover:bg-white/5"
            >
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* Navigation Items */}
          <div className="px-4 py-6 space-y-1.5">
            <div className="px-3 mb-2 text-[11px] font-bold uppercase tracking-wider text-slate-400 dark:text-gray-500">
              القائمة الرئيسية
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
                    w-full flex items-center justify-between px-3.5 py-2.5 rounded-xl text-sm font-medium transition-all
                    ${isActive 
                      ? 'bg-indigo-600 text-white shadow-md shadow-indigo-600/25 font-semibold' 
                      : 'text-slate-600 dark:text-gray-300 hover:bg-slate-100 dark:hover:bg-white/5 hover:text-slate-900 dark:hover:text-white'}
                  `}
                >
                  <div className="flex items-center gap-3">
                    <Icon className={`w-4 h-4 ${isActive ? 'text-white' : 'text-slate-400 dark:text-gray-400'}`} />
                    <span>{item.label}</span>
                  </div>

                  {item.badge !== undefined && (
                    <span className={`text-xs px-2 py-0.5 rounded-full font-semibold ${isActive ? 'bg-white/20 text-white' : item.badgeColor}`}>
                      {item.badge}
                    </span>
                  )}
                </button>
              );
            })}
          </div>
        </div>

        {/* Sidebar Footer */}
        <div className="p-4 border-t border-slate-100 dark:border-white/5 space-y-3">
          
          {/* Theme Switcher Toggle */}
          <div className="flex items-center justify-between p-2 rounded-xl bg-slate-50 dark:bg-white/[0.03] border border-slate-200/60 dark:border-white/5">
            <span className="text-xs font-medium text-slate-600 dark:text-gray-300 flex items-center gap-2">
              {theme === 'dark' ? <Moon className="w-3.5 h-3.5 text-indigo-400" /> : <Sun className="w-3.5 h-3.5 text-amber-500" />}
              <span>{theme === 'dark' ? 'الوضع الليلي (Dark)' : 'الوضع النهاري (Light)'}</span>
            </span>

            <button
              onClick={toggleTheme}
              className="p-1.5 rounded-lg bg-white dark:bg-slate-800 shadow-sm border border-slate-200 dark:border-white/10 text-slate-700 dark:text-gray-200 hover:scale-105 transition-transform"
              title="تبديل المظهر"
            >
              {theme === 'dark' ? <Sun className="w-4 h-4 text-amber-400" /> : <Moon className="w-4 h-4 text-indigo-600" />}
            </button>
          </div>

          {/* Quick System Badge */}
          <div className="p-3 rounded-xl bg-emerald-500/5 dark:bg-emerald-500/10 border border-emerald-500/20 text-xs text-emerald-700 dark:text-emerald-400 flex items-center gap-2.5">
            <span className="relative flex h-2 w-2">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
              <span className="relative inline-flex rounded-full h-2 w-2 bg-emerald-500"></span>
            </span>
            <span className="text-[11px] font-medium leading-tight">
              محرك التحقق RS256 أوفلاين نشط
            </span>
          </div>

        </div>

      </aside>
    </>
  );
}
