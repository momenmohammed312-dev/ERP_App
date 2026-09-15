import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
path = r'G:\flutter\Downloads\pos_offline_desktop_database.sqlite'
con = sqlite3.connect(path)
cur = con.cursor()
cur.execute("SELECT staff_id, amount, status, installment_months, monthly_deduction FROM staff_advances LIMIT 5")
for r in cur.fetchall():
    print(r)
cur.execute("SELECT COUNT(*) FROM staff_advances WHERE status IN ('approved','paid')")
print('approved/paid', cur.fetchone())
cur.execute("SELECT staff_id, payroll_period, basic_salary, advances, deductions, net_salary FROM payroll_table LIMIT 3")
for r in cur.fetchall():
    print(r)
con.close()
