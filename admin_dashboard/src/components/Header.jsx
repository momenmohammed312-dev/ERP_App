import React from 'react';
import { Menu, Search, Plus, RefreshCw, Settings, ShieldCheck } from 'lucide-react';

export default function Header({ 
  onToggleSidebar, 
  config, 
  onOpenConfig, 
  onOpenCreate, 
  onRefresh, 
  loading,
  searchQuery,
  setSearchQuery
}) {
  const isSupabase = config.mode === 'supabase';

  return (
    <header className="sticky top-0 z-30 h-20 px-4 sm:px-6 lg:px-8 border-b border-slate-200/80 bg-white/95 backdrop-blur-md">
      <div className="h-full flex items-center justify-between gap-4">
        
        {/* Left Side: Mobile Menu Button + Search */}
        <div className="flex items-center gap-3 flex-1 max-w-lg">
          <button
            onClick={onToggleSidebar}
            className="lg:hidden p-2 rounded-xl border border-slate-200 text-slate-600 hover:bg-slate-50 transition-colors"
            title="فتح القائمة"
          >
            <Menu className="w-5 h-5" />
          </button>

          {/* Mantis Search Box */}
          <div className="relative w-full max-w-md hidden sm:block">
            <Search className="w-4 h-4 text-slate-400 absolute right-3.5 top-1/2 -translate-y-1/2" />
            <input
              type="text"
              placeholder="بحث بالعميل، الهاتف، كود الترخيص..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="w-full pr-10 pl-4 py-2 rounded-xl bg-slate-50 border border-slate-200 text-xs text-slate-900 placeholder-slate-400 focus:outline-none focus:border-blue-500 focus:bg-white transition-all"
            />
          </div>
        </div>

        {/* Right Side: Status Chip, Refresh, Config, Create CTA */}
        <div className="flex items-center gap-2 sm:gap-3">
          
          {/* Connection Chip */}
          <button
            onClick={onOpenConfig}
            className="hidden sm:flex items-center gap-2 px-3 py-1.5 rounded-xl bg-slate-50 border border-slate-200 hover:border-slate-300 text-xs transition-colors"
            title="تغيير إعدادات الاتصال"
          >
            <span className={`w-2 h-2 rounded-full ${isSupabase ? 'bg-emerald-500' : 'bg-blue-500'}`} />
            <span className="font-semibold text-slate-700">
              {isSupabase ? 'Supabase السحابي' : 'المحاكي المحلي (Simulator)'}
            </span>
          </button>

          {/* Refresh Data */}
          <button
            onClick={onRefresh}
            disabled={loading}
            className="p-2.5 rounded-xl border border-slate-200 text-slate-600 hover:bg-slate-50 hover:text-slate-900 transition-colors disabled:opacity-50"
            title="تحديث البيانات"
          >
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin text-blue-600' : ''}`} />
          </button>

          {/* Database Config */}
          <button
            onClick={onOpenConfig}
            className="p-2.5 rounded-xl border border-slate-200 text-slate-600 hover:bg-slate-50 hover:text-slate-900 transition-colors"
            title="إعدادات قاعدة البيانات والربط"
          >
            <Settings className="w-4 h-4" />
          </button>

          {/* Create License CTA */}
          <button
            onClick={onOpenCreate}
            className="flex items-center gap-2 px-4 py-2 rounded-xl bg-blue-600 hover:bg-blue-500 text-white font-bold text-xs shadow-xs transition-all active:scale-[0.98]"
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
