import sqlite3, re, sys
sys.stdout.reconfigure(encoding='utf-8')
import openpyxl
from collections import defaultdict

DB = r'G:\flutter\Downloads\pos_offline_desktop_database.sqlite'
EXCEL = r'G:\flutter\Downloads\مرتبات_العمال_-_مصحح_جاهز_للاستيراد.xlsx'

def norm(s):
    import re
    if s is None: return None
    s=str(s).strip()
    s=re.sub(r'[إأآا]','ا',s)
    s=re.sub(r'ى','ي',s)
    s=re.sub(r'ة','ه',s)
    s=re.sub(r'\s+','',s)
    return s

con=sqlite3.connect(DB)
cur=con.cursor()
cur.execute("SELECT staff_id, name, basic_salary FROM staff_table")
staff_rows=cur.fetchall()
staff_map={r[0]: r[1] for r in staff_rows}
# advances
cur.execute("SELECT staff_id, amount, status FROM staff_advances")
adv_rows=cur.fetchall()
print(f"DB advances total {len(adv_rows)}")
for sid, amt, st in adv_rows:
    print(f"  {sid} {staff_map.get(sid,'?')} amount={amt} status={st}")

# attendance from Excel
wb=openpyxl.load_workbook(EXCEL, data_only=True)
# resolve names
cur.execute("SELECT staff_id, name FROM staff_table")
by_norm=defaultdict(list)
for sid,name in cur.fetchall():
    by_norm[norm(name)].append(sid)

SKIP={'بسملة','محمد محمود','ملك','هبه','صفا محمود','عائشة محمد','محمد عيسى','ام حماده','ام احمد'}
def resolve(name):
    k=norm(name)
    if k in {norm(x) for x in SKIP}: return None
    cands=by_norm.get(k,[])
    if len(cands)==1: return cands[0]
    if len(cands)>1:
        # keep first active?
        return cands[0]
    return None

excel_staff=[]
for sn in wb.sheetnames:
    sid=resolve(sn)
    if sid:
        excel_staff.append((sn,sid))
print(f"\nExcel sheets resolved {len(excel_staff)}")
for sn,sid in excel_staff:
    print(f"  {sn} -> {sid} {staff_map.get(sid)}")
# compare
adv_sids=set([r[0] for r in adv_rows])
excel_sids=set([sid for _,sid in excel_staff])
print(f"\nAdv SIDs {adv_sids}")
print(f"Excel SIDs count {len(excel_sids)}")
print(f"Intersection (has both): {adv_sids & excel_sids}")
print(f"Adv only (no attendance): {adv_sids - excel_sids}")
print(f"Attendance only (no advance): {len(excel_sids - adv_sids)} staff")
# check for STAFF0001 who has advance but was it in Excel?
print(f"\nSTAFF0001 in Excel? {'STAFF0001' in excel_sids} -> {staff_map.get('STAFF0001')}")
# check staff with advance pending vs attendance
for sid in adv_sids:
    has_att = sid in excel_sids
    print(f"Advance staff {sid} has_attendance={has_att}")

con.close()
