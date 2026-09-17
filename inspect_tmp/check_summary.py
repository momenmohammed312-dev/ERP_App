import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
path = r'G:\flutter\Documents\pos_offline_desktop_database.sqlite'
con = sqlite3.connect(path)
cur = con.cursor()
cur.execute("SELECT staff_id, period, late_hours, overtime_hours, excused_hours, absent_days FROM monthly_attendance_summary_table WHERE staff_id='STAFF0052'")
print(cur.fetchall())
# also check attendance for Aug with permission
cur.execute("SELECT date, status, late_minutes, permission_hours, excused_hours FROM attendance_table WHERE staff_id='STAFF0052' AND date BETWEEN 1785531600 AND 1788200000")
for r in cur.fetchall():
    print(r)
con.close()
