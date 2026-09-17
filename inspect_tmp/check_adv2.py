import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
path = r'G:\flutter\Downloads\pos_offline_desktop_database (1).sqlite'
import os
print(os.path.exists(path))
con=sqlite3.connect(path)
cur=con.cursor()
cur.execute("SELECT staff_id, amount, status, monthly_deduction, installment_months FROM staff_advances")
rows=cur.fetchall()
print(f"total {len(rows)}")
for r in rows:
    print(r)
cur.execute("SELECT staff_id, amount, status FROM staff_advances WHERE status != 'pending'")
print("non-pending", cur.fetchall())
cur.execute("SELECT staff_id, amount, status FROM staff_advances WHERE status IN ('approved','paid')")
print("approved/paid", cur.fetchall())
# also check staff names
cur.execute("SELECT staff_id, name FROM staff_table WHERE staff_id IN (SELECT staff_id FROM staff_advances)")
for r in cur.fetchall():
    print(r)
con.close()
