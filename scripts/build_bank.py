"""
[INPUT]: 读取 data/raw 中六套练习的原始接口响应。
[OUTPUT]: 生成 data/questions.sqlite、data/questions.md、data/checks.json。
[POS]: scripts 的题库构建器；保留来源记录，仅合并题干及选项一致的题。
[PROTOCOL]: 变更时更新此头部，然后检查 CLAUDE.md
"""

import collections
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import sqlite3


ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
SETS = (564, 558, 548, 530, 529, 528)
IMAGE_URL = "https://tx.jiexunkeji.net/attachment/images/36/2026/05/GHHEne35neG6HZzZHh00g0eEc0v6v3.png"


class SourceHTML(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []

    def handle_starttag(self, tag, attrs):
        if tag in ("p", "br", "li") and self.parts:
            self.parts.append("\n")
        if tag == "img":
            src = dict(attrs).get("src", "")
            if src:
                target = "images/45063-explanation.png" if src == IMAGE_URL else src
                self.parts.append(f"![原题图片]({target})")

    def handle_endtag(self, tag):
        if tag in ("p", "li"):
            self.parts.append("\n")

    def handle_data(self, data):
        self.parts.append(data)


def readable(source):
    parser = SourceHTML()
    parser.feed(str(source or ""))
    return re.sub(r"\n{3,}", "\n\n", "".join(parser.parts)).strip()


def identity(source):
    return re.sub(r"\s+", "", readable(source))


def main():
    sources = []
    titles = {}
    sets = []
    for set_id in SETS:
        payload = json.loads((DATA / "raw" / f"{set_id}.json").read_text())
        assert not payload["errors"] and len(payload["records"]) == payload["expected"]
        sets.append((set_id, payload["heading"], payload["expected"]))
        for row in payload["records"]:
            sources.append((set_id, row))

    groups = collections.OrderedDict()
    for set_id, row in sources:
        options = row["option"]
        title = identity(row["title"])
        key = (int(row["type"]), title, tuple(sorted(identity(value) for value in options.values())))
        groups.setdefault(key, []).append((set_id, row))
        titles.setdefault(title, set()).add(key)

    db_path = DATA / "questions.sqlite"
    db_path.unlink(missing_ok=True)
    db = sqlite3.connect(db_path)
    db.executescript("""
        CREATE TABLE sets (id INTEGER PRIMARY KEY, name TEXT NOT NULL, source_count INTEGER NOT NULL);
        CREATE TABLE questions (
          id TEXT PRIMARY KEY, type INTEGER NOT NULL, stem TEXT NOT NULL,
          options_json TEXT NOT NULL, answer_contents_json TEXT NOT NULL,
          explanation TEXT NOT NULL, answer_conflict INTEGER NOT NULL,
          stem_ambiguous INTEGER NOT NULL
        );
        CREATE TABLE occurrences (
          source_id TEXT PRIMARY KEY, question_id TEXT NOT NULL REFERENCES questions(id),
          set_id INTEGER NOT NULL REFERENCES sets(id), position INTEGER NOT NULL,
          raw_json TEXT NOT NULL
        );
        CREATE INDEX questions_stem ON questions(stem);
        CREATE INDEX occurrences_question ON occurrences(question_id);
    """)
    db.executemany("INSERT INTO sets VALUES (?,?,?)", sets)
    conflicts = []
    ambiguous = []
    markdown = ["# 人工智能训练师三级题库", "", "来源：腾讯教育人工智能训练师六套练习。保留源站原文；原始记录见 `raw/`。", ""]

    for ordinal, (key, occurrences) in enumerate(groups.items(), 1):
        first = occurrences[0][1]
        question_id = first["id"]
        options = {letter: readable(value) for letter, value in first["option"].items()}
        answers = []
        for _, row in occurrences:
            selected = tuple(sorted(identity(row["option"][letter]) for letter in row["correct_answer"]))
            answers.append(selected)
        conflict = len(set(answers)) > 1
        same_stem_different_options = len(titles[key[1]]) > 1
        if conflict:
            conflicts.append([row["id"] for _, row in occurrences])
        if same_stem_different_options:
            ambiguous.append(question_id)
        correct_contents = [options[letter] for letter in first["correct_answer"]]
        db.execute("INSERT INTO questions VALUES (?,?,?,?,?,?,?,?)", (
            question_id, int(first["type"]), readable(first["title"]),
            json.dumps(options, ensure_ascii=False),
            json.dumps(correct_contents, ensure_ascii=False),
            readable(first["parsing"]), int(conflict), int(same_stem_different_options)))
        db.executemany("INSERT INTO occurrences VALUES (?,?,?,?,?)", [
            (row["id"], question_id, set_id, row["index"], json.dumps(row, ensure_ascii=False))
            for set_id, row in occurrences
        ])

        markdown.extend([f"## {ordinal}. {readable(first['title'])}", "", f"题型：{ {1:'单选', 2:'多选', 3:'判断'}[int(first['type'])] }　来源题号：{', '.join(row['id'] for _, row in occurrences)}", ""])
        for label, value in options.items():
            markdown.append(f"- {label}. {value}")
        markdown.extend(["", f"**答案内容：** {'；'.join(correct_contents) if not conflict else '冲突，需核对原始记录'}", ""])
        if same_stem_different_options:
            markdown.extend(["**提示：** 同一题干另有不同选项版本；识别时须核对全部选项。", ""])
        if first["parsing"]:
            markdown.extend(["解析：", "", readable(first["parsing"]), ""])

    db.commit()
    db.close()
    (DATA / "questions.md").write_text("\n".join(markdown) + "\n")
    checks = {
        "source_total": len(sources), "unique_source_ids": len({row["id"] for _, row in sources}),
        "deduplicated_total": len(groups), "removed_exact_duplicates": len(sources) - len(groups),
        "answer_conflicts": conflicts, "same_stem_different_options": ambiguous,
        "set_counts": {str(set_id): count for set_id, _, count in sets},
    }
    (DATA / "checks.json").write_text(json.dumps(checks, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(checks, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
