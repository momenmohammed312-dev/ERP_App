import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
path = r'G:\flutter\Downloads\pos_offline_desktop_database.sqlite'
con = sqlite3.connect(path)
cur = con.cursor()
cur.execute("SELECT staff_id, payroll_period, basic_salary, late_hours, late_deduction, permission_hours, permission_deduction, absent_days, net_salary FROM payroll_table WHERE staff_id='STAFF0052' AND payroll_period='2026-08'")
print(cur.fetchall())
# also check attendance summary via python calc
# get attendance for Aug
import datetime
# need to handle timestamp in seconds
cur.execute("SELECT date, check_in_time, status, late_minutes, permission_hours, excused_hours FROM attendance_table WHERE staff_id='STAFF0052' ORDER BY date")
rows = cur.fetchall()
for r in rows[:5]:
    print(r)
# count late
cur.execute("SELECT COUNT(*), SUM(late_minutes) FROM attendance_table WHERE staff_id='STAFF0052' AND status='late'")
print(cur.fetchone())
con.close()
