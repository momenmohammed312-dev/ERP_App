import sqlite3, re, datetime, sys
sys.stdout.reconfigure(encoding='utf-8')
DB = r'F:\pos_offline_desktop_database.sqlite'
adv_list = [
    ("اسراء", 950),
    ("عمر احمد", 1800),
    ("اميره", 3500),
    ("احمد خليفه", 2900),
    ("كريم", 610),
    ("على محمد", 250),
    ("جومانه", 3000),
    ("احمد عاطف", 1000),
    ("محمد السادات", 3000),
    ("هبه", 3000),
    ("شهد عبد السلام", 2500),
    ("سالم", 1000),
    ("حبيبه على", 100),
    ("رضوى", 2700),
    ("ياسمين", 1000),
    ("ام سالم", 700),
    ("بسمله", 500),
    ("شهد", 4000),
    ("مهره", 700),
    ("مارينا", 300),
    ("ندى دياب", 300),
    ("دنيا خميس", 2500),
    ("عبد الله", 100),
    ("احمد ناجى", 680),
    ("شهد وائل", 500),
    ("احمد عبد الكريم", 600),
    ("ام تمارا", 300),
]

def norm(s):
    s=str(s).strip()
    s=re.sub(r'[إأآا]','ا',s)
    s=re.sub(r'ى','ي',s)
    s=re.sub(r'ة','ه',s)
    s=re.sub(r'\s+','',s)
    return s

con=sqlite3.connect(DB)
cur=con.cursor()
cur.execute("SELECT staff_id, name FROM staff_table")
rows=cur.fetchall()
by_norm={}
for sid,name in rows:
    by_norm.setdefault(norm(name), []).append((sid,name))
# also add mapping for short names like "كريم" -> "كريم مصطفى"
# for those, try contains
def resolve(name):
    k=norm(name)
    # exact
    if k in by_norm:
        cands=by_norm[k]
        if len(cands)==1:
            return cands[0][0]
        # if multiple, pick first active or first
        return cands[0][0]
    # try contains: find staff where norm(name) contains k or vice versa
    for key, cands in by_norm.items():
        if k in key or key in k:
            # if name is substring
            if len(cands)==1:
                return cands[0][0]
    # try manual mapping for short names
    manual = {
        norm("كريم"): "كريم مصطفى",
        norm("على محمد"): "علي محمد",
        norm("جومانه"): "جومانا",
        norm("هبه"): "هبه ام محمود",
        norm("سالم"): "سالم",
        norm("حبيبه على"): "حبيبه علي",
        norm("بسمله"): "بسملة",
        norm("شهد"): "شهد",
        norm("مهره"): "مهره",
        norm("عبد الله"): "عبد الله محمد",
        norm("ام تمارا"): "ام تمارا",
    }
    if k in manual:
        target = norm(manual[k])
        if target in by_norm:
            return by_norm[target][0][0]
    return None

# check each
for name, amt in adv_list:
    sid = resolve(name)
    if not sid:
        # try fallback: search by contains
        found=None
        for key, cands in by_norm.items():
            if norm(name) in key:
                found=cands[0][0]
                break
        sid=found
    print(f"{name} -> {sid} {cur.execute('SELECT name FROM staff_table WHERE staff_id=?',(sid,)).fetchone() if sid else 'NOT FOUND'} amount {amt}")

# now insert
# first clear existing advances for those staff where status pending/approved for 2026-08? Just insert new with approved
now = int(datetime.datetime.now(tz=datetime.timezone.utc).timestamp())
# Use transaction
con.execute("BEGIN")
inserted=0
for name, amt in adv_list:
    sid = resolve(name)
    if not sid:
        # try manual resolve again
        # for "كريم" we need to find "كريم مصطفى"
        if norm(name)=="كريم":
            cur.execute("SELECT staff_id FROM staff_table WHERE name LIKE '%كريم%'")
            r=cur.fetchone()
            sid=r[0] if r else None
        if not sid:
            print(f"SKIP {name} not found")
            continue
    # delete existing pending for same staff to avoid duplicate
    cur.execute("DELETE FROM staff_advances WHERE staff_id=? AND amount=? AND status='pending'", (sid, amt))
    # insert approved
    cur.execute("INSERT INTO staff_advances (staff_id, amount, reason, request_date, status, approved_by, approved_at, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?)",
                (sid, amt, 'سلفة أغسطس', now, 'approved', 'admin', now, now, now))
    inserted+=1
    print(f"inserted {sid} {name} {amt}")

con.commit()
print(f"inserted {inserted} advances")
# verify
cur.execute("SELECT staff_id, amount, status FROM staff_advances WHERE status='approved' ORDER BY amount DESC LIMIT 10")
for r in cur.fetchall():
    print(r)
con.close()
print("DONE")
