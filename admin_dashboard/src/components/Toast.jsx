import React from 'react';
import { CheckCircle2, AlertCircle, Info, X } from 'lucide-react';

export default function Toast({ toast, onClose }) {
  if (!toast) return null;

  const icons = {
    success: <CheckCircle2 className="w-4 h-4 text-emerald-400 shrink-0" />,
    error: <AlertCircle className="w-4 h-4 text-rose-400 shrink-0" />,
    info: <Info className="w-4 h-4 text-indigo-400 shrink-0" />,
  };

  return (
    <div className="fixed bottom-6 left-6 z-50 animate-bounce-in max-w-sm">
      <div className="flex items-center gap-3 px-4 py-3 rounded-2xl bg-[#111827] border border-white/10 shadow-2xl text-xs text-white">
        {icons[toast.type] || icons.info}
        <span className="flex-1 font-medium">{toast.message}</span>
        <button
          onClick={onClose}
          className="text-gray-400 hover:text-white transition-colors"
        >
          <X className="w-3.5 h-3.5" />
        </button>
      </div>
    </div>
  );
}
