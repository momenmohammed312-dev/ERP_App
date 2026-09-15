import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
for path in [r'G:\flutter\Downloads\pos_offline_desktop_database.sqlite', r'G:\flutter\Documents\pos_offline_desktop_database.sqlite', r'G:\flutter\Documents\pos_vegetable.sqlite']:
    import os
    if not os.path.exists(path):
        print(path, 'NOT FOUND')
        continue
    con = sqlite3.connect(path)
    cur = con.cursor()
    cur.execute("PRAGMA user_version")
    print(path, 'user_version', cur.fetchone()[0])
    cur.execute("SELECT sql FROM sqlite_master WHERE name='payroll_table'")
    row = cur.fetchone()
    if row:
        sql = row[0]
        print('has late_hours', 'late_hours' in sql, 'permission_hours' in sql)
        print(sql[sql.find('expense_ref_id'):sql.find('expense_ref_id')+300])
    cur.execute("SELECT sql FROM sqlite_master WHERE name='attendance_table'")
    row = cur.fetchone()
    if row:
        sql=row[0]
        print('attendance has late_minutes', 'late_minutes' in sql)
    con.close()
