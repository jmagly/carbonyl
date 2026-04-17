# Carbonyl Session Model Specification

## Overview

A session is the fundamental unit of browser state in Carbonyl. It encapsulates a Chromium context, its associated tabs, identity bindings, resource limits, and the set of agents currently connected to it. This document specifies session lifecycle, topology variants, hibernation semantics, multi-agent access control, and resource management for pooled deployments.

---

## Session Lifecycle

```
Created → Active → (Hibernated ↔ Active) → Destroyed
                ↘ Error → Destroyed
```

| Transition | Trigger |
|---|---|
| Created → Active | `CreateSession` RPC returns successfully |
| Active → Hibernated | `HibernateSession` RPC, or automatic eviction from a pool |
| Hibernated → Active | `RestoreSession` RPC |
| Active → Error | Chromium crash, resource ceiling exceeded, unrecoverable network failure |
| Error → Destroyed | `DestroySession` RPC, or after configurable error TTL |
| Active → Destroyed | `DestroySession` RPC |
| Hibernated → Destroyed | `DestroySession` RPC |

Sessions in the `Error` state are not automatically destroyed. They are preserved for inspection and can be explicitly destroyed once the error has been logged or investigated.

---

## Topologies

### Isolated (default)

- One Chromium browser context per session
- One agent per session with exclusive access — no lock contention
- Independent cookies, local storage, session storage, and fingerprint from all other sessions
- Tab structure is private to the session
- Use cases: parallel test execution, multi-identity automation, isolated user simulations

### Shared

- One Chromium browser context shared across multiple agents
- Agents connect with explicit roles: **actor** (read + write) or **observer** (read-only)
- Actors must acquire a lock before executing mutations in strict mode (see Locking below)
- Tab assignment: agents can be bound to specific tabs or float across all tabs
- Use cases: multi-agent collaboration on a single browsing context, live monitoring by a second agent while a primary agent drives

### Pooled

- Multiple Chromium browser contexts running on a single Chromium process
- A resource ceiling is enforced across the entire pool, not per-session
- Sessions within the pool compete for resources under the pool limits
- Eviction policy (LRU or priority-based) manages sessions when limits are reached
- Use cases: high-density deployments where per-process overhead is prohibitive

---

## Session Properties

```
id                  string    Unique identifier (UUID v4)
name                string    Optional human-readable slug for persistence
topology            enum      isolated | shared | pooled
status              enum      active | hibernated | error | destroyed
identity            object    Bound presence profile (optional)
resource_limits     object    Per-session memory and CPU caps
connected_agents    list      [{agent_id, role, connected_at}]
tabs                list      [{tab_id, url, title, assigned_agent}]
created_at          int64     Unix microseconds
last_activity_at    int64     Unix microseconds — updated on any action or observation
```

---

## Hibernation

Hibernation serializes recoverable session state into a portable token and terminates the Chromium context. The session can be restored later, on the same machine or a different one.

### What Gets Saved (HibernationToken)

```json
{
  "version": 1,
  "session_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "session_name": "my-session",
  "hibernated_at": "2026-04-03T04:10:00Z",
  "browser_state": {
    "cookies": [
      {
        "name": "session_id",
        "value": "abc123",
        "domain": ".example.com",
        "path": "/",
        "secure": true,
        "http_only": true,
        "same_site": "Lax",
        "expires": 1775001600
      }
    ],
    "local_storage": {
      "https://example.com": {
        "key": "value"
      }
    },
    "session_storage": {
      "https://example.com": {
        "key": "value"
      }
    },
    "tabs": [
      {
        "url": "https://example.com/dashboard",
        "title": "Dashboard",
        "scroll_x": 0,
        "scroll_y": 1200
      }
    ]
  },
  "identity": {
    "user_agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    "viewport": {"width": 1280, "height": 720},
    "timezone": "America/New_York",
    "locale": "en-US"
  },
  "state_fingerprint": "a3f2c8d19e4b76f0123456789abcdef0"
}
```

The token is a self-contained JSON document. It has no filesystem path dependencies and no references to the host machine. Tokens can be stored in any durable store (file, database, object storage).

### What Cannot Survive Hibernation

The following state is inherently volatile and is lost on hibernation. Callers must account for this:

| Lost State | Reason |
|---|---|
| WebSocket connections | Require active TCP; cannot be serialized |
| In-flight HTTP requests | Mid-flight at hibernation time; responses lost |
| JavaScript runtime closures and timers | V8 heap is not serialized |
| Service worker runtime state | SW registration persists; active execution does not |
| Media playback position | Player state is not captured |

These limitations should be documented in agent prompts when hibernation is used mid-task.

### Portability

- Token is portable across machines — restore does not require the originating host
- Token is portable across Chromium versions with best-effort semantics: cookies and storage use standard formats that remain stable across versions; fingerprint injection parameters are version-independent
- If restored on a significantly different Chromium version, certain browser-internal behaviors may differ, but credentials and navigation state will be preserved

---

## Multi-Agent Access Control

### Roles

| Role | Capabilities | Lock Required |
|---|---|---|
| `actor` | Observe + execute actions (click, type, navigate, scroll) | Yes, in strict mode (shared topology) |
| `observer` | Observe only (a11y tree, screenshots, events, delta) | Never |

Observers are always admitted immediately. They cannot be blocked by actor lock contention.

Actors in isolated topology sessions never acquire locks — they are the sole agent by definition.

### Locking (Shared Sessions)

Two locking modes are available. Mode is configured at session creation.

#### Strict Mode

- An actor must call `AcquireLock` (implicitly on first action call, or explicitly) before any mutation
- While one actor holds the lock, all other actors are blocked on mutations
- Lock is released explicitly via `ReleaseLock`, or automatically after the configured timeout (default: 30 seconds)
- Auto-release on timeout prevents deadlocks when an actor crashes or loses connectivity
- Observer access is never blocked regardless of lock state

#### Optimistic Mode

- Actions execute immediately without acquiring a lock
- After each action, the server compares the current state fingerprint against the fingerprint at the time the action was issued
- If fingerprints diverge (another actor mutated state concurrently), a conflict is reported in `ActionResponse`
- The calling agent decides how to handle the conflict (retry, abort, or proceed)
- Use when agents operate on disjoint parts of the page (e.g., different tabs)

#### Tab Assignment (Shared Sessions)

- An actor can be assigned to a specific tab at join time
- Assigned actors only hold the lock for mutations on their assigned tab
- Unassigned actors (floating) compete for the session-level lock

---

## Resource Ceilings (Pooled Sessions)

### Pool-Level Limits

```
max_sessions      int    Maximum number of concurrent active sessions in the pool
max_memory_mb     int    Total memory across all sessions in the pool
max_cpu_percent   float  Total CPU usage across all sessions
```

Pool limits are set in `carbonyl.yaml` under the `pool` configuration key and apply to the entire Carbonyl process.

### Per-Session Limits

```
max_memory_mb   int    Memory cap for this individual session
max_tabs        int    Maximum number of open tabs within this session
```

Per-session limits are set at `CreateSession` time via `ResourceLimits` and cannot be changed while the session is active.

If a session exceeds its per-session `max_memory_mb`, its status transitions to `ERROR` with code `BUDGET_EXHAUSTED`.

### Eviction

When a pool hits its pool-level resource ceiling:

1. The server identifies the least-recently-used active session (by `last_activity_at`)
2. A `EvictionNotice` event is emitted to all agents connected to that session via their WatchService stream
3. After a grace period (default: 5 seconds), the session is automatically hibernated
4. The hibernation token is stored internally and associated with the session ID for later restore
5. If the evicted session has `priority: true` set, it is skipped and the next LRU candidate is evicted instead

Priority sessions are exempt from automatic eviction. Use the priority flag sparingly — a pool where all sessions are high priority is a pool with no eviction policy.

Evicted sessions are hibernated, never destroyed. Their state is recoverable.

### Eviction Notification

```json
{
  "type": "eviction_notice",
  "session_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "reason": "pool_memory_ceiling",
  "grace_period_ms": 5000,
  "evict_at": "2026-04-03T04:15:05Z"
}
```

Agents that receive an eviction notice should complete or checkpoint in-flight work within the grace period.
