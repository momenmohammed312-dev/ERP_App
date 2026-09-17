import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
path = r'G:\flutter\Documents\pos_offline_desktop_database.sqlite'
con = sqlite3.connect(path)
cur = con.cursor()
cur.execute("DELETE FROM payroll_table WHERE status='calculated' AND payroll_period IN ('2026-08','2026-09')")
print('deleted', cur.rowcount)
con.commit()
cur.execute("SELECT COUNT(*) FROM payroll_table WHERE payroll_period='2026-08'")
print('remaining', cur.fetchone())
con.close()
