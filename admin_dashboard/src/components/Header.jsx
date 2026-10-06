import React from 'react';
import { KeyRound, Server, Settings, RefreshCw, Plus, Sparkles } from 'lucide-react';

export default function Header({ config, onOpenConfig, onOpenCreate, onRefresh, loading }) {
  const isSupabase = config.mode === 'supabase';

  return (
    <header className="sticky top-0 z-30 border-b border-white/5 bg-[#0B0F19]/80 backdrop-blur-xl">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-20 flex items-center justify-between">
        
        {/* Logo and Brand */}
        <div className="flex items-center gap-4">
          <div className="relative flex items-center justify-center w-12 h-12 rounded-2xl bg-gradient-to-tr from-indigo-600 via-indigo-500 to-purple-500 shadow-lg shadow-indigo-500/25">
            <KeyRound className="w-6 h-6 text-white" />
            <span className="absolute -top-1 -right-1 flex h-3.5 w-3.5">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
              <span className="relative inline-flex rounded-full h-3.5 w-3.5 bg-emerald-500 border-2 border-[#0B0F19]"></span>
            </span>
          </div>

          <div>
            <div className="flex items-center gap-2">
              <h1 className="text-xl font-bold tracking-tight text-white">
                لوحة تحكم تراخيص POS
              </h1>
              <span className="inline-flex items-center gap-1 px-2.5 py-0.5 rounded-full text-xs font-semibold bg-indigo-500/10 text-indigo-400 border border-indigo-500/20">
                <Sparkles className="w-3 h-3" /> v2.0
              </span>
            </div>
            <p className="text-xs text-gray-400">
              إدارة المفاتيح، الأجهزة والوحدات الموديلية سحابياً
            </p>
          </div>
        </div>

        {/* Status and Action Buttons */}
        <div className="flex items-center gap-3">
          {/* Connection Status Badge */}
          <button
            onClick={onOpenConfig}
            className="hidden md:flex items-center gap-2.5 px-3.5 py-2 rounded-xl bg-surface-panel/60 border border-white/5 hover:border-white/10 transition-all text-xs"
          >
            <div className={`w-2 h-2 rounded-full ${isSupabase ? 'bg-emerald-400 shadow-[0_0_8px_#34d399]' : 'bg-blue-400 shadow-[0_0_8px_#60a5fa]'}`} />
            <span className="text-gray-300">
              {isSupabase ? 'Supabase متصل' : 'المحاكي المحلي (Simulator)'}
            </span>
            <span className="text-[10px] text-gray-500 bg-black/30 px-1.5 py-0.5 rounded">
              تغيير
            </span>
          </button>

          {/* Refresh Button */}
          <button
            onClick={onRefresh}
            disabled={loading}
            className="p-2.5 rounded-xl bg-surface-panel/60 border border-white/5 hover:border-white/10 hover:bg-surface-hover text-gray-300 transition-all disabled:opacity-50"
            title="تحديث البيانات"
          >
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin text-indigo-400' : ''}`} />
          </button>

          {/* Settings Button */}
          <button
            onClick={onOpenConfig}
            className="p-2.5 rounded-xl bg-surface-panel/60 border border-white/5 hover:border-white/10 hover:bg-surface-hover text-gray-300 transition-all"
            title="إعدادات الربط و Supabase"
          >
            <Settings className="w-4 h-4" />
          </button>

          {/* Create License CTA Button */}
          <button
            onClick={onOpenCreate}
            className="flex items-center gap-2 px-4 py-2.5 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-white font-medium text-sm shadow-lg shadow-indigo-600/30 transition-all active:scale-[0.98]"
          >
            <Plus className="w-4 h-4" />
            <span>إنشاء ترخيص جديد</span>
          </button>
        </div>

      </div>
    </header>
  );
}
