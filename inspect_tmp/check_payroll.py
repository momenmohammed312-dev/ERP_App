import sqlite3, os, sys
sys.stdout.reconfigure(encoding='utf-8')
path = r'G:\flutter\Downloads\pos_offline_desktop_database.sqlite'
if not os.path.exists(path):
    print('NOT_FOUND', path)
    import glob
    print(glob.glob(r'G:\flutter\Downloads\*.sqlite'))
    sys.exit(0)
con = sqlite3.connect(path)
cur = con.cursor()
cur.execute("SELECT sql FROM sqlite_master WHERE type='table' AND name='payroll_table'")
row = cur.fetchone()
print('SCHEMA:', (row[0][:1200] if row else 'no table'))
print('--- payroll 2026-08 ---')
cur.execute("SELECT payroll_period, staff_id, basic_salary, late_hours, late_deduction, permission_hours, permission_deduction, overtime_hours, overtime_pay, net_salary, status FROM payroll_table WHERE payroll_period='2026-08'")
cols = [d[0] for d in cur.description]
print(cols)
rows = cur.fetchall()
for r in rows[:15]:
    print(r)
print('COUNT:', len(rows))
# also check attendance for one staff to see lateMinutes
print('--- sample attendance lateMinutes ---')
try:
    cur.execute("SELECT staff_id, date, status, late_minutes, permission_hours, excused, excused_hours FROM attendance_table LIMIT 5")
    print([d[0] for d in cur.description])
    for r in cur.fetchall():
        print(r)
except Exception as e:
    print('attendance error', e)
con.close()
