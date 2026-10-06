import React from 'react';
import { 
  Menu, Search, Plus, RefreshCw, Settings, 
  Cloud, Server, Bell, Moon, Sun, ShieldCheck 
} from 'lucide-react';

export default function Header({ 
  onToggleSidebar, 
  config, 
  onOpenConfig, 
  onOpenCreate, 
  onRefresh, 
  loading,
  searchQuery,
  setSearchQuery,
  theme,
  toggleTheme,
  expiringCount = 0
}) {
  const isSupabase = config.mode === 'supabase';

  return (
    <header className="sticky top-0 z-30 h-20 px-4 sm:px-6 lg:px-8 border-b border-slate-200/80 dark:border-white/5 bg-white/80 dark:bg-[#0B0F19]/80 backdrop-blur-xl transition-colors">
      <div className="h-full flex items-center justify-between gap-4">
        
        {/* Left Side: Mobile Menu Button + Search */}
        <div className="flex items-center gap-3 flex-1 max-w-lg">
          <button
            onClick={onToggleSidebar}
            className="lg:hidden p-2.5 rounded-xl border border-slate-200 dark:border-white/10 text-slate-600 dark:text-gray-300 hover:bg-slate-100 dark:hover:bg-white/5 transition-colors"
            title="فتح القائمة"
          >
            <Menu className="w-5 h-5" />
          </button>

          {/* Search Input (Mantis Style) */}
          <div className="relative w-full max-w-md hidden sm:block">
            <Search className="w-4 h-4 text-slate-400 dark:text-gray-500 absolute right-3.5 top-1/2 -translate-y-1/2" />
            <input
              type="text"
              placeholder="بحث سريع برقم الهاتف، اسم العميل، أو مفتاح الترخيص..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full pr-10 pl-4 py-2 rounded-xl bg-slate-50 dark:bg-white/[0.04] border border-slate-200 dark:border-white/10 text-sm text-slate-900 dark:text-white placeholder-slate-400 dark:placeholder-gray-500 focus:outline-none focus:border-indigo-500 transition-colors"
            />
          </div>
        </div>

        {/* Right Side: Backend Status, Notifications, Theme, Create CTA */}
        <div className="flex items-center gap-2.5 sm:gap-3">
          
          {/* Connection Status Chip */}
          <button
            onClick={onOpenConfig}
            className="hidden md:flex items-center gap-2 px-3 py-1.5 rounded-xl bg-slate-50 dark:bg-white/[0.03] border border-slate-200/80 dark:border-white/10 hover:border-slate-300 text-xs transition-all"
            title="إعدادات الربط"
          >
            <span className={`w-2 h-2 rounded-full ${isSupabase ? 'bg-emerald-500 shadow-[0_0_8px_#10b981]' : 'bg-blue-500 shadow-[0_0_8px_#3b82f6]'}`} />
            <span className="font-medium text-slate-700 dark:text-gray-300">
              {isSupabase ? 'Supabase السحابي' : 'المحاكي المحلي'}
            </span>
          </button>

          {/* Theme Toggle Button */}
          <button
            onClick={toggleTheme}
            className="p-2.5 rounded-xl border border-slate-200 dark:border-white/10 text-slate-600 dark:text-gray-300 hover:bg-slate-100 dark:hover:bg-white/5 transition-colors"
            title="تبديل الوضع الليلي / النهاري"
          >
            {theme === 'dark' ? <Sun className="w-4 h-4 text-amber-400" /> : <Moon className="w-4 h-4 text-slate-600" />}
          </button>

          {/* Refresh Button */}
          <button
            onClick={onRefresh}
            disabled={loading}
            className="p-2.5 rounded-xl border border-slate-200 dark:border-white/10 text-slate-600 dark:text-gray-300 hover:bg-slate-100 dark:hover:bg-white/5 transition-colors disabled:opacity-50"
            title="تحديث البيانات"
          >
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin text-indigo-500' : ''}`} />
          </button>

          {/* Database / Settings */}
          <button
            onClick={onOpenConfig}
            className="p-2.5 rounded-xl border border-slate-200 dark:border-white/10 text-slate-600 dark:text-gray-300 hover:bg-slate-100 dark:hover:bg-white/5 transition-colors"
            title="إعدادات قاعدة البيانات"
          >
            <Settings className="w-4 h-4" />
          </button>

          {/* Create License CTA (Mantis / Material Tone) */}
          <button
            onClick={onOpenCreate}
            className="flex items-center gap-2 px-4 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-semibold text-xs sm:text-sm shadow-md shadow-indigo-600/25 transition-all active:scale-[0.98]"
          >
            <Plus className="w-4 h-4" />
            <span className="hidden sm:inline">إصدار ترخيص جديد</span>
            <span className="sm:hidden">ترخيص</span>
          </button>

        </div>

      </div>
    </header>
  );
}
