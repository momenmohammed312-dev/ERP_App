import sqlite3, datetime, sys
sys.stdout.reconfigure(encoding='utf-8')
DB = r'F:\pos_offline_desktop_database.sqlite'
con=sqlite3.connect(DB)
cur=con.cursor()
# update the 13 corrected payrolls with correct late etc
corrections = {
    'STAFF0016': {'late': 0.75, 'over': 1.0, 'perm': 0, 'absent': 0},
    'STAFF0048': {'late': 17, 'over': 7.5, 'perm': 0, 'absent': 2},
    'STAFF0057': {'late': 13, 'over': 0, 'perm': 4.5, 'absent': 0},
    'STAFF0059': {'late': 0, 'over': 1.0, 'perm': 2, 'absent': 9},
    'STAFF0060': {'late': 5, 'over': 0, 'perm': 0, 'absent': 11},
    'STAFF0063': {'late': 12, 'over': 1.0, 'perm': 0, 'absent': 7},
    'STAFF0076': {'late': 2.5, 'over': 0, 'perm': 1.5, 'absent': 4},
    'STAFF0080': {'late': 5.5, 'over': 0, 'perm': 0, 'absent': 3},
    'STAFF0081': {'late': 2, 'over': 1.5, 'perm': 0, 'absent': 1},
    'STAFF0082': {'late': 16, 'over': 4.5, 'perm': 10, 'absent': 5},
    'STAFF0083': {'late': 4.5, 'over': 0, 'perm': 0, 'absent': 12},
    'STAFF0084': {'late': 0, 'over': 17, 'perm': 0, 'absent': 1},
    'STAFF0087': {'late': 5.5, 'over': 2.5, 'perm': 4.5, 'absent': 10},
}
for sid, vals in corrections.items():
    cur.execute("SELECT basic_salary, hourly_rate FROM staff_table WHERE staff_id=?", (sid,))
    row=cur.fetchone()
    if not row: continue
    basic, hr = row
    hourly=hr if hr else (basic/30/8 if basic else 0)
    late_h=vals['late']; perm_h=vals['perm']; absent_d=vals['absent']; over_h=vals['over']
    late_ded=late_h*hourly*1.5
    perm_ded=perm_h*hourly*1.0
    absent_ded=absent_d*(basic/30) if basic else 0
    over_pay=over_h*hourly*1.5
    cur.execute("SELECT advances FROM payroll_table WHERE staff_id=? AND payroll_period='2026-08'", (sid,))
    adv_row=cur.fetchone()
    advances=adv_row[0] if adv_row else 0
    # bonus 200 if no absent
    bonus=200 if absent_d==0 else 0
    deductions=advances+late_ded+perm_ded+absent_ded
    net=basic+over_pay+bonus - deductions
    cur.execute("UPDATE payroll_table SET late_hours=?, late_deduction=?, permission_hours=?, permission_deduction=?, overtime_hours=?, overtime_pay=?, deductions=?, net_salary=?, bonus=?, updated_at=? WHERE staff_id=? AND payroll_period='2026-08'",
                (late_h, late_ded, perm_h, perm_ded, over_h, over_pay, deductions, net, bonus, int(datetime.datetime.now(tz=datetime.timezone.utc).timestamp()), sid))
    print(f"updated {sid} late {late_h} perm {perm_h} absent {absent_d} over {over_h} net {net:.0f} ded {deductions:.0f}")

# verify
cur.execute("SELECT staff_id, late_hours, permission_hours, absent_days, net_salary FROM payroll_table WHERE payroll_period='2026-08' AND staff_id IN ('STAFF0016','STAFF0048','STAFF0057')")
for r in cur.fetchall():
    print(r)

con.commit()
con.close()
print("done")
