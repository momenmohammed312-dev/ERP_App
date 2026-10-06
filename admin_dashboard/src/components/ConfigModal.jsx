import React, { useState } from 'react';
import { X, Server, Cloud, Globe, ExternalLink, Save, CheckCircle, HelpCircle } from 'lucide-react';
import { api } from '../services/api';

export default function ConfigModal({ isOpen, onClose, onSaveConfig }) {
  const [config, setConfig] = useState(() => api.loadConfig());
  const [savedSuccess, setSavedSuccess] = useState(false);

  if (!isOpen) return null;

  const handleSubmit = (e) => {
    e.preventDefault();
    api.saveConfig(config);
    onSaveConfig(config);
    setSavedSuccess(true);
    setTimeout(() => {
      setSavedSuccess(false);
      onClose();
    }, 1200);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md">
      <div className="relative w-full max-w-xl rounded-3xl bg-[#111827] border border-white/10 shadow-2xl overflow-hidden">
        
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-5 border-b border-white/5 bg-white/[0.02]">
          <div className="flex items-center gap-3">
            <div className="p-2.5 rounded-xl bg-indigo-600/20 text-indigo-400 border border-indigo-500/20">
              <Server className="w-5 h-5" />
            </div>
            <div>
              <h2 className="text-base font-bold text-white">
                إعدادات الاتصال وقاعدة البيانات
              </h2>
              <p className="text-xs text-gray-400">
                الربط مع Supabase السحابي أو المحاكي المحلي
              </p>
            </div>
          </div>

          <button
            onClick={onClose}
            className="p-2 rounded-xl text-gray-400 hover:text-white hover:bg-white/5 transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Content Form */}
        <form onSubmit={handleSubmit} className="p-6 space-y-5">
          
          {/* Mode Switcher */}
          <div className="space-y-2">
            <label className="block text-xs font-semibold text-gray-300">
              بيئة التشغيل (Operation Mode):
            </label>
            <div className="grid grid-cols-2 gap-3">
              <button
                type="button"
                onClick={() => setConfig({ ...config, mode: 'supabase' })}
                className={`p-3.5 rounded-2xl border text-right transition-all flex items-start gap-3 ${
                  config.mode === 'supabase'
                    ? 'bg-indigo-600/15 border-indigo-500 text-white shadow-lg shadow-indigo-600/10'
                    : 'bg-surface-panel/40 border-white/5 text-gray-400 hover:text-white'
                }`}
              >
                <Cloud className={`w-5 h-5 shrink-0 mt-0.5 ${config.mode === 'supabase' ? 'text-indigo-400' : 'text-gray-500'}`} />
                <div>
                  <div className="text-xs font-bold text-white">Supabase Cloud</div>
                  <div className="text-[11px] text-gray-400 mt-0.5">قاعدة البيانات السحابية للإنتاج</div>
                </div>
              </button>

              <button
                type="button"
                onClick={() => setConfig({ ...config, mode: 'simulator' })}
                className={`p-3.5 rounded-2xl border text-right transition-all flex items-start gap-3 ${
                  config.mode === 'simulator'
                    ? 'bg-blue-600/15 border-blue-500 text-white shadow-lg shadow-blue-600/10'
                    : 'bg-surface-panel/40 border-white/5 text-gray-400 hover:text-white'
                }`}
              >
                <Server className={`w-5 h-5 shrink-0 mt-0.5 ${config.mode === 'simulator' ? 'text-blue-400' : 'text-gray-500'}`} />
                <div>
                  <div className="text-xs font-bold text-white">المحاكي المحلي / تجريبي</div>
                  <div className="text-[11px] text-gray-400 mt-0.5">بدون إنترنت أو عبر Node Simulator</div>
                </div>
              </button>
            </div>
          </div>

          {/* Supabase Inputs */}
          {config.mode === 'supabase' ? (
            <div className="space-y-3 pt-2">
              <div>
                <label className="block text-xs text-gray-300 mb-1">
                  Supabase Project URL *
                </label>
                <input
                  type="url"
                  placeholder="https://your-project-id.supabase.co"
                  value={config.supabaseUrl}
                  onChange={(e) => setConfig({ ...config, supabaseUrl: e.target.value })}
                  className="w-full px-3.5 py-2.5 rounded-xl bg-surface-panel/80 border border-white/10 text-xs text-white focus:outline-none focus:border-indigo-500 font-mono"
                  required
                />
              </div>

              <div>
                <label className="block text-xs text-gray-300 mb-1">
                  Supabase Service Role Key (أو Anon Key) *
                </label>
                <input
                  type="password"
                  placeholder="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
                  value={config.supabaseKey}
                  onChange={(e) => setConfig({ ...config, supabaseKey: e.target.value })}
                  className="w-full px-3.5 py-2.5 rounded-xl bg-surface-panel/80 border border-white/10 text-xs text-white focus:outline-none focus:border-indigo-500 font-mono"
                  required
                />
                <p className="text-[10px] text-gray-400 mt-1">
                  يتم حفظ المفتاح فقط محلياً في متصفحك (localStorage) ولا يُرسل لأي جهة خارجية.
                </p>
              </div>
            </div>
          ) : (
            <div className="space-y-3 pt-2">
              <div>
                <label className="block text-xs text-gray-300 mb-1">
                  رابط المحاكي المحلي (Simulator URL)
                </label>
                <input
                  type="text"
                  placeholder="http://localhost:8000"
                  value={config.simulatorUrl}
                  onChange={(e) => setConfig({ ...config, simulatorUrl: e.target.value })}
                  className="w-full px-3.5 py-2.5 rounded-xl bg-surface-panel/80 border border-white/10 text-xs text-white focus:outline-none focus:border-indigo-500 font-mono"
                />
                <p className="text-[10px] text-gray-400 mt-1">
                  يمكنك تشغيل المحاكي عبر تشغيل: <code className="text-indigo-300">node tools/license_simulator.js</code>
                </p>
              </div>
            </div>
          )}

          {/* Cloudflare Pages Deployment Note */}
          <div className="p-3.5 rounded-2xl bg-white/[0.02] border border-white/5 space-y-1.5 text-xs">
            <div className="font-semibold text-gray-300 flex items-center gap-1.5">
              <Globe className="w-3.5 h-3.5 text-indigo-400" />
              <span>النشر المجاني على Cloudflare Pages:</span>
            </div>
            <p className="text-[11px] text-gray-400 leading-relaxed">
              هذه اللوحة مبنية كـ React SPA بالكامل. يمكنك رفع مجلد <code className="text-gray-200">dist/</code> بضغطة زر واحدة (Drag & Drop) على <strong>Cloudflare Pages</strong> مجاناً وبدون أي تكلفة استضافة شهرية، وستحصل على رابط HTTPS مخصص تتحكم به من تليفونك أو الكمبيوتر!
            </p>
          </div>

          {/* Actions */}
          <div className="flex items-center justify-end gap-3 pt-4 border-t border-white/5">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 rounded-xl bg-white/5 hover:bg-white/10 text-xs text-gray-300"
            >
              إلغاء
            </button>
            <button
              type="submit"
              className="flex items-center gap-2 px-5 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-500 text-xs font-bold text-white shadow-lg shadow-indigo-600/30 transition-all"
            >
              {savedSuccess ? (
                <>
                  <CheckCircle className="w-4 h-4 text-emerald-400" />
                  <span>تم الحفظ بنجاح!</span>
                </>
              ) : (
                <>
                  <Save className="w-4 h-4" />
                  <span>حفظ الإعدادات</span>
                </>
              )}
            </button>
          </div>

        </form>

      </div>
    </div>
  );
}
