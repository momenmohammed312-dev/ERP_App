import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
con=sqlite3.connect(r'F:\pos_offline_desktop_database.sqlite')
cur=con.cursor()
for q in ["SELECT staff_id, name FROM staff_table WHERE name LIKE '%بسملة%'",
          "SELECT staff_id, name FROM staff_table WHERE name LIKE '%بسمله%'",
          "SELECT staff_id, name FROM staff_table WHERE name LIKE '%ندى%'",
          "SELECT staff_id, name FROM staff_table WHERE name LIKE '%ندا%'",
          "SELECT staff_id, name FROM staff_table WHERE name LIKE '%كريم%'"]:
    try:
        cur.execute(q)
        print(q, cur.fetchall())
    except Exception as e:
        print("err", e)
con.close()
