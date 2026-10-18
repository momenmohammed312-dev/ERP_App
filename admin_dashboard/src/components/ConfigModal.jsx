import React, { useState } from 'react';
import { X, Server, Cloud, Globe, Save, CheckCircle } from 'lucide-react';
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
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/40 backdrop-blur-xs">
      <div className="relative w-full max-w-xl rounded-2xl bg-white border border-slate-200 shadow-xl overflow-hidden">
        
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-slate-100 bg-slate-50/50">
          <div className="flex items-center gap-3">
            <div className="p-2.5 rounded-xl bg-blue-50 text-blue-600 border border-blue-200">
              <Server className="w-5 h-5" />
            </div>
            <div>
              <h2 className="text-sm font-bold text-slate-900">
                إعدادات الربط وقاعدة بيانات مدار
              </h2>
              <p className="text-xs text-slate-500">
                الربط مع Supabase السحابي للإنتاج أو المحاكي المحلي
              </p>
            </div>
          </div>

          <button
            onClick={onClose}
            className="p-1.5 rounded-lg text-slate-400 hover:text-slate-600 hover:bg-slate-100 transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Content Form */}
        <form onSubmit={handleSubmit} className="p-6 space-y-4 text-xs">
          
          {/* Mode Switcher */}
          <div className="space-y-2">
            <label className="block font-bold text-slate-700">
              بيئة التشغيل السحابية:
            </label>
            <div className="grid grid-cols-2 gap-3">
              <button
                type="button"
                onClick={() => setConfig({ ...config, mode: 'supabase' })}
                className={`p-3.5 rounded-xl border text-right transition-all flex items-start gap-2.5 ${
                  config.mode === 'supabase'
                    ? 'bg-blue-50 border-blue-600 text-blue-900 shadow-xs'
                    : 'bg-slate-50 border-slate-200 text-slate-600 hover:border-slate-300'
                }`}
              >
                <Cloud className={`w-5 h-5 shrink-0 mt-0.5 ${config.mode === 'supabase' ? 'text-blue-600' : 'text-slate-400'}`} />
                <div>
                  <div className="font-bold text-slate-900">Supabase Cloud</div>
                  <div className="text-[11px] text-slate-500 mt-0.5">قاعدة البيانات السحابية الحية</div>
                </div>
              </button>

              <button
                type="button"
                onClick={() => setConfig({ ...config, mode: 'simulator' })}
                className={`p-3.5 rounded-xl border text-right transition-all flex items-start gap-2.5 ${
                  config.mode === 'simulator'
                    ? 'bg-blue-50 border-blue-600 text-blue-900 shadow-xs'
                    : 'bg-slate-50 border-slate-200 text-slate-600 hover:border-slate-300'
                }`}
              >
                <Server className={`w-5 h-5 shrink-0 mt-0.5 ${config.mode === 'simulator' ? 'text-blue-600' : 'text-slate-400'}`} />
                <div>
                  <div className="font-bold text-slate-900">المحاكي المحلي</div>
                  <div className="text-[11px] text-slate-500 mt-0.5">تجربة مباشرة على الكمبيوتر</div>
                </div>
              </button>
            </div>
          </div>

          {/* Supabase Inputs */}
          {config.mode === 'supabase' ? (
            <div className="space-y-3 pt-1">
              <div>
                <label className="block text-slate-700 font-bold mb-1">
                  Supabase Project URL *
                </label>
                <input
                  type="url"
                  placeholder="https://your-project.supabase.co"
                  value={config.supabaseUrl}
                  onChange={(e) => setConfig({ ...config, supabaseUrl: e.target.value })}
                  className="w-full px-3 py-2 rounded-xl bg-slate-50 border border-slate-200 text-xs text-slate-900 focus:outline-none focus:border-blue-500 focus:bg-white font-mono"
                  required
                />
              </div>

              <div>
                <label className="block text-slate-700 font-bold mb-1">
                  Supabase Service Role Key (أو Anon Key) *
                </label>
                <input
                  type="password"
                  placeholder="eyJhbGciOiJIUzI1NiIsInR5cCI..."
                  value={config.supabaseKey}
                  onChange={(e) => setConfig({ ...config, supabaseKey: e.target.value })}
                  className="w-full px-3 py-2 rounded-xl bg-slate-50 border border-slate-200 text-xs text-slate-900 focus:outline-none focus:border-blue-500 focus:bg-white font-mono"
                  required
                />
                <p className="text-[10px] text-slate-400 mt-0.5">
                  يتم حفظ المفتاح بأمان داخل متصفحك فقط ولا يُنقل لأي طرف ثالث.
                </p>
              </div>
            </div>
          ) : (
            <div className="space-y-2 pt-1">
              <div>
                <label className="block text-slate-700 font-bold mb-1">
                  رابط المحاكي المحلي (Simulator URL)
                </label>
                <input
                  type="text"
                  placeholder="http://localhost:8000"
                  value={config.simulatorUrl}
                  onChange={(e) => setConfig({ ...config, simulatorUrl: e.target.value })}
                  className="w-full px-3 py-2 rounded-xl bg-slate-50 border border-slate-200 text-xs text-slate-900 focus:outline-none focus:border-blue-500 focus:bg-white font-mono"
                />
                <p className="text-[11px] text-slate-500 mt-1">
                  شغّل المحاكي بأمر: <code className="bg-slate-100 text-blue-700 px-1 py-0.5 rounded font-bold">node tools/license_simulator.js</code>
                </p>
              </div>
            </div>
          )}

          {/* Cloudflare Note */}
          <div className="p-3.5 rounded-xl bg-slate-50 border border-slate-200 space-y-1">
            <div className="font-bold text-slate-800 flex items-center gap-1.5">
              <Globe className="w-4 h-4 text-blue-600" />
              <span>استضافة مجانية 100% على Cloudflare Pages:</span>
            </div>
            <p className="text-[11px] text-slate-500 leading-relaxed">
              هذه اللوحة تعمل كـ SPA مباشرة من المتصفح دون الحاجة لسيرفر backend إضافي، ويمكنك رفع مجلد <code className="font-bold text-slate-700">dist/</code> على Cloudflare Pages برابط مخصص دائم مجاناً وبلا أي رسوم شهرية.
            </p>
          </div>

          {/* Actions */}
          <div className="flex items-center justify-end gap-2 pt-3 border-t border-slate-100">
            <button
              type="button"
              onClick={onClose}
              className="px-4 py-2 rounded-xl bg-slate-100 hover:bg-slate-200 text-slate-700 font-bold"
            >
              إلغاء
            </button>
            <button
              type="submit"
              className="flex items-center gap-2 px-5 py-2 rounded-xl bg-blue-600 hover:bg-blue-500 text-white font-bold shadow-xs transition-colors"
            >
              {savedSuccess ? (
                <>
                  <CheckCircle className="w-4 h-4" />
                  <span>تم الحفظ!</span>
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
