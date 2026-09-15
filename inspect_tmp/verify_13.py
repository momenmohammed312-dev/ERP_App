import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
con=sqlite3.connect(r'F:\pos_offline_desktop_database.sqlite')
cur=con.cursor()
for sid in ['STAFF0016','STAFF0048','STAFF0057','STAFF0059','STAFF0060','STAFF0063','STAFF0076','STAFF0080','STAFF0081','STAFF0082','STAFF0083','STAFF0084','STAFF0087']:
    cur.execute("SELECT late_hours, overtime_hours, permission_hours, absent_days, bonus, net_salary, deductions FROM payroll_table WHERE staff_id=? AND payroll_period='2026-08'", (sid,))
    row=cur.fetchone()
    print(sid, row)
con.close()
