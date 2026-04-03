#!/usr/bin/env python3
from __future__ import annotations
"""
Carbonyl session management.

Manages named Chromium user-data-dir sessions for persistent browser state
(cookies, localStorage, IndexedDB). Supports session creation, forking for
concurrent multi-browser scenarios, snapshot/restore, and live-instance detection.

Session store layout:
    ~/.local/share/carbonyl/sessions/   (or $CARBONYL_SESSION_DIR)
    ├── <name>/
    │   ├── session.json     # metadata
    │   └── profile/         # --user-data-dir passed to Carbonyl/Chromium
    └── <name>.snap.<tag>/   # snapshots (forks with naming convention)

Usage:
    python automation/session.py list
    python automation/session.py create my-session
    python automation/session.py fork my-session my-session-fork
    python automation/session.py snapshot my-session post-login
    python automation/session.py restore my-session post-login
    python automation/session.py destroy my-session
    python automation/session.py info my-session
"""

import argparse
import json
import os
import re
import shutil
import signal
import sys
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Optional


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

_ENV_SESSION_DIR = "CARBONYL_SESSION_DIR"
_DEFAULT_SESSION_DIR = Path.home() / ".local" / "share" / "carbonyl" / "sessions"

# Valid session name: lowercase letters, digits, hyphens. No leading/trailing hyphens.
# Consecutive hyphens (--) are allowed to support snapshot naming (<name>--snap--<tag>).
_SLUG_RE = re.compile(r"^[a-z0-9][a-z0-9\-]*[a-z0-9]$|^[a-z0-9]$")

# Singleton lock file written by Chromium inside user-data-dir
_SINGLETON_LOCK = "SingletonLock"


# ---------------------------------------------------------------------------
# Data model
# ---------------------------------------------------------------------------

@dataclass
class SessionMeta:
    id: str                    # same as name (slug)
    name: str
    created_at: str            # ISO-8601
    tags: list[str] = field(default_factory=list)
    forked_from: Optional[str] = None
    snapshot_of: Optional[str] = None   # set when this IS a snapshot


@dataclass
class Session:
    meta: SessionMeta
    path: Path                 # session directory  (<store>/<name>/)
    profile: Path              # --user-data-dir    (<session>/profile/)


# ---------------------------------------------------------------------------
# SessionManager
# ---------------------------------------------------------------------------

class SessionManager:
    """
    Manage named Carbonyl browser sessions backed by Chromium user-data-dirs.
    """

    def __init__(self, session_dir: Optional[Path] = None) -> None:
        env_dir = os.environ.get(_ENV_SESSION_DIR)
        if session_dir is not None:
            self._root = Path(session_dir)
        elif env_dir:
            self._root = Path(env_dir)
        else:
            self._root = _DEFAULT_SESSION_DIR
        self._root.mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _session_dir(self, name: str) -> Path:
        return self._root / name

    def _profile_dir(self, name: str) -> Path:
        return self._session_dir(name) / "profile"

    def _meta_path(self, name: str) -> Path:
        return self._session_dir(name) / "session.json"

    def _read_meta(self, name: str) -> SessionMeta:
        data = json.loads(self._meta_path(name).read_text())
        return SessionMeta(
            id=data["id"],
            name=data["name"],
            created_at=data["created_at"],
            tags=data.get("tags", []),
            forked_from=data.get("forked_from"),
            snapshot_of=data.get("snapshot_of"),
        )

    def _write_meta(self, meta: SessionMeta) -> None:
        self._meta_path(meta.name).write_text(
            json.dumps(asdict(meta), indent=2) + "\n"
        )

    @staticmethod
    def _slug_ok(name: str) -> bool:
        return bool(_SLUG_RE.match(name))

    def _require_slug(self, name: str) -> None:
        if not self._slug_ok(name):
            raise ValueError(
                f"Invalid session name {name!r}. "
                "Use lowercase letters, digits, and hyphens only."
            )

    def _singleton_lock(self, name: str) -> Path:
        return self._profile_dir(name) / "SingletonLock"

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def exists(self, name: str) -> bool:
        """Return True if a session with this name exists."""
        return self._meta_path(name).is_file()

    def get(self, name: str) -> Session:
        """Return Session for an existing session; raises if not found."""
        if not self.exists(name):
            raise KeyError(f"Session {name!r} does not exist.")
        meta = self._read_meta(name)
        return Session(
            meta=meta,
            path=self._session_dir(name),
            profile=self._profile_dir(name),
        )

    def profile_dir(self, name: str) -> Path:
        """Return the --user-data-dir path for this session (creates dirs)."""
        p = self._profile_dir(name)
        p.mkdir(parents=True, exist_ok=True)
        return p

    def list(self, *, include_snapshots: bool = True) -> list[dict]:
        """Return list of session metadata dicts sorted by created_at."""
        results = []
        for d in sorted(self._root.iterdir()):
            if not d.is_dir():
                continue
            meta_file = d / "session.json"
            if not meta_file.is_file():
                continue
            try:
                data = json.loads(meta_file.read_text())
            except Exception:
                continue
            if not include_snapshots and data.get("snapshot_of"):
                continue
            data["live"] = self.is_live(d.name)
            data["profile"] = str(d / "profile")
            results.append(data)
        return results

    def create(self, name: str, *, tags: Optional[list[str]] = None) -> Path:
        """
        Create a new empty session. Returns the profile directory path.
        Raises if the session already exists.
        """
        self._require_slug(name)
        if self.exists(name):
            raise FileExistsError(f"Session {name!r} already exists.")
        session_dir = self._session_dir(name)
        profile = self._profile_dir(name)
        profile.mkdir(parents=True, exist_ok=True)
        meta = SessionMeta(
            id=name,
            name=name,
            created_at=_iso_now(),
            tags=tags or [],
        )
        self._write_meta(meta)
        return profile

    def destroy(self, name: str, *, force: bool = False) -> None:
        """
        Delete a session and all its data.
        Raises if the session is live unless force=True.
        """
        if not self.exists(name):
            raise KeyError(f"Session {name!r} does not exist.")
        if self.is_live(name) and not force:
            raise RuntimeError(
                f"Session {name!r} has a live browser attached. "
                "Stop the browser or use force=True."
            )
        shutil.rmtree(self._session_dir(name))

    def fork(self, source: str, dest: str) -> Path:
        """
        Create a new session `dest` as a copy of `source`.
        The two sessions evolve independently from this point.
        Returns the profile directory of the new session.
        Raises if source is live (copying a live Chromium profile can corrupt it).
        """
        if not self.exists(source):
            raise KeyError(f"Source session {source!r} does not exist.")
        self._require_slug(dest)
        if self.exists(dest):
            raise FileExistsError(f"Destination session {dest!r} already exists.")
        if self.is_live(source):
            raise RuntimeError(
                f"Session {source!r} has a live browser attached — "
                "cannot safely fork a live profile. Stop the browser first."
            )

        src_profile = self._profile_dir(source)
        dest_session = self._session_dir(dest)
        dest_profile = dest_session / "profile"

        shutil.copytree(src_profile, dest_profile, symlinks=False)

        # Clean stale lock in the copy (the source lock no longer applies)
        lock = dest_profile / _SINGLETON_LOCK
        if lock.exists() or lock.is_symlink():
            lock.unlink(missing_ok=True)

        src_meta = self._read_meta(source)
        dest_meta = SessionMeta(
            id=dest,
            name=dest,
            created_at=_iso_now(),
            tags=list(src_meta.tags),
            forked_from=source,
        )
        self._write_meta(dest_meta)
        return dest_profile

    @staticmethod
    def _snap_name(name: str, tag: str) -> str:
        """Return the canonical snapshot session name: ``<name>--snap--<tag>``."""
        return f"{name}--snap--{tag}"

    def snapshot(self, name: str, tag: str) -> str:
        """
        Create a snapshot of `name` tagged with `tag`.
        Snapshot session name is ``<name>--snap--<tag>``.
        Returns the snapshot session name.
        """
        snap_name = self._snap_name(name, tag)
        self.fork(name, snap_name)
        # Mark as snapshot in meta
        snap_meta = self._read_meta(snap_name)
        snap_meta.snapshot_of = name
        snap_meta.forked_from = name
        self._write_meta(snap_meta)
        return snap_name

    def restore(self, name: str, tag: str) -> Path:
        """
        Restore `name` from snapshot ``<name>--snap--<tag>``.
        The current session profile is REPLACED with the snapshot contents.
        Returns the restored profile directory.
        Raises if either the session or snapshot is live.
        """
        snap_name = self._snap_name(name, tag)
        if not self.exists(snap_name):
            raise KeyError(f"Snapshot {snap_name!r} does not exist.")
        if not self.exists(name):
            raise KeyError(f"Session {name!r} does not exist.")
        if self.is_live(name):
            raise RuntimeError(
                f"Session {name!r} is live — stop the browser before restoring."
            )
        if self.is_live(snap_name):
            raise RuntimeError(
                f"Snapshot {snap_name!r} is live — stop the browser before restoring."
            )

        dest_profile = self._profile_dir(name)
        snap_profile = self._profile_dir(snap_name)

        # Replace profile with snapshot copy
        shutil.rmtree(dest_profile, ignore_errors=True)
        shutil.copytree(snap_profile, dest_profile, symlinks=False)

        # Clean stale lock in restored profile
        lock = dest_profile / _SINGLETON_LOCK
        if lock.exists() or lock.is_symlink():
            lock.unlink(missing_ok=True)

        return dest_profile

    def is_live(self, name: str) -> bool:
        """
        Return True if a live Chromium process is using this session's profile.
        Checks for SingletonLock and verifies the PID is still running.
        """
        lock = self._singleton_lock(name)
        if not (lock.exists() or lock.is_symlink()):
            return False
        return not self._is_stale_lock(lock)

    def clean_stale_lock(self, name: str) -> bool:
        """
        Remove SingletonLock if the owning process is dead.
        Returns True if a stale lock was cleaned, False otherwise.
        """
        lock = self._singleton_lock(name)
        if not (lock.exists() or lock.is_symlink()):
            return False
        if self._is_stale_lock(lock):
            lock.unlink(missing_ok=True)
            return True
        return False

    @staticmethod
    def _is_stale_lock(lock: Path) -> bool:
        """
        Read the SingletonLock symlink (`hostname-pid`) and check if that PID
        is alive on this host. Returns True if the lock is stale (process dead).
        """
        try:
            target = os.readlink(lock)
        except (OSError, ValueError):
            # Not a symlink or unreadable — treat as stale
            return True
        # Format: "<hostname>-<pid>"
        parts = target.rsplit("-", 1)
        if len(parts) != 2:
            return True
        try:
            pid = int(parts[1])
        except ValueError:
            return True
        try:
            os.kill(pid, 0)   # signal 0: check existence without killing
            return False      # process alive
        except ProcessLookupError:
            return True       # process dead → stale lock
        except PermissionError:
            return False      # process alive but owned by different user


# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

def _iso_now() -> str:
    import datetime
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _cmd_list(args: argparse.Namespace, sm: SessionManager) -> None:
    sessions = sm.list(include_snapshots=not args.no_snapshots)
    if not sessions:
        print("No sessions.")
        return
    fmt = "{:<30} {:<24} {:<6} {}"
    print(fmt.format("NAME", "CREATED", "LIVE", "TAGS"))
    print("-" * 80)
    for s in sessions:
        live = "yes" if s.get("live") else "no"
        tags = ", ".join(s.get("tags", []))
        snap = s.get("snapshot_of")
        name = s["name"] + (f"  [snap of {snap}]" if snap else "")
        print(fmt.format(name, s["created_at"][:19], live, tags))


def _cmd_create(args: argparse.Namespace, sm: SessionManager) -> None:
    tags = args.tags.split(",") if args.tags else []
    profile = sm.create(args.name, tags=tags)
    print(f"Created session {args.name!r}")
    print(f"  Profile: {profile}")


def _cmd_destroy(args: argparse.Namespace, sm: SessionManager) -> None:
    sm.destroy(args.name, force=args.force)
    print(f"Destroyed session {args.name!r}")


def _cmd_fork(args: argparse.Namespace, sm: SessionManager) -> None:
    profile = sm.fork(args.source, args.dest)
    print(f"Forked {args.source!r} → {args.dest!r}")
    print(f"  Profile: {profile}")


def _cmd_snapshot(args: argparse.Namespace, sm: SessionManager) -> None:
    snap_name = sm.snapshot(args.name, args.tag)
    print(f"Snapshot created: {snap_name!r}")


def _cmd_restore(args: argparse.Namespace, sm: SessionManager) -> None:
    profile = sm.restore(args.name, args.tag)
    print(f"Restored {args.name!r} from snapshot tag {args.tag!r}")
    print(f"  Profile: {profile}")


def _cmd_info(args: argparse.Namespace, sm: SessionManager) -> None:
    s = sm.get(args.name)
    live = sm.is_live(args.name)
    print(f"Session:    {s.meta.name}")
    print(f"Created:    {s.meta.created_at}")
    print(f"Live:       {'yes' if live else 'no'}")
    print(f"Tags:       {', '.join(s.meta.tags) or '(none)'}")
    if s.meta.forked_from:
        print(f"Forked from: {s.meta.forked_from}")
    if s.meta.snapshot_of:
        print(f"Snapshot of: {s.meta.snapshot_of}")
    print(f"Path:       {s.path}")
    print(f"Profile:    {s.profile}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Carbonyl session manager",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--session-dir",
        metavar="DIR",
        help=f"Session store directory (default: $CARBONYL_SESSION_DIR or {_DEFAULT_SESSION_DIR})",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    # list
    p_list = sub.add_parser("list", aliases=["ls"], help="List sessions")
    p_list.add_argument("--no-snapshots", action="store_true", help="Hide snapshots")

    # create
    p_create = sub.add_parser("create", help="Create a new empty session")
    p_create.add_argument("name", help="Session name (slug)")
    p_create.add_argument("--tags", metavar="TAG1,TAG2", help="Comma-separated tags")

    # destroy
    p_destroy = sub.add_parser("destroy", aliases=["rm"], help="Delete a session")
    p_destroy.add_argument("name")
    p_destroy.add_argument("-f", "--force", action="store_true", help="Force even if live")

    # fork
    p_fork = sub.add_parser("fork", help="Fork a session into a new independent copy")
    p_fork.add_argument("source", help="Source session name")
    p_fork.add_argument("dest", help="Destination session name")

    # snapshot
    p_snap = sub.add_parser("snapshot", aliases=["snap"], help="Snapshot a session")
    p_snap.add_argument("name", help="Session to snapshot")
    p_snap.add_argument("tag", help="Snapshot tag (e.g. post-login)")

    # restore
    p_restore = sub.add_parser("restore", help="Restore a session from a snapshot")
    p_restore.add_argument("name", help="Session to restore")
    p_restore.add_argument("tag", help="Snapshot tag to restore from")

    # info
    p_info = sub.add_parser("info", help="Show session details")
    p_info.add_argument("name")

    args = parser.parse_args()

    sm = SessionManager(
        session_dir=Path(args.session_dir) if args.session_dir else None
    )

    dispatch = {
        "list": _cmd_list,
        "ls": _cmd_list,
        "create": _cmd_create,
        "destroy": _cmd_destroy,
        "rm": _cmd_destroy,
        "fork": _cmd_fork,
        "snapshot": _cmd_snapshot,
        "snap": _cmd_snapshot,
        "restore": _cmd_restore,
        "info": _cmd_info,
    }
    try:
        dispatch[args.cmd](args, sm)
    except (KeyError, FileExistsError, RuntimeError, ValueError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
