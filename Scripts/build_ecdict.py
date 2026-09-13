"""Convert the pinned upstream ECDICT CSV to a read-only app SQLite resource.

Usage: python3 Scripts/build_ecdict.py INPUT.csv OUTPUT.sqlite
Only Python standard-library modules are required.
"""
import csv
import hashlib
import sqlite3
import sys
from pathlib import Path

source, destination = map(Path, sys.argv[1:])
if destination.exists():
    raise SystemExit("Output already exists; choose a new output path.")
destination.parent.mkdir(parents=True, exist_ok=True)
db = sqlite3.connect(destination)
db.execute("CREATE TABLE words (word TEXT PRIMARY KEY COLLATE NOCASE, phonetic TEXT NOT NULL, english TEXT NOT NULL, chinese TEXT NOT NULL) WITHOUT ROWID")
csv.field_size_limit(10_000_000)
with source.open(encoding="utf-8-sig", newline="") as stream:
    reader = csv.DictReader(stream)
    assert {"word", "phonetic", "definition", "translation"} <= set(reader.fieldnames)
    for row in reader:
        word = row["word"].strip().lower()
        english = row["definition"].replace("\\n", "\n").strip()
        chinese = row["translation"].replace("\\n", "\n").strip()
        if word and (english or chinese):
            db.execute("INSERT OR IGNORE INTO words VALUES (?, ?, ?, ?)", (word, row["phonetic"].strip(), english, chinese))
db.execute("CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
db.executemany("INSERT INTO metadata VALUES (?, ?)", [
    ("source", "https://github.com/skywind3000/ECDICT"),
    ("revision", "bc015ed2e24a7abef49fc6dbbb7fe32c1dadaf8b"),
    ("csv_sha256", hashlib.sha256(source.read_bytes()).hexdigest()),
])
db.execute("PRAGMA user_version = 1")
db.commit()
assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
print(f"Converted {db.execute('SELECT COUNT(*) FROM words').fetchone()[0]:,} words; {destination.stat().st_size / 1024**2:.1f} MiB")
db.close()
