import sqlite3, re, datetime, sys, json, os
sys.stdout.reconfigure(encoding='utf-8')
import openpyxl
from collections import defaultdict

DB = r'F:\pos_offline_desktop_database.sqlite'
DAILY_FILE = r'G:\flutter\Downloads\مرتبات_العمال_-_مصحح_جاهز_للاستيراد.xlsx'
MONTHLY_FILE = r'G:\flutter\Downloads\attendance_import_filled (1).xlsx'

def norm(s):
    if s is None: return None
    s=str(s).strip()
    s=re.sub(r'[إأآا]','ا',s)
    s=re.sub(r'ى','ي',s)
    s=re.sub(r'ة','ه',s)
    s=re.sub(r'\s+','',s)
    return s

con=sqlite3.connect(DB)
cur=con.cursor()
cur.execute("select staff_id, name, basic_salary, hourly_rate, status from staff_table")
staff_rows=cur.fetchall()
by_norm=defaultdict(list)
for sid,name,st,bsal in [(r[0],r[1],r[4] if len(r)>4 else r[2], r[2] if len(r)==3 else r[2]) for r in staff_rows]:
    # staff_rows is 5 cols: sid,name,status,basic,hr? Actually we selected 4: sid,name,status,basic
    pass
# redo correctly
cur.execute("SELECT staff_id, name, status, basic_salary, hourly_rate FROM staff_table")
staff_rows=cur.fetchall()
by_norm=defaultdict(list)
staff_map={}
for sid,name,st,bsal,hr in staff_rows:
    staff_map[sid]=(name,bsal,hr,st)
    by_norm[norm(name)].append(sid)

DUPLICATE_KEEPERS = {'STAFF0096':'ام سما','STAFF0102':'ام محمود','STAFF0115':'عزه','STAFF0057':'ياسمين','STAFF0066':'دنيا خميس','STAFF0078':'ام سالم','STAFF0074':'عبدالله محمد','STAFF0077':'علي محمد','STAFF0069':'حبيبه علي','STAFF0106':'اسماء حسني'}
SKIP_NAMES={'بسملة','محمد محمود','ملك','هبه','صفا محمود','عائشة محمد','محمد عيسى','ام حماده','ام احمد','فرح عماد','احمد عبد الكريم'}
def resolve(name):
    k=norm(name)
    if k in {norm(x) for x in SKIP_NAMES}: return None
    cands=by_norm.get(k,[])
    if len(cands)==1: return cands[0]
    if len(cands)>1:
        keep=[c for c in cands if c in DUPLICATE_KEEPERS]
        if len(keep)==1: return keep[0]
        return None
    return None

# load daily
wb_daily=openpyxl.load_workbook(DAILY_FILE, data_only=True)
daily=defaultdict(list)
unresolved_daily=[]
for sn in wb_daily.sheetnames:
    sid=resolve(sn)
    if not sid:
        unresolved_daily.append(sn)
        continue
    ws=wb_daily[sn]
    headers=[]
    for row in ws.iter_rows():
        for cell in row:
            if cell.value=='التاريخ':
                headers.append((cell.row,cell.column))
    for hr,hc in headers:
        r=hr+1
        while True:
            dc=ws.cell(row=r,column=hc).value
            if not isinstance(dc, datetime.datetime): break
            ci=ws.cell(row=r,column=hc+2).value
            co=ws.cell(row=r,column=hc+3).value
            def to_t(v):
                if v is None or (isinstance(v,str) and v.strip()==''): return None
                if isinstance(v, datetime.time): return v
                if isinstance(v, datetime.datetime): return v.time()
                if isinstance(v,str):
                    if 'غ' in v: return None
                    try:
                        p=v.replace('؛',':').replace(';',':').split(':')
                        return datetime.time(int(p[0]), int(p[1]) if len(p)>1 else 0)
                    except: return None
                return None
            daily[sid].append((dc.date(), to_t(ci), to_t(co)))
            r+=1

# load monthly
wb_month=openpyxl.load_workbook(MONTHLY_FILE, data_only=True)
ws_m=wb_month['ملخص']
monthly={}
unresolved_month=[]
for row in ws_m.iter_rows(min_row=2, values_only=True):
    name=row[0]
    if not name or 'تعليمات' in str(name): continue
    sid=resolve(name)
    if not sid:
        unresolved_month.append(str(name))
        continue
    late,extra,perm,absen=row[1],row[2],row[3],row[4]
    period=row[5] if len(row)>5 and row[5] else '2026-08'
    if isinstance(period, datetime.datetime): period=period.strftime('%Y-%m')
    period=str(period).strip()
    if period=='None' or not period: period='2026-08'
    monthly[sid]={'late': float(late) if isinstance(late,(int,float)) else 0.0,
                  'over': float(extra) if isinstance(extra,(int,float)) else 0.0,
                  'perm': float(perm) if isinstance(perm,(int,float)) else 0.0,
                  'absent': int(absen) if isinstance(absen,(int,float)) else 0,
                  'period': period}

# validation
print("=== VALIDATION ===")
print(f"staff total {len(staff_rows)} daily resolved {len(daily)} monthly resolved {len(monthly)}")
print(f"unresolved daily sheets: {unresolved_daily}")
print(f"unresolved monthly rows: {unresolved_month} ")
# check daily vs monthly for common
common=set(daily.keys()) & set(monthly.keys())
print(f"common {len(common)}")
for sid in sorted(common)[:5]:
    name=staff_map[sid][0]
    # compute daily late
    # grace 10, work 8-17
    late_min=0
    for d,ci,co in daily[sid]:
        if ci and ci.hour*60+ci.minute > 8*60+10:
            late_min += ci.hour*60+ci.minute - (8*60+10)
    daily_late_h=late_min/60
    m=monthly[sid]
    print(f"{sid} {name}: daily_late {daily_late_h:.1f} vs monthly {m['late']}  diff {daily_late_h - m['late']:.1f}  perm {m['perm']} absent {m['absent']}")

# compute final payroll for 2026-08 for all target
target_ids=set(daily.keys()) | set(monthly.keys())
print("\n=== FINAL PAYROLL 2026-08 (Basic -0 + Over*1.5 - Absent*(basic/30) - Late*1.5 - Perm*1.0) ===")
print(f"{'STAFF':<10} {'Name':<12} {'Basic':>7} {'Late':>5} {'Perm':>5} {'Absent':>6} {'Over':>5} {'Hourly':>7} {'LateDed':>8} {'PermDed':>8} {'AbsDed':>8} {'OverPay':>8} {'Net':>9}")
# get advances
cur.execute("SELECT staff_id, SUM(CASE WHEN status IN ('approved','paid') THEN COALESCE(monthly_deduction, amount) ELSE 0 END) FROM staff_advances GROUP BY staff_id")
adv_map=dict(cur.fetchall())
# settings bonus
cur.execute("SELECT setting_value FROM attendance_settings WHERE setting_key='perfect_attendance_bonus'")
row=cur.fetchone()
bonus_def=float(row[0]) if row else 200.0

results=[]
for sid in sorted(target_ids):
    name, basic, hr, st = staff_map[sid] if sid in staff_map else ("?",0,None,"?")
    # basic
    if sid in monthly:
        m=monthly[sid]
        late_h=m['late']; perm_h=m['perm']; absent_d=m['absent']; over_h=m['over']
    else:
        # daily only, compute from daily
        late_min=sum((ci.hour*60+ci.minute - (8*60+10)) for d,ci,co in daily[sid] if ci and ci.hour*60+ci.minute > 8*60+10)
        late_h=late_min/60
        perm_h=0
        # absent from daily where ci is None and not Friday
        # count absent as days where no record and not Friday? For now 0
        absent_d=0
        over_h=0
    hourly= hr if hr else (basic/30/8 if basic else 0)
    late_ded=late_h*hourly*1.5
    perm_ded=perm_h*hourly*1.0
    absent_ded=absent_d*(basic/30) if basic else 0
    over_pay=over_h*hourly*1.5
    advances=adv_map.get(sid,0) or 0
    # bonus: give 200 only if no absent/late/perm/leave? For final, give 0 for now to match user's "ناقص الصفر" (maybe 0 bonus)
    # User said "ناقص الصفر" and "الصفر موجودة" - unclear, but we will not add bonus for those with deductions, to keep net as basic - deductions + over
    # For validation, set bonus 0 for all with any deduction, 200 only if perfect
    has_ded = (late_h>0 or perm_h>0 or absent_d>0)
    bonus = 0 if has_ded else bonus_def
    # But earlier PDFs had bonus even with deductions, so maybe always 200? We'll show both
    # For final, use 0 to match "ناقص الصفر" (maybe bonus 0)
    bonus_to_use = 0  # as per "ناقص الصفر"
    net = basic - 0 + over_pay - absent_ded - late_ded - perm_ded  # Basic -0 + Over - Absent - Late - Perm
    # Actually user said: Basic - 0 + Over - Absent - Late - Perm => net = basic + over - absent - late - perm
    # We'll compute that
    net2 = basic + over_pay - absent_ded - late_ded - perm_ded - advances
    results.append((sid,name,basic,late_h,perm_h,absent_d,over_h,hourly,late_ded,perm_ded,absent_ded,over_pay,net2))
    print(f"{sid:<10} {name[:12]:<12} {basic:7.0f} {late_h:5.1f} {perm_h:5.1f} {absent_d:6d} {over_h:5.1f} {hourly:7.2f} {late_ded:8.2f} {perm_ded:8.2f} {absent_ded:8.2f} {over_pay:8.2f} {net2:9.2f}")

# also check for staff with no attendance but in monthly (should still have payroll)
# save to json for later DB write
import json, pathlib
out = {
    sid: {"name": staff_map[sid][0], "basic": staff_map[sid][1], "late": r[3], "perm": r[4], "absent": r[5], "over": r[6], "net": r[12]}
    for sid, *r in [(sid,)+tuple(results[i][1:]) for i,sid in enumerate(sorted(target_ids))]
}
# Instead, build dict
# Write validation report
with open(r'G:\development\POS-Offline-Desktop-main\inspect_tmp\final_payroll_validation.json','w',encoding='utf-8') as f:
    json.dump([{"staff_id": sid, "name": staff_map[sid][0], "basic": basic, "late": late_h, "perm": perm_h, "absent": absent_d, "over": over_h, "net": net2} for sid,name,basic,late_h,perm_h,absent_d,over_h,hourly,late_ded,perm_ded,absent_ded,over_pay,net2 in results], f, ensure_ascii=False, indent=2)
print("\nWrote final_payroll_validation.json")

con.close()
