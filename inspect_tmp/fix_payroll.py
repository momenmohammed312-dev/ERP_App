import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
path = r'G:\flutter\Downloads\pos_offline_desktop_database.sqlite'
con = sqlite3.connect(path)
cur = con.cursor()
cur.execute("SELECT COUNT(*) FROM payroll_table WHERE payroll_period='2026-08'")
print('before', cur.fetchone())
cur.execute("DELETE FROM payroll_table WHERE payroll_period='2026-08'")
con.commit()
cur.execute("SELECT COUNT(*) FROM payroll_table WHERE payroll_period='2026-08'")
print('after', cur.fetchone())
con.close()
print('deleted, now recalc in app will use new logic')
