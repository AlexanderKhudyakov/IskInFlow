#!/usr/bin/env python3
"""tracker-dashboard — local read-only web dashboard over the host task tracker.

Visualizes Tasks/ (host task tracker, format per guides/task_tracker.md)
enriched with execution progress from .task-locks/ lock files: the pipeline
stage ladder (guides/pipeline.md), history timeline, objectives and review/QA
round counts. Never mutates the tracker, the locks or anything else.

Usage:
  python3 IskInFlow/scripts/tracker-dashboard.py [--port 8765]
                                                 [--tasks-dir PATH]
                                                 [--no-open]

Tasks directory resolution (first hit wins):
  1. --tasks-dir PATH
  2. TASKS_DIR env (same convention as the Tasks/*.sh shims)
  3. <host-root>/Tasks — sibling of this nested IskInFlow clone
  4. nearest Tasks/ directory found upward from the cwd

A missing or empty Tasks/ is a valid state: the page renders a placeholder.

Endpoints:
  /                  the dashboard page (tracker-dashboard.html, same dir)
  /api/tasks         overview JSON for every task (lightweight)
  /api/task/<id>     detail JSON: lock history, objectives, comments, checklist
"""

import argparse
import datetime as dt
import json
import os
import re
import sys
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent

# Gate-stage ladder (flow's GATE_STAGES order) collapsed into progress
# milestones; SKIPPED/conditional variants count as their passed counterpart.
STAGE_ALIASES = {
    "MERGED_AND_ARCHIVED": "MERGED",
    "MERGED_TO_MAIN": "MERGED",
    "QA_VERIFIED": "QA_PASSED",
    "QA_COMPLETE": "QA_PASSED",
    "IMPLEMENTATION_IN_PROGRESS": "IMPLEMENTATION_STARTED",
}
MILESTONES = [
    ("impl-start", {"IMPLEMENTATION_STARTED"}, 15),
    ("impl-done", {"IMPLEMENTATION_COMPLETE"}, 40),
    ("review-pass", {"CODE_REVIEW_APPROVED", "CODE_REVIEW_SKIPPED"}, 60),
    ("qa-pass", {"QA_PASSED", "QA_CONDITIONAL_PASS", "QA_SKIPPED"}, 75),
    ("reflection", {"REFLECTION_COMPLETE"}, 85),
    ("merged", {"MERGED"}, 92),
]
TERMINAL_STATUSES = {"done", "cancelled"}

STATUS_LABELS = {
    "draft": "Черновик",
    "open": "Открыта",
    "in-progress": "В работе",
    "blocked": "Заблокирована",
    "review": "На приёмке",
    "done": "Выполнена",
    "cancelled": "Отменена",
}


# ---------------------------------------------------------------------------
# Minimal frontmatter parser (the task.md schema subset; stdlib has no yaml)
# ---------------------------------------------------------------------------

def _unquote(value):
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "'\"":
        inner = value[1:-1]
        if value[0] == "'":
            return inner.replace("''", "'")
        try:
            return json.loads(value)
        except ValueError:
            return inner
    return value


def _scalar(value):
    raw = value.strip()
    if raw.startswith("[") and raw.endswith("]"):
        body = raw[1:-1].strip()
        if not body:
            return []
        return [_scalar(item) for item in body.split(",")]
    if re.fullmatch(r"-?\d+", raw):
        return int(raw)
    if raw in ("true", "false"):
        return raw == "true"
    return _unquote(raw)


def parse_frontmatter(text):
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    fm = {}
    i = 1
    while i < len(lines):
        line = lines[i]
        if line.strip() == "---":
            break
        if not line.strip() or line.lstrip().startswith("#") or line.startswith((" ", "\t")):
            i += 1
            continue
        m = re.match(r"^([A-Za-z][\w-]*):\s*(.*)$", line)
        if not m:
            i += 1
            continue
        key, val = m.group(1), m.group(2).strip()
        if val:
            fm[key] = _scalar(val)
            i += 1
            continue
        # Empty value: block list (`- item`) or nested map (env:) follows.
        items, sub, j = [], {}, i + 1
        while j < len(lines):
            l2 = lines[j]
            if l2.strip() == "---":
                break
            li = re.match(r"^\s+-\s+(.*)$", l2)
            km = re.match(r"^\s+([A-Za-z][\w-]*):\s*(.*)$", l2)
            if li:
                items.append(_scalar(li.group(1)))
            elif km:
                sub[km.group(1)] = _unquote(km.group(2)) if km.group(2).strip() else None
            else:
                break
            j += 1
        if items:
            fm[key] = items
        elif sub:
            fm[key] = sub
        else:
            fm[key] = None
        i = j
    return fm


# ---------------------------------------------------------------------------
# Data collection
# ---------------------------------------------------------------------------

def resolve_tasks_dir(explicit):
    if explicit:
        return Path(explicit).resolve()
    if os.environ.get("TASKS_DIR"):
        return Path(os.environ["TASKS_DIR"]).resolve()
    host_root = SCRIPT_DIR.parent.parent  # nested clone: <host>/IskInFlow/scripts
    candidate = host_root / "Tasks"
    if candidate.is_dir():
        return candidate
    cwd = Path.cwd().resolve()
    for node in [cwd, *cwd.parents]:
        if (node / "Tasks").is_dir():
            return node / "Tasks"
    return candidate  # missing — placeholder state


def load_lock_index(locks_root):
    """Map int task id -> parsed lock, scanning active and completed dirs."""
    index = {}
    if not locks_root.is_dir():
        return index
    for path in sorted(list(locks_root.glob("*.lock.json"))
                       + list((locks_root / "completed").glob("*.lock.json"))):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            continue
        task_id = str(data.get("taskId") or path.stem)
        m = re.match(r"^(\d+)", task_id)
        if not m:
            continue
        index[int(m.group(1))] = {
            "path": path,
            "data": data,
            "completedDir": (locks_root / "completed") in path.parents,
        }
    return index


def _parse_ts(value):
    if not value:
        return None
    try:
        return dt.datetime.fromisoformat(value)
    except ValueError:
        return None


def _milestone_stage(lock):
    """Highest milestone ever reached (history + current workStage)."""
    seen = set()
    for entry in lock.get("history") or []:
        stage = entry.get("toStage")
        if stage:
            seen.add(STAGE_ALIASES.get(stage, stage))
    stage = lock.get("workStage")
    if stage:
        seen.add(STAGE_ALIASES.get(stage, stage))
    reached = None
    for name, stages, _pct in MILESTONES:
        if seen & stages:
            reached = name
    return reached, seen


def _lock_progress(lock):
    reached, _seen = _milestone_stage(lock)
    if reached is None:
        return None
    for name, _stages, pct in MILESTONES:
        if name == reached:
            return pct
    return None


def compute_progress(status, lock):
    """(percent|None, label) — None means 'not counted' (cancelled)."""
    if status == "done":
        return 100, "Выполнена"
    if status == "cancelled":
        return None, "Отменена"
    if status == "review":
        return 95, "Слита · ожидает приёмки"
    lock_pct = _lock_progress(lock) if lock else None
    if status == "blocked":
        return (max(lock_pct, 5) if lock_pct is not None else 5), "Заблокирована"
    if status == "in-progress":
        if lock_pct is None:
            return 5, "В работе · без лока"
        return lock_pct, None  # label filled from the stage by the caller
    return 0, {"draft": "Черновик", "open": "Готова к взятию"}.get(status)


def _objective_text(item):
    if isinstance(item, str):
        return item
    if isinstance(item, dict):
        for key in ("objective", "text", "title", "description", "name"):
            if item.get(key):
                return str(item[key])
        return json.dumps(item, ensure_ascii=False)
    return str(item)


def _split_body(raw):
    return raw.split("---", 2)[2] if raw.startswith("---") else raw


def extract_description(body):
    m = re.search(r"^##\s+Описание\s*$(.*?)(?=^##\s|\Z)", body, re.M | re.S)
    if not m:
        return ""
    lines = [l.strip() for l in m.group(1).splitlines() if l.strip()]
    text = " ".join(lines)
    text = re.sub(r"<!--.*?-->", "", text, flags=re.S)
    text = re.sub(r"[*_`#\[\]]", "", text)
    return text.strip()[:400]


def extract_checklist(body):
    items, section = [], ""
    for line in body.splitlines():
        hm = re.match(r"^##\s+(.*)$", line)
        if hm:
            section = hm.group(1).strip()
            continue
        cm = re.match(r"^\s*[-*]\s+\[( |x|X)\]\s+(.*)$", line)
        if cm:
            items.append({"section": section, "done": cm.group(1).lower() == "x",
                          "text": cm.group(2).strip()})
    return items


def load_comments(task_dir):
    result = []
    cdir = task_dir / "comments"
    if cdir.is_dir():
        for path in sorted(cdir.glob("*.md")):
            raw = path.read_text(encoding="utf-8", errors="replace")
            fm = parse_frontmatter(raw)
            body = _split_body(raw).strip()
            result.append({
                "file": path.name,
                "author": fm.get("author"),
                "date": fm.get("date"),
                "kind": fm.get("kind") or "comment",
                "excerpt": re.sub(r"[*_`#\[\]]", "", body)[:300],
            })
    return result


def _rounds(lock, stage):
    return sum(1 for h in lock.get("history") or [] if h.get("toStage") == stage)


def build_task_entry(task_dir, fm, lock_rec):
    status = fm.get("status") or "draft"
    lock = lock_rec["data"] if lock_rec else None
    pct, label = compute_progress(status, lock)
    if label is None and lock:  # in-progress with a lock: label from the stage
        label = STAGE_ALIASES.get(lock.get("workStage"), lock.get("workStage")) or "В работе"

    def _ids(value):
        return [int(v) for v in (value or []) if str(v).lstrip("-").isdigit()]

    raw = (task_dir / "task.md").read_text(encoding="utf-8", errors="replace")
    body = _split_body(raw)
    checklist = extract_checklist(body)
    obj_done = len((lock or {}).get("workState", {}).get("completedObjectives") or [])
    obj_total = obj_done + len((lock or {}).get("workState", {}).get("pendingObjectives") or [])
    locked_at = _parse_ts((lock or {}).get("lockedAt"))
    completed_at = _parse_ts((lock or {}).get("completedAt"))
    duration_h = None
    if locked_at and completed_at:
        duration_h = round((completed_at - locked_at).total_seconds() / 3600, 1)
    num = re.match(r"(\d+)", task_dir.name).group(1)
    return {
        "id": int(fm.get("id") or num),
        "num": num,
        "folder": task_dir.name,
        "title": str(fm.get("title") or task_dir.name),
        "type": fm.get("type"),
        "status": status,
        "statusLabel": STATUS_LABELS.get(status, status),
        "priority": fm.get("priority") or "P2",
        "created": fm.get("created"),
        "updated": fm.get("updated"),
        "closed": fm.get("closed"),
        "resolution": fm.get("resolution"),
        "assignee": fm.get("assignee"),
        "tags": fm.get("tags") or [],
        "blockedBy": _ids(fm.get("blocked-by")),
        "relatesTo": _ids(fm.get("relates-to")),
        "branch": fm.get("branch"),
        "lock": fm.get("lock"),
        "spec": fm.get("spec"),
        "progress": pct,
        "progressLabel": label,
        "lockStage": (STAGE_ALIASES.get(lock.get("workStage"), lock.get("workStage"))
                      if lock else None),
        "lockStatus": (lock or {}).get("status"),
        "reviewRounds": _rounds(lock or {}, "CODE_REVIEW_REQUESTED"),
        "qaRounds": _rounds(lock or {}, "QA_REQUESTED"),
        "objectivesDone": obj_done,
        "objectivesTotal": obj_total,
        "checklistDone": sum(1 for c in checklist if c["done"]),
        "checklistTotal": len(checklist),
        "commentsCount": len(load_comments(task_dir)),
        "lockedAt": (lock or {}).get("lockedAt"),
        "completedAt": (lock or {}).get("completedAt"),
        "durationHours": duration_h,
        "implementedBy": (lock or {}).get("implementedBy"),
        "reviewedBy": (lock or {}).get("reviewedBy"),
        "qaBy": (lock or {}).get("qaBy"),
    }


def collect(tasks_dir):
    task_dirs = []
    if tasks_dir.is_dir():
        task_dirs = sorted(
            d for d in tasks_dir.iterdir()
            if d.is_dir() and re.match(r"^\d{4}-", d.name) and (d / "task.md").is_file()
        )
    locks_root = tasks_dir.parent / ".task-locks"
    lock_index = load_lock_index(locks_root)
    entries = []
    for d in task_dirs:
        try:
            fm = parse_frontmatter((d / "task.md").read_text(encoding="utf-8", errors="replace"))
            num = re.match(r"(\d+)", d.name).group(1)
            lock_rec = lock_index.get(int(fm.get("id") or num))
            entries.append(build_task_entry(d, fm, lock_rec))
        except (OSError, ValueError, AttributeError) as exc:
            print(f"warn: {d.name}: {exc}", file=sys.stderr)
            continue
    by_id = {e["id"]: e for e in entries}
    for e in entries:  # open tasks whose blockers have all closed
        blockers = [by_id[b] for b in e["blockedBy"] if b in by_id]
        e["readyToStart"] = bool(
            blockers and e["status"] in ("open", "draft")
            and all(b["status"] in TERMINAL_STATUSES for b in blockers)
        )
    return {
        "project": tasks_dir.parent.name,
        "tasksDir": str(tasks_dir),
        "locksDir": str(locks_root),
        "hasTasks": bool(entries),
        "generatedAt": dt.datetime.now(dt.timezone.utc).astimezone().isoformat(timespec="seconds"),
        "tasks": entries,
    }


def collect_detail(tasks_dir, task_id):
    if not tasks_dir.is_dir():
        return None
    for d in sorted(tasks_dir.iterdir()):
        if not (d.is_dir() and re.match(r"^\d{4}-", d.name) and (d / "task.md").is_file()):
            continue
        raw = (d / "task.md").read_text(encoding="utf-8", errors="replace")
        fm = parse_frontmatter(raw)
        num = re.match(r"(\d+)", d.name).group(1)
        if int(fm.get("id") or num) != task_id:
            continue
        lock_rec = load_lock_index(tasks_dir.parent / ".task-locks").get(task_id)
        entry = build_task_entry(d, fm, lock_rec)
        lock = lock_rec["data"] if lock_rec else None
        history = [{
            "ts": h.get("timestamp"),
            "from": h.get("fromStage"),
            "to": STAGE_ALIASES.get(h.get("toStage"), h.get("toStage")),
            "agent": h.get("agentId"),
            "reason": h.get("reason"),
        } for h in ((lock or {}).get("history") or [])]
        objectives = {
            "completed": [_objective_text(o) for o in (lock or {}).get("workState", {}).get("completedObjectives") or []],
            "pending": [_objective_text(o) for o in (lock or {}).get("workState", {}).get("pendingObjectives") or []],
        }
        lookup = {t["id"]: t for t in collect(tasks_dir)["tasks"]}
        slim = {t["id"]: {k: t[k] for k in ("id", "num", "title", "status", "statusLabel")}
                for t in lookup.values()}
        blockers = [slim[b] for b in entry["blockedBy"] if b in slim]
        blocking = [slim[t["id"]] for t in lookup.values() if entry["id"] in t["blockedBy"]]
        related = [slim[r] for r in entry["relatesTo"] if r in slim]
        return {
            **entry,
            "description": extract_description(_split_body(raw)),
            "checklist": extract_checklist(_split_body(raw)),
            "comments": load_comments(d),
            "lockPath": str(lock_rec["path"]) if lock_rec else None,
            "history": history,
            "objectives": objectives,
            "blockers": blockers,
            "blocking": blocking,
            "related": related,
        }
    return None


# ---------------------------------------------------------------------------
# HTTP server
# ---------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    tasks_dir = None

    def log_message(self, *args):
        pass

    def _send(self, code, body, ctype):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path in ("/", "/index.html"):
            try:
                page = (SCRIPT_DIR / "tracker-dashboard.html").read_bytes()
            except OSError:
                return self._send(500, b"tracker-dashboard.html not found next to the script",
                                  "text/plain; charset=utf-8")
            return self._send(200, page, "text/html; charset=utf-8")
        if path == "/api/tasks":
            try:
                data = collect(self.tasks_dir)
            except Exception as exc:  # noqa: BLE001 — surface scan failures as 500
                return self._send(500, json.dumps({"error": str(exc)}).encode(),
                                  "application/json; charset=utf-8")
            return self._send(200, json.dumps(data, ensure_ascii=False).encode(),
                              "application/json; charset=utf-8")
        m = re.fullmatch(r"/api/task/(\d+)", path)
        if m:
            detail = collect_detail(self.tasks_dir, int(m.group(1)))
            if detail is None:
                return self._send(404, b'{"error": "task not found"}',
                                  "application/json; charset=utf-8")
            return self._send(200, json.dumps(detail, ensure_ascii=False).encode(),
                              "application/json; charset=utf-8")
        if path == "/favicon.ico":
            return self._send(204, b"", "text/plain")
        return self._send(404, b"not found", "text/plain; charset=utf-8")


def main():
    ap = argparse.ArgumentParser(description="IskInFlow task tracker dashboard (read-only)")
    ap.add_argument("--port", type=int, default=8765)
    ap.add_argument("--tasks-dir", default=None,
                    help="Tasks/ directory (default: host root next to the nested clone)")
    ap.add_argument("--no-open", action="store_true", help="do not open the browser")
    args = ap.parse_args()

    tasks_dir = resolve_tasks_dir(args.tasks_dir)
    Handler.tasks_dir = tasks_dir
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    url = f"http://127.0.0.1:{args.port}/"
    print(f"tracker-dashboard: {url}")
    n = len(collect(tasks_dir)["tasks"]) if tasks_dir.is_dir() else 0
    print(f"  tasks dir: {tasks_dir} ({n} tasks)")
    print("  Ctrl+C to stop")
    if not args.no_open:
        threading.Timer(0.4, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nbye")


if __name__ == "__main__":
    main()
