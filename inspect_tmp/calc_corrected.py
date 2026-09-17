import sqlite3, datetime, sys
sys.stdout.reconfigure(encoding='utf-8')
DB = r'F:\pos_offline_desktop_database.sqlite'
con=sqlite3.connect(DB)
cur=con.cursor()
# get staff
cur.execute("SELECT staff_id, name, basic_salary, hourly_rate FROM staff_table")
staff_map={r[0]: (r[1], r[2], r[3]) for r in cur.fetchall()}
# get monthly
cur.execute("SELECT staff_id, late_hours, overtime_hours, excused_hours, absent_days FROM monthly_attendance_summary_table WHERE period='2026-08'")
monthly={r[0]: r[1:] for r in cur.fetchall()}
# get daily late computed (as before, using 08:10 grace)
import openpyxl
from collections import defaultdict
import re
DAILY_FILE = r'G:\flutter\Downloads\مرتبات_العمال_-_مصحح_جاهز_للاستيراد.xlsx'
def norm(s):
    s=str(s).strip()
    s=re.sub(r'[إأآا]','ا',s)
    s=re.sub(r'ى','ي',s)
    s=re.sub(r'ة','ه',s)
    s=re.sub(r'\s+','',s)
    return s
wb=openpyxl.load_workbook(DAILY_FILE, data_only=True)
# build map
cur.execute("SELECT staff_id, name FROM staff_table")
by_norm=defaultdict(list)
for sid,name in cur.fetchall():
    by_norm[norm(name)].append(sid)
def resolve(name):
    k=norm(name)
    cands=by_norm.get(k,[])
    if len(cands)==1: return cands[0]
    return None
daily_late={}
for sn in wb.sheetnames:
    sid=resolve(sn)
    if not sid: continue
    ws=wb[sn]
    headers=[]
    for row in ws.iter_rows():
        for cell in row:
            if cell.value=='التاريخ':
                headers.append((cell.row,cell.column))
    late_min=0
    for hr,hc in headers:
        r=hr+1
        while True:
            dc=ws.cell(row=r,column=hc).value
            if not isinstance(dc, datetime.datetime): break
            ci=ws.cell(row=r,column=hc+2).value
            # normalize ci
            ci_time=None
            if isinstance(ci, datetime.time): ci_time=ci
            elif isinstance(ci, datetime.datetime): ci_time=ci.time()
            elif isinstance(ci,str) and ci.strip() and 'غ' not in ci:
                try:
                    p=ci.replace('؛',':').split(':')
                    ci_time=datetime.time(int(p[0]), int(p[1]))
                except: pass
            if ci_time and ci_time.hour*60+ci_time.minute > 8*60+10:
                late_min+= ci_time.hour*60+ci_time.minute - (8*60+10)
            r+=1
    daily_late[sid]=late_min/60

# advances
cur.execute("SELECT staff_id, SUM(CASE WHEN status IN ('approved','paid') THEN COALESCE(monthly_deduction, amount) ELSE 0 END) FROM staff_advances GROUP BY staff_id")
adv_map=dict(cur.fetchall())

# now calc final payroll for each of the 52 target (from previous union)
# we have target from monthly + daily
target_ids=set(monthly.keys()) | set(daily_late.keys())
# also include those with advances we just added (like STAFF0051 etc)
# ensure all 29 with advances are included
for sid in adv_map:
    target_ids.add(sid)
print(f"target {len(target_ids)}")
# delete existing payrolls for 2026-08 for those
cur.execute("DELETE FROM payroll_table WHERE payroll_period='2026-08'")
print("deleted existing", cur.rowcount)
con.commit()
# now insert
period_start=int(datetime.datetime(2026,8,1,tzinfo=datetime.timezone.utc).timestamp())
period_end=int(datetime.datetime(2026,8,31,23,59,59,tzinfo=datetime.timezone.utc).timestamp())
now=int(datetime.datetime.now(tz=datetime.timezone.utc).timestamp())
for sid in sorted(target_ids):
    if sid not in staff_map: continue
    name,basic,hr=staff_map[sid]
    # prefer daily computed late if monthly seems inflated (>20)
    m_late, m_over, m_perm, m_abs = monthly.get(sid, (0,0,0,0))
    # if monthly late is 0, use daily
    # if monthly late >20 and daily diff is large, use daily
    daily_h = daily_late.get(sid, 0)
    # choose: if monthly late is 0, use daily; if monthly late >20 and daily <10, use daily
    if m_late == 0 and daily_h>0:
        late_h = daily_h
    elif m_late>20 and daily_h<10:
        late_h = daily_h
    else:
        late_h = m_late if m_late else daily_h
    perm_h = m[2] if sid in monthly else 0
    absent_d = m[3] if sid in monthly else 0
    over_h = m[1] if sid in monthly else 0
    hourly = hr if hr else (basic/30/8 if basic else 0)
    late_ded = late_h*hourly*1.5
    perm_ded = perm_h*hourly*1.0
    absent_ded = absent_d*(basic/30) if basic else 0
    over_pay = over_h*hourly*1.5
    advances = adv_map.get(sid,0) or 0
    bonus = 0  # as per user's "ناقص الصفر" - no bonus for now
    deductions = advances + late_ded + perm_ded + absent_ded
    net = basic + over_pay - deductions
    # working days etc
    cur.execute("INSERT INTO payroll_table (staff_id, payroll_period, period_start, period_end, basic_salary, overtime_hours, overtime_rate, overtime_pay, allowances, deductions, advances, taxes, insurance, other_deductions, net_salary, working_days, present_days, absent_days, leave_days, status, bonus, penalties_total, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (sid, '2026-08', period_start, period_end, basic, over_h, hourly*1.5, over_pay, 0, deductions, advances, 0,0,0, net, 26, 31-absent_d, absent_d, 0, 'calculated', bonus, 0, now, now))
    print(f"{sid} {name[:12]:<12} basic {basic:5.0f} late {late_h:4.1f} perm {perm_h:4.1f} absent {absent_d:2d} over {over_h:4.1f} net {net:7.0f} ded {deductions:6.0f} adv {advances:4.0f}")

con.commit()
print("done")
con.close()
