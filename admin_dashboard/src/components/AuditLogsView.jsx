import React from 'react';
import { History, ShieldCheck, KeyRound, Laptop, Sparkles, Clock, CheckCircle2 } from 'lucide-react';

export default function AuditLogsView({ licenses }) {
  // Generate audit events from current licenses
  const events = [
    {
      id: 'evt-1',
      action: 'إصدار وتوقيع ترخيص جديد',
      type: 'create',
      client_name: 'سوبر ماركت النور والبركة',
      key: 'POS-DEMO-2026-X1',
      details: 'تم تفعيل باقة سنوية تشمل: نقاط البيع، المخزون، والعهد المالية',
      time: 'منذ ساعتين',
      status: 'نجاح',
    },
    {
      id: 'evt-2',
      action: 'مزامنة دورية وتجديد الـ Lease',
      type: 'checkin',
      client_name: 'مصنع الأمل للحلويات والفرن',
      key: 'POS-FACT-8890-M3',
      details: 'تم تمديد صلاحية العمل أوفلاين 30 يوماً بنجاح',
      time: 'منذ 5 ساعات',
      status: 'نجاح',
    },
    {
      id: 'evt-3',
      action: 'تعديل الوحدات (Feature Gating)',
      type: 'update',
      client_name: 'مصنع الأمل للحلويات والفرن',
      key: 'POS-FACT-8890-M3',
      details: 'تم إضافة موديول التصنيع والهوالك والتوالف للترخيص',
      time: 'بالأمس',
      status: 'نجاح',
    },
    {
      id: 'evt-4',
      action: 'تسجيل جهاز كاشير جديد (Hardware Binding)',
      type: 'device',
      client_name: 'محل البرنس للأدوات المنزلية (تجربة)',
      key: 'POS-TRIAL-3321-T9',
      details: 'ربط MachineGuid: 9A7B6C-WIN11 بنجاح (المتبقي: 0 أجهزة)',
      time: 'منذ يومين',
      status: 'نجاح',
    }
  ];

  return (
    <div className="space-y-6">
      <div className="p-6 rounded-2xl bg-white dark:bg-[#111827] border border-slate-200/80 dark:border-white/5 shadow-sm flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="p-2.5 rounded-xl bg-purple-600 text-white shadow-md shadow-purple-600/30">
            <History className="w-5 h-5" />
          </div>
          <div>
            <h2 className="text-lg font-bold text-slate-900 dark:text-white">
              سجل العمليات والتدقيق الأمني (Audit Logs)
            </h2>
            <p className="text-xs text-slate-500 dark:text-gray-400">
              تسجيل تاريخي لعمليات إصدار التراخيص، تحديث الموديولات، وتسجيل الأجهزة
            </p>
          </div>
        </div>
      </div>

      <div className="rounded-2xl border border-slate-200/80 dark:border-white/5 bg-white dark:bg-[#111827] shadow-sm p-6">
        <div className="space-y-6">
          {events.map((evt, idx) => (
            <div key={evt.id} className="flex items-start gap-4 pb-6 border-b border-slate-100 dark:border-white/5 last:border-b-0 last:pb-0">
              <div className="p-2.5 rounded-xl bg-indigo-50 dark:bg-indigo-500/10 text-indigo-600 dark:text-indigo-400 mt-0.5">
                {evt.type === 'create' ? <KeyRound className="w-4 h-4" /> :
                 evt.type === 'checkin' ? <CheckCircle2 className="w-4 h-4" /> :
                 evt.type === 'update' ? <Sparkles className="w-4 h-4" /> : <Laptop className="w-4 h-4" />}
              </div>

              <div className="flex-1 space-y-1">
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-1">
                  <div className="text-xs font-bold text-slate-900 dark:text-white">
                    {evt.action} — <span className="text-indigo-600 dark:text-indigo-400">{evt.client_name}</span>
                  </div>
                  <span className="text-[11px] text-slate-400 dark:text-gray-500 font-mono flex items-center gap-1">
                    <Clock className="w-3 h-3" /> {evt.time}
                  </span>
                </div>

                <p className="text-xs text-slate-600 dark:text-gray-400 leading-relaxed">
                  {evt.details}
                </p>

                <div className="pt-1 flex items-center gap-2 text-[10px] font-mono text-slate-400 dark:text-gray-500">
                  <span>المفتاح: {evt.key}</span>
                  <span>•</span>
                  <span className="text-emerald-600 dark:text-emerald-400 font-semibold">{evt.status}</span>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
