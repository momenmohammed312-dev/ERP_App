import React from 'react';
import { History, KeyRound, Laptop, Sparkles, Clock, CheckCircle2 } from 'lucide-react';

export default function AuditLogsView({ licenses }) {
  const events = [
    {
      id: 'evt-1',
      action: 'إصدار وتوقيع ترخيص جديد',
      type: 'create',
      client_name: 'سوبرماركت النور والبركة',
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
      action: 'تعديل الوحدات (Modular Feature Gating)',
      type: 'update',
      client_name: 'مصنع الأمل للحلويات والفرن',
      key: 'POS-FACT-8890-M3',
      details: 'تم إضافة موديول التصنيع والهوالك والتوالف للترخيص سحابياً',
      time: 'بالأمس',
      status: 'نجاح',
    },
    {
      id: 'evt-4',
      action: 'توثيق بصمة جهاز كاشير جديد',
      type: 'device',
      client_name: 'محل البرنس للأدوات المنزلية (تجربة)',
      key: 'POS-TRIAL-3321-T9',
      details: 'ربط MachineGuid: 9A7B6C-WIN11 بنجاح بنظام مدار',
      time: 'منذ يومين',
      status: 'نجاح',
    }
  ];

  return (
    <div className="space-y-6">
      <div className="p-6 rounded-2xl bg-white border border-slate-200/90 shadow-xs flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="p-3 rounded-xl bg-purple-50 text-purple-600 border border-purple-200/60">
            <History className="w-6 h-6" />
          </div>
          <div>
            <h2 className="text-base font-extrabold text-slate-900">
              سجل العمليات والتدقيق الأمني (Audit Logs)
            </h2>
            <p className="text-xs text-slate-500 mt-0.5">
              توثيق زمني دقيق لكل حركة ترخيص أو مزامنة أو فك ارتباط أجهزة
            </p>
          </div>
        </div>
      </div>

      <div className="rounded-2xl border border-slate-200/90 bg-white shadow-xs p-6">
        <div className="space-y-5">
          {events.map((evt) => (
            <div key={evt.id} className="flex items-start gap-4 pb-5 border-b border-slate-100 last:border-b-0 last:pb-0">
              <div className="p-2.5 rounded-xl bg-blue-50 text-blue-600 border border-blue-200/60 mt-0.5">
                {evt.type === 'create' ? <KeyRound className="w-4 h-4" /> :
                 evt.type === 'checkin' ? <CheckCircle2 className="w-4 h-4" /> :
                 evt.type === 'update' ? <Sparkles className="w-4 h-4" /> : <Laptop className="w-4 h-4" />}
              </div>

              <div className="flex-1 space-y-1">
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-1">
                  <div className="text-xs font-bold text-slate-900">
                    {evt.action} — <span className="text-blue-700">{evt.client_name}</span>
                  </div>
                  <span className="text-[11px] text-slate-400 font-mono flex items-center gap-1">
                    <Clock className="w-3 h-3" /> {evt.time}
                  </span>
                </div>

                <p className="text-xs text-slate-600 leading-relaxed">
                  {evt.details}
                </p>

                <div className="pt-1 flex items-center gap-2 text-[10px] font-mono text-slate-400">
                  <span>كود: {evt.key}</span>
                  <span>•</span>
                  <span className="text-emerald-700 font-bold bg-emerald-50 px-2 py-0.5 rounded border border-emerald-200">{evt.status}</span>
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
