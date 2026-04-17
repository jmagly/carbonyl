# Carbonyl Control API Specification

## Overview

The Carbonyl Control API is the primary integration surface for all consumers. It exposes browser session lifecycle management, action execution, multi-channel observation, and live session streaming over a set of typed RPC services.

---

## Transport

### gRPC (primary)

- Protocol: protobuf over HTTP/2
- Default port: `9515`
- All services defined in `carbonyl.v1` package
- Strongly typed; generated clients available for Go, Python, TypeScript, and Rust

### WebSocket (dashboard/streaming)

- Protocol: JSON messages over WebSocket
- Default port: `9516`
- Used for dashboard UIs and streaming consumers that cannot use gRPC
- WatchService frames are serialized as newline-delimited JSON
- Connect path: `ws://host:9516/watch/{session_id}`

### Unix Socket (legacy compatibility)

- Path: `/var/run/carbonyl/daemon.sock` (configurable)
- Preserves the existing `daemon.py` wire protocol during transition
- Read-only compatibility shim — new features are gRPC-only
- Will be removed after two minor version deprecation window

---

## Authentication

- API key passed via gRPC metadata header: `x-carbonyl-api-key`
- WebSocket equivalent: `X-Carbonyl-Api-Key` HTTP header on upgrade request
- Authentication is **disabled by default** for local development (loopback interface)
- Authentication is **required** when the server binds to any non-localhost address
- Keys are configured in `carbonyl.yaml` or via the `CARBONYL_API_KEY` environment variable
- Invalid or missing key returns gRPC status `UNAUTHENTICATED` (HTTP 401 equivalent)

---

## Services

### SessionService

Manages the full lifecycle of browser sessions.

```protobuf
service SessionService {
  rpc CreateSession(CreateSessionRequest)   returns (CreateSessionResponse);
  rpc DestroySession(DestroySessionRequest) returns (DestroySessionResponse);
  rpc ListSessions(ListSessionsRequest)     returns (ListSessionsResponse);
  rpc HealthCheck(HealthCheckRequest)       returns (HealthCheckResponse);
  rpc JoinSession(JoinSessionRequest)       returns (JoinSessionResponse);
  rpc LeaveSession(LeaveSessionRequest)     returns (LeaveSessionResponse);
  rpc HibernateSession(HibernateRequest)    returns (HibernateResponse);
  rpc RestoreSession(RestoreRequest)        returns (RestoreResponse);
}
```

#### Message Types

##### CreateSessionRequest

```protobuf
message CreateSessionRequest {
  Viewport         viewport         = 1;  // Required. Width and height in pixels.
  ProxyConfig      proxy            = 2;  // Optional. Outbound proxy configuration.
  PresenceProfile  presence_profile = 3;  // Optional. Timing preset and identity config.
  Topology         topology         = 4;  // Optional. Default: ISOLATED.
  int32            max_agents       = 5;  // Shared topology only. Max concurrent agents.
  ResourceLimits   resource_limits  = 6;  // Optional. Memory and CPU caps.
  string           named_session    = 7;  // Optional. Slug for persistence and restore.
}

message Viewport {
  int32 width  = 1;
  int32 height = 2;
}

message ProxyConfig {
  string server   = 1;  // e.g. "http://proxy.example.com:8080"
  string username = 2;
  string password = 3;
}

message PresenceProfile {
  TimingPreset timing_preset  = 1;  // FAST | NATURAL | DELIBERATE | INSTANT
  string       identity_name  = 2;  // Named identity profile to bind, e.g. "residential-us"
}

enum TimingPreset {
  TIMING_PRESET_UNSPECIFIED = 0;
  FAST                      = 1;
  NATURAL                   = 2;
  DELIBERATE                = 3;
  INSTANT                   = 4;  // No humanization. Testing only.
}

enum Topology {
  TOPOLOGY_UNSPECIFIED = 0;
  ISOLATED             = 1;  // Default. One agent, one context.
  SHARED               = 2;  // Multiple agents, one context.
  POOLED               = 3;  // Multiple contexts on shared Chromium process.
}

message ResourceLimits {
  int32 max_memory_mb    = 1;
  float max_cpu_percent  = 2;
}
```

##### CreateSessionResponse

```protobuf
message CreateSessionResponse {
  string      session_id   = 1;
  string      access_token = 2;  // Required for actor role in shared sessions.
  SessionInfo session      = 3;
}
```

##### SessionInfo

```protobuf
message SessionInfo {
  string        id               = 1;
  SessionStatus status           = 2;
  int64         created_at       = 3;  // Unix microseconds.
  Topology      topology         = 4;
  int32         connected_agents = 5;
  ResourceUsage resource_usage   = 6;
  string        current_url      = 7;
}

enum SessionStatus {
  SESSION_STATUS_UNSPECIFIED = 0;
  ACTIVE                     = 1;
  HIBERNATED                 = 2;
  ERROR                      = 3;
  DESTROYED                  = 4;
}

message ResourceUsage {
  int32 memory_mb    = 1;
  float cpu_percent  = 2;
}
```

##### DestroySessionRequest / DestroySessionResponse

```protobuf
message DestroySessionRequest {
  string session_id = 1;
}

message DestroySessionResponse {
  bool success = 1;
}
```

##### ListSessionsRequest / ListSessionsResponse

```protobuf
message ListSessionsRequest {
  // All fields optional. Omit for full list.
  SessionStatus filter_status   = 1;
  Topology      filter_topology = 2;
}

message ListSessionsResponse {
  repeated SessionInfo sessions = 1;
}
```

##### HealthCheckRequest / HealthCheckResponse

```protobuf
message HealthCheckRequest {}

message HealthCheckResponse {
  bool   healthy   = 1;
  string version   = 2;  // Carbonyl server version.
  int32  uptime_s  = 3;
}
```

##### JoinSessionRequest / JoinSessionResponse

```protobuf
message JoinSessionRequest {
  string    session_id = 1;
  AgentRole role       = 2;  // ACTOR | OBSERVER
  string    agent_id   = 3;  // Caller-assigned identifier for tracing.
}

enum AgentRole {
  AGENT_ROLE_UNSPECIFIED = 0;
  ACTOR                  = 1;  // Read + write. Requires lock in shared sessions.
  OBSERVER               = 2;  // Read-only. No lock needed.
}

message JoinSessionResponse {
  string access_token = 1;  // Include in subsequent action requests.
}
```

##### LeaveSessionRequest / LeaveSessionResponse

```protobuf
message LeaveSessionRequest {
  string session_id   = 1;
  string access_token = 2;
}

message LeaveSessionResponse {
  bool success = 1;
}
```

##### HibernateRequest / HibernateResponse

```protobuf
message HibernateRequest {
  string session_id = 1;
}

message HibernateResponse {
  bool   success          = 1;
  string hibernation_token = 2;  // Opaque JSON blob. Store for restore.
}
```

##### RestoreRequest / RestoreResponse

```protobuf
message RestoreRequest {
  string hibernation_token = 1;
  string named_session     = 2;  // Optional override for restored session name.
}

message RestoreResponse {
  string      session_id = 1;
  SessionInfo session    = 2;
}
```

---

### ActionService

Executes browser mutations within a session.

```protobuf
service ActionService {
  rpc Navigate(NavigateRequest)           returns (NavigateResponse);
  rpc Click(ClickRequest)                 returns (ActionResponse);
  rpc Type(TypeRequest)                   returns (ActionResponse);
  rpc PressKey(PressKeyRequest)           returns (ActionResponse);
  rpc Scroll(ScrollRequest)               returns (ActionResponse);
  rpc Hover(HoverRequest)                 returns (ActionResponse);
  rpc SelectOption(SelectOptionRequest)   returns (ActionResponse);
  rpc WaitForSelector(WaitRequest)        returns (WaitResponse);
  rpc WaitForNavigation(WaitRequest)      returns (WaitResponse);
  rpc NewTab(NewTabRequest)               returns (TabResponse);
  rpc CloseTab(CloseTabRequest)           returns (TabResponse);
  rpc SwitchTab(SwitchTabRequest)         returns (TabResponse);
  rpc ListTabs(ListTabsRequest)           returns (ListTabsResponse);
}
```

#### Common Fields

All action requests include:

```protobuf
// Included in every action request via field reuse.
string session_id   = 1;  // Required.
string access_token = 2;  // Required for actor role in shared sessions.
```

#### LocatorSpec

Element targeting uses a priority hierarchy: ARIA role + accessible name (primary), text content match (secondary), visual description (tertiary). Callers should populate fields in priority order and let the server resolve.

```protobuf
message LocatorSpec {
  string role               = 1;  // ARIA role, e.g. "button", "textbox"
  string name               = 2;  // Accessible name (aria-label, label, placeholder)
  string text               = 3;  // Visible text content match
  string visual_description = 4;  // Natural language description for vision fallback
}
```

#### Message Types

##### NavigateRequest / NavigateResponse

```protobuf
message NavigateRequest {
  string session_id   = 1;
  string access_token = 2;
  string url          = 3;
  int32  timeout_ms   = 4;  // Default: 30000
}

message NavigateResponse {
  bool   success      = 1;
  string final_url    = 2;  // After any redirects.
  int32  duration_ms  = 3;
  string error        = 4;
}
```

##### ClickRequest / ActionResponse

```protobuf
message ClickRequest {
  string      session_id   = 1;
  string      access_token = 2;
  LocatorSpec locator      = 3;
  int32       timeout_ms   = 4;  // Default: 5000
}

message ActionResponse {
  bool   success        = 1;
  int32  duration_ms    = 2;
  string error          = 3;  // Populated only on failure.
  bool   state_changed  = 4;  // True if DOM state fingerprint changed post-action.
}
```

##### TypeRequest

```protobuf
message TypeRequest {
  string      session_id   = 1;
  string      access_token = 2;
  LocatorSpec locator      = 3;
  string      text         = 4;
  bool        clear_first  = 5;  // Clear existing value before typing.
}
```

##### PressKeyRequest

```protobuf
message PressKeyRequest {
  string session_id   = 1;
  string access_token = 2;
  string key          = 3;  // Key name, e.g. "Enter", "Tab", "ArrowDown"
  string modifiers    = 4;  // Comma-separated: "Control", "Shift", "Alt"
}
```

##### ScrollRequest

```protobuf
message ScrollRequest {
  string      session_id   = 1;
  string      access_token = 2;
  LocatorSpec locator      = 3;  // Optional. Scrolls viewport if omitted.
  int32       delta_x      = 4;  // Pixels.
  int32       delta_y      = 5;
}
```

##### HoverRequest

```protobuf
message HoverRequest {
  string      session_id   = 1;
  string      access_token = 2;
  LocatorSpec locator      = 3;
}
```

##### SelectOptionRequest

```protobuf
message SelectOptionRequest {
  string      session_id   = 1;
  string      access_token = 2;
  LocatorSpec locator      = 3;
  string      value        = 4;  // Option value attribute.
  string      label        = 5;  // Option visible text (alternative to value).
}
```

##### WaitRequest / WaitResponse

```protobuf
message WaitRequest {
  string      session_id   = 1;
  string      access_token = 2;
  LocatorSpec locator      = 3;  // WaitForSelector only.
  int32       timeout_ms   = 4;  // Default: 30000
}

message WaitResponse {
  bool   success      = 1;
  int32  duration_ms  = 2;
  string error        = 3;
}
```

##### Tab Management

```protobuf
message NewTabRequest {
  string session_id   = 1;
  string access_token = 2;
  string url          = 3;  // Optional. Opens blank tab if omitted.
}

message CloseTabRequest {
  string session_id   = 1;
  string access_token = 2;
  string tab_id       = 3;
}

message SwitchTabRequest {
  string session_id   = 1;
  string access_token = 2;
  string tab_id       = 3;
}

message ListTabsRequest {
  string session_id = 1;
}

message TabResponse {
  bool    success = 1;
  TabInfo tab     = 2;
  string  error   = 3;
}

message ListTabsResponse {
  repeated TabInfo tabs = 1;
}

message TabInfo {
  string tab_id         = 1;
  string url            = 2;
  string title          = 3;
  bool   active         = 4;
  string assigned_agent = 5;  // Shared sessions only.
}
```

---

### ObservationService

Reads current browser state without mutations.

```protobuf
service ObservationService {
  rpc Observe(ObserveRequest)                     returns (Observation);
  rpc ObserveDelta(DeltaRequest)                  returns (DeltaObservation);
  rpc Screenshot(ScreenshotRequest)               returns (ScreenshotResponse);
  rpc GetAccessibilityTree(A11yRequest)            returns (A11yResponse);
  rpc FindText(FindTextRequest)                   returns (FindTextResponse);
}
```

#### Message Types

##### ObserveRequest / Observation (fused)

```protobuf
message ObserveRequest {
  string session_id        = 1;
  bool   include_screenshot = 2;  // Default: true
  bool   include_a11y_tree  = 3;  // Default: true
  bool   include_network    = 4;  // Default: false (high volume)
  bool   include_terminal   = 5;  // Default: false
}

message Observation {
  string              accessibility_tree = 1;  // Serialized a11y tree (JSON)
  bytes               screenshot         = 2;
  string              screenshot_format  = 3;  // "png" | "jpeg"
  string              url                = 4;
  string              title              = 5;
  repeated string     console_messages   = 6;
  repeated string     network_requests   = 7;  // Recent request URLs.
  string              state_fingerprint  = 8;  // Hash of observable DOM state.
  int64               timestamp_us       = 9;
  string              terminal_text      = 10; // Terminal output if session has terminal.
}
```

##### DeltaRequest / DeltaObservation

```protobuf
message DeltaRequest {
  string session_id          = 1;
  string baseline_fingerprint = 2;  // Compare against this prior fingerprint.
}

message DeltaObservation {
  bool            state_changed        = 1;
  repeated string new_console_messages = 2;
  repeated string new_network_requests = 3;
  repeated string dom_mutations        = 4;  // Human-readable mutation summaries.
  bool            fingerprint_changed  = 5;
  string          new_fingerprint      = 6;
}
```

##### ScreenshotRequest / ScreenshotResponse

```protobuf
message ScreenshotRequest {
  string session_id = 1;
  string format     = 2;  // "png" | "jpeg". Default: "png"
  int32  quality    = 3;  // JPEG only. 0-100. Default: 85
  int32  max_width  = 4;  // Optional scaling. Preserves aspect ratio.
  int32  max_height = 5;
}

message ScreenshotResponse {
  bytes  data      = 1;
  string format    = 2;
  int32  width     = 3;
  int32  height    = 4;
  int64  timestamp_us = 5;
}
```

##### A11yRequest / A11yResponse

```protobuf
message A11yRequest {
  string session_id    = 1;
  bool   include_hidden = 2;  // Default: false
}

message A11yResponse {
  string tree_json     = 1;  // Full serialized accessibility tree.
  int64  timestamp_us  = 2;
}
```

##### FindTextRequest / FindTextResponse

```protobuf
message FindTextRequest {
  string session_id = 1;
  string query      = 2;
  bool   exact      = 3;  // Default: false (substring match)
}

message FindTextResponse {
  repeated TextMatch matches = 1;
}

message TextMatch {
  string text       = 1;  // Matched text content.
  string role       = 2;  // ARIA role of the matching element.
  string name       = 3;  // Accessible name.
  string selector   = 4;  // CSS selector path (informational).
}
```

---

### WatchService

Streams live session frames for dashboards, monitoring, and real-time replay.

```protobuf
service WatchService {
  rpc WatchSession(WatchRequest) returns (stream WatchFrame);
}
```

#### Message Types

##### WatchRequest

```protobuf
message WatchRequest {
  string session_id        = 1;
  bool   include_screencast = 2;  // Stream video frames. Default: false
  bool   include_terminal   = 3;  // Stream terminal output. Default: false
  bool   include_events     = 4;  // Stream browser events. Default: true
  int32  screencast_fps     = 5;  // Default: 5
  string screencast_format  = 6;  // "jpeg" | "png". Default: "jpeg"
  int32  screencast_quality = 7;  // JPEG only. Default: 70
  int32  max_width          = 8;  // Optional downscale. Preserves aspect ratio.
  int32  max_height         = 9;
}
```

##### WatchFrame

```protobuf
message WatchFrame {
  int64 timestamp_us = 1;
  oneof payload {
    ScreencastFrame screencast = 2;
    TerminalFrame   terminal   = 3;
    BrowserEvent    event      = 4;
    AgentAction     action     = 5;
  }
}

message ScreencastFrame {
  bytes  data   = 1;
  string format = 2;
  int32  width  = 3;
  int32  height = 4;
}

message TerminalFrame {
  string text = 1;  // Incremental terminal output since last frame.
}

message BrowserEvent {
  string type    = 1;  // "navigation", "console", "network", "error"
  string payload = 2;  // JSON-encoded event details.
}

message AgentAction {
  string agent_id    = 1;
  string action_type = 2;  // "click", "type", "navigate", etc.
  string summary     = 3;  // Human-readable action description.
}
```

---

## Error Codes

All errors are returned as gRPC status codes with a detail message. Application-level error codes are included in the status detail.

| Code | gRPC Status | Description |
|---|---|---|
| `SESSION_NOT_FOUND` | `NOT_FOUND` | No session exists with the given ID. |
| `SESSION_BUSY` | `RESOURCE_EXHAUSTED` | Exclusive lock is held by another actor. Retry after lock timeout. |
| `BUDGET_EXHAUSTED` | `RESOURCE_EXHAUSTED` | Session hit its memory or CPU resource ceiling. |
| `ELEMENT_NOT_FOUND` | `NOT_FOUND` | Locator did not match any element within the timeout window. |
| `NAVIGATION_FAILED` | `ABORTED` | Navigation did not reach a stable state (network error, timeout, crash). |
| `TIMEOUT` | `DEADLINE_EXCEEDED` | Operation did not complete within the specified or default timeout. |
| `UNAUTHORIZED` | `UNAUTHENTICATED` | Missing or invalid API key. |
| `RATE_LIMITED` | `RESOURCE_EXHAUSTED` | Too many requests from caller. Back off and retry. |

---

## Versioning

- Package name encodes the API version: `carbonyl.v1.SessionService`
- Breaking changes (field removal, semantic changes, enum removal) require a new major version (`carbonyl.v2`)
- Additive changes (new fields, new RPCs, new enum values) are non-breaking and released within the current version
- Deprecation policy: two minor version releases of advance notice before removal
- Deprecated fields are annotated in proto source with `[deprecated = true]` and documented in the changelog
- Clients are expected to ignore unknown fields (standard protobuf forward-compatibility rule)
