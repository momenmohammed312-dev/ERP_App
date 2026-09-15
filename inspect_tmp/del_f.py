import sqlite3
con=sqlite3.connect(r'F:\pos_offline_desktop_database.sqlite')
cur=con.cursor()
cur.execute("DELETE FROM payroll_table WHERE payroll_period='2026-08'")
print('deleted', cur.rowcount)
con.commit()
con.close()
