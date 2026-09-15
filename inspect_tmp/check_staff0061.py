import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
path = r'G:\flutter\Downloads\pos_offline_desktop_database.sqlite'
con = sqlite3.connect(path)
cur = con.cursor()
# find staff 0061 name
cur.execute("SELECT name FROM staff_table WHERE staff_id='STAFF0061'")
print(cur.fetchone())
# attendance for Aug 2026
# dates are stored as integer timestamps (milliseconds? drift stores as int)
# check sample
cur.execute("SELECT date, status, late_minutes, permission_hours, excused, excused_hours, check_in_time, check_out_time FROM attendance_table WHERE staff_id='STAFF0061' ORDER BY date LIMIT 20")
rows = cur.fetchall()
for r in rows:
    print(r)
# count Aug
cur.execute("SELECT COUNT(*), SUM(late_minutes), SUM(permission_hours) FROM attendance_table WHERE staff_id='STAFF0061' AND date BETWEEN 1651363200000 AND 1664582400000")
# better use date range via python
import datetime
start = int(datetime.datetime(2026,8,1).timestamp()*1000)
end = int(datetime.datetime(2026,8,31,23,59,59).timestamp()*1000)
print('range', start, end)
cur.execute("SELECT date, check_in_time, check_out_time, late_minutes, permission_hours FROM attendance_table WHERE staff_id='STAFF0061' AND date >= ? AND date <= ?", (start,end))
rows = cur.fetchall()
print('aug rows', len(rows))
for r in rows[:10]:
    print(r)
# also check payroll
cur.execute("SELECT payroll_period, basic_salary, late_hours, late_deduction, permission_hours, permission_deduction, net_salary FROM payroll_table WHERE staff_id='STAFF0061' AND payroll_period='2026-08'")
print(cur.fetchall())
con.close()
