import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
con=sqlite3.connect(r'F:\pos_offline_desktop_database.sqlite')
cur=con.cursor()
# for all payroll 2026-08 where absent=0 and bonus=0, set bonus 200 and recalc net
cur.execute("SELECT staff_id, basic_salary, overtime_hours, overtime_rate, late_deduction, permission_deduction, absent_days, deductions, net_salary, bonus FROM payroll_table WHERE payroll_period='2026-08' AND absent_days=0 AND bonus=0")
rows=cur.fetchall()
print(f"found {len(rows)} with 0 absent and 0 bonus")
for sid, basic, over_h, over_rate, late_ded, perm_ded, absent, ded, net, bonus in rows:
    # recalc: net currently = basic+over_pay - ded (where ded includes late+perm+adv+absent)
    # we need to add 200 bonus
    # over_pay is already in net? Actually net = basic+over_pay+bonus - ded
    # So new net = old net +200
    # Update bonus and net, and deductions stays same
    cur.execute("SELECT over_pay FROM (SELECT overtime_pay as over_pay FROM payroll_table WHERE staff_id=? AND payroll_period='2026-08')", (sid,))
    # simpler: just update
    cur.execute("UPDATE payroll_table SET bonus=200, net_salary = net_salary + 200, updated_at=? WHERE staff_id=? AND payroll_period='2026-08'", (int(__import__('datetime').datetime.now(tz=__import__('datetime').timezone.utc).timestamp()), sid))
    print(f"updated {sid} +200")
con.commit()
# verify
cur.execute("SELECT staff_id, absent_days, bonus, net_salary FROM payroll_table WHERE payroll_period='2026-08' AND absent_days=0 LIMIT 10")
for r in cur.fetchall():
    print(r)
con.close()
print("done")
