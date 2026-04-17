# Carbonyl Agent Browser Runtime — Architecture

## High-Level Architecture

```
                         Consumers
    ┌──────────────┬──────────────┬──────────────┬───────────────┐
    │  matric-test  │   Python     │   Go/Java    │   Dashboard   │
    │  (TypeScript) │   Agents     │   Agents     │   (Web UI)    │
    │              │              │              │               │
    │  gRPC Client │  PyO3 SDK    │  gRPC Client │  WebSocket    │
    └──────┬───────┴──────┬───────┴──────┬───────┴───────┬───────┘
           │              │              │               │
    ═══════╪══════════════╪══════════════╪═══════════════╪════════
           │              │              │               │
    ┌──────▼──────────────▼──────────────▼───────────────▼───────┐
    │                                                             │
    │                   Carbonyl Runtime (Rust)                   │
    │                                                             │
    │  ┌─────────────┐  ┌─────────────┐  ┌───────────────────┐  │
    │  │ Control API  │  │   Watch     │  │   PyO3 Bindings   │  │
    │  │ (gRPC/WS)   │  │   Server    │  │   (in-process)    │  │
    │  │             │  │  (streams)  │  │                   │  │
    │  └──────┬──────┘  └──────┬──────┘  └────────┬──────────┘  │
    │         │                │                   │             │
    │  ┌──────▼────────────────▼───────────────────▼──────────┐  │
    │  │                Session Manager                        │  │
    │  │  ┌──────────┐ ┌──────────┐ ┌───────────────────────┐ │  │
    │  │  │  Pool     │ │ Topology │ │    Hibernation        │ │  │
    │  │  │  Manager  │ │ Manager  │ │    Engine             │ │  │
    │  │  │          │ │          │ │                       │ │  │
    │  │  │ Resource  │ │ Shared/  │ │ Cookie extraction    │ │  │
    │  │  │ ceilings  │ │ isolated │ │ Storage serialization│ │  │
    │  │  │ eviction  │ │ multi-   │ │ State fingerprint    │ │  │
    │  │  │          │ │ agent    │ │ Portable tokens      │ │  │
    │  │  └──────────┘ └──────────┘ └───────────────────────┘ │  │
    │  └──────────────────────┬────────────────────────────────┘  │
    │                         │                                   │
    │  ┌──────────────────────▼────────────────────────────────┐  │
    │  │              Observation Engine                        │  │
    │  │                                                       │  │
    │  │  Fused capture (a11y + screenshot + DOM + net + cons) │  │
    │  │  Delta observations    Streaming events               │  │
    │  │  State fingerprinting  Screencast frames              │  │
    │  └──────────────────────┬────────────────────────────────┘  │
    │                         │                                   │
    │  ┌──────────────────────▼────────────────────────────────┐  │
    │  │               Presence Layer                           │  │
    │  │                                                       │  │
    │  │  Timing humanization   Identity profiles              │  │
    │  │  Mouse trajectories    Fingerprint coherence          │  │
    │  │  Keystroke jitter      Viewport/UA/TZ rotation        │  │
    │  └──────────────────────┬────────────────────────────────┘  │
    │                         │                                   │
    │  ┌──────────────────────▼────────────────────────────────┐  │
    │  │           Existing Carbonyl Core (~3,154 LOC)          │  │
    │  │                                                       │  │
    │  │  Terminal rendering    Input handling                  │  │
    │  │  Quadrant binarizer   ANSI parser                     │  │
    │  │  Frame sync (60fps)   Navigation UI                   │  │
    │  └──────────────────────┬────────────────────────────────┘  │
    │                         │ extern "C" FFI                    │
    └─────────────────────────┼───────────────────────────────────┘
                              │
    ┌─────────────────────────▼───────────────────────────────────┐
    │              Chromium headless_shell                         │
    │                                                             │
    │  Blink    Skia    V8    CDP Server    Network    GPU        │
    └─────────────────────────────────────────────────────────────┘
```

## Component Diagram

```mermaid
C4Context
    title Carbonyl Agent Browser Runtime — Component View

    System_Boundary(consumers, "Consumers") {
        Person(human, "Human Observer", "Watches agent sessions")
        System(matric, "matric-test", "TypeScript test platform")
        System(pyagent, "Python Agent", "LangChain/CrewAI/custom")
        System(other, "Other Agent", "Go/Java/Rust via gRPC")
    }

    System_Boundary(carbonyl, "Carbonyl Runtime (Rust)") {
        Component(ctrl, "Control API", "gRPC + WebSocket", "Sessions, actions, observations")
        Component(watch, "Watch Server", "gRPC stream + WS", "Screencast, terminal, events")
        Component(pyo3, "PyO3 Bindings", "Python native ext", "pip install carbonyl")
        Component(sess, "Session Manager", "Tokio", "Pool, topology, hibernation")
        Component(obs, "Observation Engine", "CDP domains", "Fused capture, deltas, streaming")
        Component(pres, "Presence Layer", "Timing + fingerprint", "Human-like behavior")
        Component(core, "Carbonyl Core", "Terminal I/O", "Rendering, input, frame sync")
    }

    System_Ext(chromium, "Chromium headless_shell", "Browser engine + CDP")
    System_Ext(ffmpeg, "ffmpeg", "Video encoding")
    System_Ext(rtmp, "Restreamer/OBS", "Live streaming")

    Rel(matric, ctrl, "gRPC", "actions, observations")
    Rel(pyagent, pyo3, "Python FFI", "in-process")
    Rel(other, ctrl, "gRPC", "actions, observations")
    Rel(human, watch, "WebSocket", "screencast, terminal, events")

    Rel(ctrl, sess, "manage sessions")
    Rel(pyo3, sess, "manage sessions")
    Rel(sess, obs, "capture state")
    Rel(sess, pres, "apply timing/identity")
    Rel(obs, core, "terminal rendering")
    Rel(obs, chromium, "CDP", "a11y, screenshot, DOM, network")
    Rel(core, chromium, "FFI", "rendering, input")
    Rel(watch, obs, "subscribe to frames/events")
    Rel(watch, ffmpeg, "pipe frames", "screencast → MP4/RTMP")
    Rel(ffmpeg, rtmp, "RTMP/SRT", "live stream")
```

## Sequence Diagrams

### Flow 1: Agent PRAV Cycle (matric-test → Carbonyl)

```mermaid
sequenceDiagram
    participant MT as matric-test<br/>(TypeScript)
    participant API as Control API<br/>(gRPC)
    participant SM as Session<br/>Manager
    participant PL as Presence<br/>Layer
    participant OE as Observation<br/>Engine
    participant CDP as Chromium<br/>(CDP)

    Note over MT,CDP: Session Setup
    MT->>API: CreateSession(viewport, proxy, presence)
    API->>SM: allocate(config)
    SM->>CDP: Target.createBrowserContext()
    SM->>PL: apply identity profile
    PL->>CDP: Network.setUserAgentOverride()
    PL->>CDP: Emulation.setTimezoneOverride()
    SM-->>API: SessionHandle{id, wsEndpoint}
    API-->>MT: session_id

    Note over MT,CDP: PRAV Perceive Phase
    MT->>API: Observe(session_id)
    API->>OE: fused_capture(session_id)
    par Parallel CDP calls
        OE->>CDP: Accessibility.getFullAXTree()
        OE->>CDP: Page.captureScreenshot()
        OE->>CDP: Runtime.evaluate("window.location")
        OE->>CDP: Network.getResponseBodies() [cached]
    end
    OE->>OE: compute state fingerprint
    OE-->>API: Observation{a11y, screenshot, url, console, network, fingerprint}
    API-->>MT: observation

    Note over MT,CDP: PRAV Act Phase (with presence)
    MT->>API: Click(session_id, {role: "button", name: "Submit"})
    API->>PL: humanize_action(click)
    PL->>PL: compute mouse trajectory (Bezier)
    PL->>PL: compute timing delays
    loop Mouse movement points
        PL->>CDP: Input.dispatchMouseEvent(move, x, y)
        PL->>PL: wait(jittered_delay)
    end
    PL->>CDP: Input.dispatchMouseEvent(pressed, x, y)
    PL->>PL: wait(natural_click_duration)
    PL->>CDP: Input.dispatchMouseEvent(released, x, y)
    CDP-->>API: action complete
    API-->>MT: ActionResult{success, durationMs}

    Note over MT,CDP: PRAV Verify Phase
    MT->>API: Observe(session_id)
    API->>OE: fused_capture(session_id)
    OE-->>API: new Observation
    API-->>MT: observation (for assertion evaluation)
```

### Flow 2: Session Hibernation and Restore

```mermaid
sequenceDiagram
    participant Agent as Agent
    participant API as Control API
    participant SM as Session<br/>Manager
    participant HE as Hibernation<br/>Engine
    participant CDP as Chromium<br/>(CDP)
    participant FS as Filesystem

    Note over Agent,FS: Hibernate
    Agent->>API: Hibernate(session_id)
    API->>SM: hibernate(session_id)
    SM->>HE: extract_state(session_id)

    par State extraction via CDP
        HE->>CDP: Network.getAllCookies()
        CDP-->>HE: cookies[]
        HE->>CDP: Runtime.evaluate("Object.entries(localStorage)")
        CDP-->>HE: localStorage{}
        HE->>CDP: Runtime.evaluate("Object.entries(sessionStorage)")
        CDP-->>HE: sessionStorage{}
        HE->>CDP: Target.getTargets()
        CDP-->>HE: open tabs[{url, title}]
        HE->>CDP: Runtime.evaluate("window.scrollY") per tab
        CDP-->>HE: scrollPositions[]
    end

    HE->>HE: serialize to HibernationToken
    HE->>FS: write token.json (portable, no path deps)
    SM->>CDP: Browser.close()
    SM->>SM: release pool slot
    SM-->>API: HibernationToken{id, path}
    API-->>Agent: token

    Note over Agent,FS: Time passes... (minutes, hours, days)
    Note over Agent,FS: Possibly different machine

    Note over Agent,FS: Restore
    Agent->>API: Restore(token)
    API->>SM: restore(token)
    SM->>SM: allocate pool slot
    SM->>CDP: Target.createBrowserContext()

    SM->>HE: inject_state(token, context)
    HE->>FS: read token.json
    HE->>CDP: Network.setCookies(cookies)
    loop Each saved tab
        HE->>CDP: Target.createTarget(url)
        HE->>CDP: Runtime.evaluate("localStorage.setItem(k,v)") per entry
        HE->>CDP: Runtime.evaluate("sessionStorage.setItem(k,v)") per entry
        HE->>CDP: Runtime.evaluate("window.scrollTo(0, savedY)")
    end
    HE->>HE: compute fingerprint, compare with saved
    HE-->>SM: RestoreResult{success, fingerprintMatch}
    SM-->>API: RestoredSession{session_id}
    API-->>Agent: session_id (ready to use)
```

### Flow 3: Unified Streaming (Watch)

```mermaid
sequenceDiagram
    participant Observer as Human Observer<br/>(browser/terminal)
    participant Recorder as Video Recorder<br/>(ffmpeg)
    participant Cast as RTMP Caster<br/>(Restreamer)
    participant WS as Watch Server
    participant OE as Observation<br/>Engine
    participant Core as Carbonyl<br/>Core
    participant CDP as Chromium

    Note over Observer,CDP: Subscribe to streams
    Observer->>WS: WatchSession(session_id, screencast=true, terminal=true, events=true)
    Recorder->>WS: WatchSession(session_id, screencast=true, fps=30, format=png)
    Cast->>WS: WatchSession(session_id, screencast=true, fps=15, format=jpeg)

    WS->>CDP: Page.startScreencast(maxFps=30, jpeg, 1280x720)
    WS->>OE: subscribe_events(session_id)
    WS->>Core: subscribe_terminal(session_id)

    loop Continuous streaming
        CDP-->>WS: Page.screencastFrame(base64 jpeg, metadata)
        WS->>CDP: Page.screencastFrameAck(frameId)

        par Fan-out to subscribers
            WS-->>Observer: WatchFrame{screencast: frame}
            WS-->>Recorder: WatchFrame{screencast: frame}
            WS-->>Cast: WatchFrame{screencast: frame}
        end

        Core-->>WS: terminal ANSI chunk
        WS-->>Observer: WatchFrame{terminal: ansi_data}

        OE-->>WS: BrowserEvent{network_request, xhr POST /api}
        par Fan-out events
            WS-->>Observer: WatchFrame{event: network_request}
            Note over Recorder: events not subscribed
        end
    end

    Note over Cast,CDP: RTMP output path
    Cast->>Cast: screencast frames → ffmpeg -f flv rtmp://restreamer/live/feed

    Note over Observer: Sees: live page + terminal + event timeline
    Note over Recorder: Produces: session-abc.mp4
    Note over Cast: Streams: rtmp://restreamer/live/agent-feed
```

### Flow 4: Multi-Agent Shared Session

```mermaid
sequenceDiagram
    participant A as Agent A<br/>(Explorer)
    participant B as Agent B<br/>(Asserter)
    participant C as Agent C<br/>(Observer)
    participant API as Control API
    participant SM as Session<br/>Manager
    participant TM as Topology<br/>Manager
    participant CDP as Chromium

    Note over A,CDP: Coordinator creates shared session
    A->>API: CreateSession(topology=shared, max_agents=3)
    API->>SM: allocate shared session
    SM->>CDP: Target.createBrowserContext()
    SM-->>API: session_id

    Note over A,CDP: Agents join the session
    A->>API: JoinSession(session_id, role=actor)
    API->>TM: grant(A, actor, session_id)
    TM-->>API: access_token_A

    B->>API: JoinSession(session_id, role=actor)
    API->>TM: grant(B, actor, session_id)
    TM-->>API: access_token_B

    C->>API: JoinSession(session_id, role=observer)
    API->>TM: grant(C, observer, session_id)
    TM-->>API: access_token_C (read-only)

    Note over A,CDP: Agent A acts (acquires lock)
    A->>API: Act(Click, {button: Submit}, token_A)
    API->>TM: acquire_lock(session_id, A)
    TM-->>API: lock granted
    API->>CDP: Input.dispatchMouseEvent(...)
    CDP-->>API: done
    API->>TM: release_lock(session_id, A)
    API-->>A: ActionResult{success}

    Note over B,CDP: Agent B acts (waits for lock)
    B->>API: Act(Type, {input: email, text: "..."}, token_B)
    API->>TM: acquire_lock(session_id, B)
    Note over TM: Lock held by nobody → granted
    TM-->>API: lock granted
    API->>CDP: Input.dispatchKeyEvent(...)
    API-->>B: ActionResult{success}

    Note over C,CDP: Agent C observes (no lock needed)
    C->>API: Observe(session_id, token_C)
    API->>CDP: Accessibility.getFullAXTree()
    CDP-->>API: a11y tree
    API-->>C: Observation (read-only, no lock)

    Note over A,CDP: Agents leave
    A->>API: LeaveSession(session_id, token_A)
    B->>API: LeaveSession(session_id, token_B)
    C->>API: LeaveSession(session_id, token_C)
    API->>TM: revoke all tokens
    API->>SM: session idle → hibernate or destroy
```

### Flow 5: matric-test Backend Normalization

```mermaid
sequenceDiagram
    participant PRAV as PRAV Loop<br/>(matric-test)
    participant MCP as Browser MCP<br/>Server
    participant BE as Backend<br/>Adapter
    participant CB as CarbonylBackend
    participant SB as SteelBackend
    participant BB as BrowserbaseBackend

    Note over PRAV,BB: Same test, any backend
    PRAV->>MCP: navigate("https://example.com")
    MCP->>BE: execute(navigate, url)

    alt Carbonyl backend (selected)
        BE->>CB: navigate(url)
        CB->>CB: gRPC → Carbonyl Control API
        CB-->>BE: {url, title}
    else Steel.dev backend
        BE->>SB: navigate(url)
        SB->>SB: REST → Steel API → CDP
        SB-->>BE: {url, title}
    else Browserbase backend
        BE->>BB: navigate(url)
        BB->>BB: REST → Browserbase API → CDP
        BB-->>BE: {url, title}
    end

    BE-->>MCP: NavigationResult
    MCP-->>PRAV: {url, title}

    Note over PRAV,BB: Observation is also normalized
    PRAV->>MCP: observe()
    MCP->>BE: observe()
    BE->>CB: Observe() via gRPC
    Note over CB: Carbonyl returns FUSED observation<br/>(a11y + screenshot + DOM + network + console)<br/>in one atomic call
    CB-->>BE: FusedObservation
    BE->>BE: normalize to matric-test Observation type
    BE-->>MCP: Observation
    MCP-->>PRAV: Observation{a11y, screenshot, url, console, network, fingerprint}

    Note over PRAV,BB: Targeting stays in matric-test
    PRAV->>PRAV: LLM reasoning (gap analysis)
    PRAV->>PRAV: Locator resolution (ARIA > text > visual)
    PRAV->>PRAV: Action selection from typed action space
    Note over PRAV: All backend-agnostic
```

## Component Responsibilities

| Component | Owns | Does Not Own |
|-----------|------|-------------|
| **Control API** | gRPC/WS endpoints, auth, rate limiting | Business logic — delegates to managers |
| **Watch Server** | Stream multiplexing, fan-out, backpressure | Frame generation — subscribes to sources |
| **Session Manager** | Pool, lifecycle, topology, resource ceilings | Browser internals — uses CDP |
| **Hibernation Engine** | State extraction, serialization, restoration | Cookie/storage format — uses CDP APIs |
| **Observation Engine** | Fused capture, deltas, streaming events | Element targeting — that's matric-test |
| **Presence Layer** | Timing, trajectories, fingerprints, identities | Test logic — transparent to agents |
| **Carbonyl Core** | Terminal rendering, ANSI I/O, frame sync | CDP — separate channel |
| **Chromium** | HTML/CSS/JS, rendering, networking, CDP | Everything above the CDP wire |

## Data Flow Summary

```
Agent request
  → Control API (gRPC/PyO3)
    → Session Manager (routing, access control)
      → Presence Layer (timing humanization)
        → Chromium (CDP execution)
          → Page mutation
        ← CDP events
      ← Raw observation
    ← Fused observation
  ← Typed response

Streaming (parallel):
  Chromium → Screencast frames ──→ Watch Server ──→ Observers
  Chromium → CDP events ─────────→ Watch Server ──→ Agents/Observers
  Carbonyl Core → ANSI output ──→ Watch Server ──→ Terminal viewers
  Watch Server → ffmpeg ─────────→ MP4 file / RTMP stream
```
