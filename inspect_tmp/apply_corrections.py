import sqlite3, datetime, sys
sys.stdout.reconfigure(encoding='utf-8')
DB = r'F:\pos_offline_desktop_database.sqlite'
con=sqlite3.connect(DB)
cur=con.cursor()
# corrections from user
corrections = {
    'STAFF0016': {'late': 0.75, 'over': 1.0, 'perm': 0, 'absent': 0},  # 45 دقيقة =0.75
    'STAFF0048': {'late': 17, 'over': 7.5, 'perm': 0, 'absent': 2},
    'STAFF0057': {'late': 13, 'over': 0, 'perm': 4.5, 'absent': 0},
    'STAFF0059': {'late': 0, 'over': 1.0, 'perm': 2, 'absent': 9},
    'STAFF0060': {'late': 5, 'over': 0, 'perm': 0, 'absent': 11},
    'STAFF0063': {'late': 12, 'over': 1.0, 'perm': 0, 'absent': 7},
    'STAFF0076': {'late': 2.5, 'over': 0, 'perm': 1.5, 'absent': 4},
    'STAFF0080': {'late': 5.5, 'over': 0, 'perm': 0, 'absent': 3},
    'STAFF0081': {'late': 2, 'over': 1.5, 'perm': 0, 'absent': 1},  # سلف 2500 will be handled separately via advances, not here
    'STAFF0082': {'late': 16, 'over': 4.5, 'perm': 10, 'absent': 5},
    'STAFF0083': {'late': 4.5, 'over': 0, 'perm': 0, 'absent': 12},
    'STAFF0084': {'late': 0, 'over': 17, 'perm': 0, 'absent': 1},
    'STAFF0087': {'late': 5.5, 'over': 2.5, 'perm': 4.5, 'absent': 10},
}
# also update advances for STAFF0081 to 2500 (was 300)
# check current advance for STAFF0081
cur.execute("SELECT amount FROM staff_advances WHERE staff_id='STAFF0081' AND status='approved'")
print("STAFF0081 advance before", cur.fetchall())
cur.execute("UPDATE staff_advances SET amount=2500 WHERE staff_id='STAFF0081' AND amount=300")
print("updated STAFF0081", cur.rowcount)
# apply monthly corrections
for sid, vals in corrections.items():
    cur.execute("SELECT * FROM monthly_attendance_summary_table WHERE staff_id=? AND period='2026-08'", (sid,))
    row=cur.fetchone()
    if row:
        cur.execute("UPDATE monthly_attendance_summary_table SET late_hours=?, overtime_hours=?, excused_hours=?, absent_days=?, updated_at=? WHERE staff_id=? AND period='2026-08'",
                    (vals['late'], vals['over'], vals['perm'], vals['absent'], int(datetime.datetime.now(tz=datetime.timezone.utc).timestamp()), sid))
        print(f"updated {sid} late {vals['late']} over {vals['over']} perm {vals['perm']} absent {vals['absent']}")
    else:
        cur.execute("INSERT INTO monthly_attendance_summary_table (staff_id, period, late_hours, overtime_hours, excused_hours, absent_days, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?)",
                    (sid, '2026-08', vals['late'], vals['over'], vals['perm'], vals['absent'], int(datetime.datetime.now(tz=datetime.timezone.utc).timestamp()), int(datetime.datetime.now(tz=datetime.timezone.utc).timestamp())))
        print(f"inserted {sid}")

con.commit()
# now recalc payroll for those with bonus for perfect attendance (0 absent)
# we will delete and recalc for all corrected staff
for sid in corrections.keys():
    cur.execute("DELETE FROM payroll_table WHERE staff_id=? AND payroll_period='2026-08'", (sid,))
print(f"deleted payrolls for corrected staff {cur.rowcount}")
con.commit()
# also need to handle bonus 200 for those with 0 absent
# we will recalc via python logic similar to before but now with corrected monthly
# get staff map
cur.execute("SELECT staff_id, basic_salary, hourly_rate FROM staff_table")
staff_map={r[0]: (r[1], r[2]) for r in cur.fetchall()}
cur.execute("SELECT staff_id, late_hours, overtime_hours, excused_hours, absent_days FROM monthly_attendance_summary_table WHERE period='2026-08'")
monthly={r[0]: r[1:] for r in cur.fetchall()}
cur.execute("SELECT staff_id, SUM(CASE WHEN status IN ('approved','paid') THEN COALESCE(monthly_deduction, amount) ELSE 0 END) FROM staff_advances GROUP BY staff_id")
adv_map=dict(cur.fetchall())
# recalc for corrected staff
period_start=int(datetime.datetime(2026,8,1,tzinfo=datetime.timezone.utc).timestamp())
period_end=int(datetime.datetime(2026,8,31,23,59,59,tzinfo=datetime.timezone.utc).timestamp())
now=int(datetime.datetime.now(tz=datetime.timezone.utc).timestamp())
for sid in corrections.keys():
    if sid not in staff_map:
        continue
    basic, hr = staff_map[sid]
    m_late, m_over, m_perm, m_abs = monthly.get(sid, (0,0,0,0))
    m_late=m_late or 0; m_over=m_over or 0; m_perm=m_perm or 0; m_abs=m_abs or 0
    hourly=hr if hr else (basic/30/8 if basic else 0)
    late_ded=m_late*hourly*1.5
    perm_ded=m_perm*hourly*1.0
    absent_ded=m_abs*(basic/30) if basic else 0
    over_pay=m_over*hourly*1.5
    advances=adv_map.get(sid,0) or 0
    # bonus 200 if no absent
    bonus=200 if m_abs==0 else 0
    deductions=advances+late_ded+perm_ded+absent_ded
    net=basic+over_pay+bonus - deductions
    cur.execute("INSERT INTO payroll_table (staff_id, payroll_period, period_start, period_end, basic_salary, overtime_hours, overtime_rate, overtime_pay, allowances, deductions, advances, taxes, insurance, other_deductions, net_salary, working_days, present_days, absent_days, leave_days, status, bonus, penalties_total, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (sid, '2026-08', period_start, period_end, basic, m_over, hourly*1.5, over_pay, 0, deductions, advances, 0,0,0, net, 26, 31-m_abs, m_abs, 0, 'calculated', bonus, 0, now, now))
    print(f"{sid} net {net:.0f} late {m_late} perm {m_perm} absent {m_abs} over {m_over} bonus {bonus}")

con.commit()
# verify
cur.execute("SELECT staff_id, late_hours, permission_hours, absent_days, net_salary FROM payroll_table WHERE payroll_period='2026-08' AND staff_id IN ('STAFF0016','STAFF0048','STAFF0057')")
for r in cur.fetchall():
    print(r)
con.close()
print("DONE corrections applied")
