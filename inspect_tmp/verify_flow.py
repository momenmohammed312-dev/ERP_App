import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
paths = {
    'Downloads': r'G:\flutter\Downloads\pos_offline_desktop_database.sqlite',
    'Documents': r'G:\flutter\Documents\pos_offline_desktop_database.sqlite',
}
for label, path in paths.items():
    import os
    if not os.path.exists(path):
        print(label, 'MISSING')
        continue
    con = sqlite3.connect(path)
    cur = con.cursor()
    cur.execute("PRAGMA user_version")
    uv = cur.fetchone()[0]
    print(f"\n=== {label} {path} user_version={uv} ===")
    # payroll schema
    cur.execute("SELECT sql FROM sqlite_master WHERE name='payroll_table'")
    sql = cur.fetchone()[0]
    print('payroll has late_deduction', 'late_deduction' in sql, 'permission_deduction' in sql)
    # attendance schema
    cur.execute("SELECT sql FROM sqlite_master WHERE name='attendance_table'")
    sql2 = cur.fetchone()[0]
    print('attendance has late_minutes', 'late_minutes' in sql2, 'permission_hours' in sql2)
    # sample staff STAF0052
    cur.execute("SELECT payroll_period, basic_salary, late_hours, late_deduction, permission_hours, permission_deduction, absent_days, net_salary, status FROM payroll_table WHERE staff_id='STAFF0052' AND payroll_period='2026-08'")
    row = cur.fetchone()
    print('STAFF0052 payroll 2026-08:', row)
    # monthly summary
    cur.execute("SELECT late_hours, excused_hours, absent_days FROM monthly_attendance_summary_table WHERE staff_id='STAFF0052' AND period='2026-08'")
    print('monthly summary:', cur.fetchone())
    # attendance counts
    cur.execute("SELECT status, COUNT(*) FROM attendance_table WHERE staff_id='STAFF0052' AND date BETWEEN 1651363200 AND 1664582400 GROUP BY status")
    # need correct timestamp range for Aug 2026: use seconds
    # use actual dates from payroll period: 2026-08-01 to 2026-08-31
    import datetime
    s = int(datetime.datetime(2026,8,1).timestamp())
    e = int(datetime.datetime(2026,8,31,23,59,59).timestamp())
    cur.execute("SELECT status, COUNT(*), SUM(late_minutes), SUM(permission_hours) FROM attendance_table WHERE staff_id='STAFF0052' AND date BETWEEN ? AND ? GROUP BY status", (s,e))
    print('attendance Aug grouped:')
    for r in cur.fetchall():
        print(r)
    con.close()
