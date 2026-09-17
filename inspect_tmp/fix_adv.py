import sqlite3, sys
sys.stdout.reconfigure(encoding='utf-8')
con=sqlite3.connect(r'F:\pos_offline_desktop_database.sqlite')
cur=con.cursor()
# fix كريم
print("fix كريم")
cur.execute("DELETE FROM staff_advances WHERE staff_id='STAFF0051' AND amount=610")
print("deleted", cur.rowcount)
# check if STAFF0086 already has 610
cur.execute("SELECT COUNT(*) FROM staff_advances WHERE staff_id='STAFF0086' AND amount=610")
print("STAFF0086 existing", cur.fetchone())
if cur.fetchone() is None:
    pass
# Actually need to fetch after
cur.execute("SELECT COUNT(*) FROM staff_advances WHERE staff_id='STAFF0086' AND amount=610")
cnt=cur.fetchone()[0]
if cnt==0:
    import datetime
    now=int(datetime.datetime.now(tz=datetime.timezone.utc).timestamp())
    cur.execute("INSERT INTO staff_advances (staff_id, amount, reason, request_date, status, approved_by, approved_at, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?)",
                ('STAFF0086', 610, 'سلفة أغسطس', now, 'approved', 'admin', now, now, now))
    print("inserted STAFF0086 610")
else:
    print("already exists")

# add ندى دياب
cur.execute("SELECT COUNT(*) FROM staff_advances WHERE staff_id='STAFF0068' AND amount=300")
cnt=cur.fetchone()[0]
print("STAFF0068 300 existing", cnt)
if cnt==0:
    import datetime
    now=int(datetime.datetime.now(tz=datetime.timezone.utc).timestamp())
    cur.execute("INSERT INTO staff_advances (staff_id, amount, reason, request_date, status, approved_by, approved_at, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?)",
                ('STAFF0068', 300, 'سلفة أغسطس', now, 'approved', 'admin', now, now, now))
    print("inserted STAFF0068 300")

# find بسملة
cur.execute("SELECT staff_id, name FROM staff_table")
rows=cur.fetchall()
for sid,name in rows:
    if 'بسمل' in name or 'بسمة' in name:
        print(f"found بسملة-like {sid} {name}")

# check for بسملة in any
cur.execute("SELECT staff_id, name FROM staff_table WHERE name LIKE '%بسم%'")
print(cur.fetchall())

# try to find بسملة with different encoding: search all
cur.execute("SELECT staff_id, name FROM staff_table")
for sid,name in cur.fetchall():
    if 'ب' in name and 'س' in name and 'م' in name:
        # print candidates
        if 'سمل' in name or 'سمله' in name:
            print(f"candidate {sid} {repr(name)}")

# dedup: for each staff where count>1 with same amount, keep one
cur.execute("SELECT staff_id, amount, COUNT(*) c FROM staff_advances WHERE status='approved' GROUP BY staff_id, amount HAVING c>1")
for sid, amt, c in cur.fetchall():
    print(f"dup {sid} {amt} count {c}")
    # delete duplicates keep one
    cur.execute("SELECT id FROM staff_advances WHERE staff_id=? AND amount=?", (sid, amt))
    ids=[r[0] for r in cur.fetchall()]
    # keep first, delete rest
    for did in ids[1:]:
        cur.execute("DELETE FROM staff_advances WHERE id=?", (did,))
        print(f"deleted dup {did}")

con.commit()
# verify total approved
cur.execute("SELECT staff_id, amount FROM staff_advances WHERE status='approved' ORDER BY staff_id")
for r in cur.fetchall():
    print(r)
print("total approved", cur.execute("SELECT COUNT(*) FROM staff_advances WHERE status='approved'").fetchone())
con.close()
