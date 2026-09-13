"""Extract WordNet 3.0 quoted usage examples, without inventing sentences.

python3 Scripts/build_examples.py wordnet.zip output-directory
Outputs a SQLite resource and the unmodified database license.
"""
import hashlib
import re
import sqlite3
import sys
import zipfile
from pathlib import Path

archive, output = map(Path, sys.argv[1:])
output.mkdir(parents=True, exist_ok=True)
target = output / "examples.sqlite"
if target.exists():
    raise SystemExit("Output exists. Choose a new output directory.")
db = sqlite3.connect(target)
db.execute("CREATE TABLE examples (word TEXT PRIMARY KEY COLLATE NOCASE, sentence TEXT NOT NULL) WITHOUT ROWID")
with zipfile.ZipFile(archive) as corpus:
    license_text = corpus.read("wordnet/LICENSE").decode()
    (output / "WordNet-LICENSE.txt").write_text(license_text)
    for category in ("noun", "verb", "adj", "adv"):
        for line in corpus.read(f"wordnet/data.{category}").decode().splitlines():
            if not line or not line[0].isdigit() or " | " not in line:
                continue
            data, gloss = line.split(" | ", 1)
            fields = data.split()
            lemmas = [re.sub(r"\((?:a|p|ip)\)$", "", fields[4 + i * 2]).lower()
                      for i in range(int(fields[3], 16))]
            for word in lemmas:
                if not re.fullmatch(r"[a-z]+(?:[-'][a-z]+)*", word):
                    continue
                for sentence in re.findall(r'"([^"\n]+)"', gloss):
                    # A synset's example may only demonstrate a different synonym.
                    if len(sentence.split()) >= 3 and re.search(r"(?<![a-z])" + re.escape(word) + r"(?![a-z])", sentence, re.I):
                        db.execute("INSERT OR IGNORE INTO examples VALUES (?, ?)", (word, sentence))
                        break
    db.execute("CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
    db.executemany("INSERT INTO metadata VALUES (?, ?)", [
        ("source", "https://raw.githubusercontent.com/nltk/nltk_data/gh-pages/packages/corpora/wordnet.zip"),
        ("sha256", hashlib.sha256(archive.read_bytes()).hexdigest()),
        ("license", license_text),
    ])
db.commit()
assert db.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
print(f"Extracted {db.execute('SELECT count(*) FROM examples').fetchone()[0]:,} word examples; {target.stat().st_size / 1024**2:.2f} MiB")
db.close()
