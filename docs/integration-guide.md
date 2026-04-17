# Carbonyl Integration Guide — Connecting Consumers

Guide for external consumers who want to use Carbonyl as their browser runtime.

---

## Overview

Carbonyl exposes two integration modes:

| Mode | When to use |
|------|------------|
| **In-process (Python)** | Python-based consumers; lowest latency; single-machine |
| **Networked (any language)** | Polyglot consumers; distributed systems; sidecar or cloud deployments |

The networked mode speaks gRPC (primary) and WebSocket (streaming/dashboard use cases). The gRPC API is the canonical interface — the Python SDK is a thin PyO3 wrapper over the same session model.

---

## Python SDK (PyO3 — in-process)

### Installation

```bash
pip install carbonyl
carbonyl install   # downloads Chromium runtime (~200MB, one-time)
```

The `carbonyl install` step pulls the pre-built Chromium runtime for your platform. It only needs to run once per environment.

### Basic usage

```python
import asyncio
from carbonyl import Carbonyl, PresenceProfile

async def main():
    runtime = Carbonyl()

    # Create an isolated session
    session = await runtime.create_session(
        viewport=(1280, 720),
        presence=PresenceProfile.natural(),
    )

    # Navigate
    await session.navigate("https://example.com")

    # Observe (fused multi-channel)
    obs = await session.observe()
    print(obs.url)
    print(obs.accessibility_tree)
    print(f"Screenshot: {len(obs.screenshot)} bytes")

    # Act
    await session.click(role="button", name="Submit")
    await session.type(role="textbox", name="Email", text="user@example.com")

    # Hibernate the session (portable snapshot)
    token = await session.hibernate()
    token.export_to_file("my-session.json")

    # ... later, even on a different machine ...
    token = HibernationToken.from_file("my-session.json")
    restored = await runtime.restore_session(token)

    await restored.close()

asyncio.run(main())
```

### Shared session (multi-agent)

Multiple agents can join a single shared session. Actors hold a write lock per action; observers never block.

```python
async def multi_agent():
    runtime = Carbonyl()

    session = await runtime.create_session(topology="shared", max_agents=3)

    # Agent A joins as actor (read + write)
    agent_a = await session.join(role="actor")

    # Agent B joins as observer (read-only, no lock needed)
    agent_b = await session.join(role="observer")

    # A navigates, B watches
    await agent_a.navigate("https://example.com")
    obs = await agent_b.observe()

    await agent_a.leave()
    await agent_b.leave()
```

See `docs/session-model.md` for the full shared session topology and locking semantics.

### Streaming

Use `session.watch()` to receive a continuous stream of screencast frames and DOM events. Useful for feeding a vision model in real time or driving a live dashboard.

```python
async def stream_session():
    runtime = Carbonyl()
    session = await runtime.create_session()
    await session.navigate("https://example.com")

    async for frame in session.watch(screencast=True, events=True, fps=5):
        if frame.type == "screencast":
            # Feed JPEG bytes to a vision model
            pass
        elif frame.type == "event":
            print(f"{frame.timestamp}: {frame.event_type}")
```

---

## gRPC Client (TypeScript / matric-test)

### Setup

Generate TypeScript types from the protobuf definitions:

```bash
npx grpc_tools_node_protoc \
  --ts_out=./src/generated \
  --grpc_out=./src/generated \
  --proto_path=./proto \
  carbonyl/v1/*.proto
```

### Basic usage

```typescript
import {
  SessionServiceClient,
  ActionServiceClient,
  ObservationServiceClient,
} from './generated/carbonyl/v1';

const sessions = new SessionServiceClient(
  'localhost:9515',
  grpc.credentials.createInsecure(),
);
const actions = new ActionServiceClient(
  'localhost:9515',
  grpc.credentials.createInsecure(),
);
const observations = new ObservationServiceClient(
  'localhost:9515',
  grpc.credentials.createInsecure(),
);

// Create session
const { sessionId } = await sessions.createSession({
  viewport: { width: 1280, height: 720 },
  presenceProfile: { timingPreset: 'natural' },
});

// Navigate
await actions.navigate({ sessionId, url: 'https://example.com' });

// Observe
const observation = await observations.observe({ sessionId });
console.log(observation.url);
console.log(observation.accessibilityTree);
```

### CarbonylBackend for matric-test

Implements the `BrowserBackend` interface from `@matric-test/browser-mcp`. Drop this in as a replacement for the Steel.dev or Browserbase backends.

```typescript
import type { BrowserBackend, BrowserConfig, BrowserSession } from '@matric-test/browser-mcp';

export class CarbonylBackend implements BrowserBackend {
  private client: SessionServiceClient;

  constructor(endpoint: string = 'localhost:9515') {
    this.client = new SessionServiceClient(
      endpoint,
      grpc.credentials.createInsecure(),
    );
  }

  async createSession(config: BrowserConfig): Promise<BrowserSession> {
    const response = await this.client.createSession({
      viewport: config.viewport,
      proxy: config.proxy,
      presenceProfile: { timingPreset: 'natural' },
    });
    return {
      id: response.sessionId,
      wsEndpoint: response.cdpEndpoint, // CDP WebSocket for Playwright
      status: 'active',
    };
  }

  async destroySession(sessionId: string): Promise<void> {
    await this.client.destroySession({ sessionId });
  }

  async healthCheck(sessionId: string): Promise<boolean> {
    const { healthy } = await this.client.healthCheck({ sessionId });
    return healthy;
  }
}
```

`cdpEndpoint` is the Chrome DevTools Protocol WebSocket URL. Playwright can attach to it directly via `browser.connectOverCDP(wsEndpoint)`.

---

## gRPC Client (Go)

```go
conn, _ := grpc.Dial("localhost:9515", grpc.WithInsecure())
defer conn.Close()

client := pb.NewSessionServiceClient(conn)

resp, _ := client.CreateSession(ctx, &pb.CreateSessionRequest{
    Viewport: &pb.Viewport{Width: 1280, Height: 720},
})
sessionID := resp.SessionId
```

---

## gRPC Client (Python — networked alternative to PyO3)

Use this when you want a networked connection to a remote Carbonyl instance rather than loading the library in-process.

```python
import grpc
from carbonyl.v1 import session_pb2_grpc, session_pb2

channel = grpc.aio.insecure_channel('localhost:9515')
sessions = session_pb2_grpc.SessionServiceStub(channel)

response = await sessions.CreateSession(session_pb2.CreateSessionRequest(
    viewport=session_pb2.Viewport(width=1280, height=720),
))
session_id = response.session_id
```

---

## Docker

Run Carbonyl as a standalone service and connect from any language.

```bash
# Run Carbonyl as a service
docker run -d -p 9515:9515 -p 9516:9516 carbonyl/runtime
```

| Port | Protocol | Purpose |
|------|----------|---------|
| 9515 | gRPC | Session, action, observation APIs |
| 9516 | WebSocket / HTTP | Watch stream, dashboard |

Verify the service is up:

```bash
grpcurl -plaintext localhost:9515 carbonyl.v1.SessionService/ListSessions
```

---

## Watch / Stream (WebSocket)

The WebSocket endpoint at port 9516 delivers a real-time stream of JPEG screencast frames and DOM events. Designed for browser dashboards and monitoring UIs.

```javascript
const ws = new WebSocket('ws://localhost:9516/watch/session-abc');

ws.onmessage = (event) => {
  const frame = JSON.parse(event.data);

  if (frame.type === 'screencast') {
    // Render JPEG frame to a canvas element
    const img = new Image();
    img.src = `data:image/jpeg;base64,${frame.data}`;
    canvas.getContext('2d').drawImage(img, 0, 0);
  }
};
```

Frame types:

| `frame.type` | Contents |
|-------------|---------|
| `screencast` | Base64-encoded JPEG, `frame.data` |
| `event` | DOM or network event, `frame.event_type` + `frame.timestamp` |

---

## RTMP / SRT Casting

Cast a live session to a streaming server for recording or broadcast. Useful for piping agent activity into OBS, Restreamer, or any RTMP-compatible ingest.

```bash
# Cast to Restreamer via RTMP
carbonyl cast session-abc --rtmp rtmp://restreamer.local/live/agent-feed

# Cast to OBS via SRT
carbonyl cast session-abc --srt srt://obs-host:9000
```

---

## LangChain Tool Integration

Wrap a Carbonyl session as a LangChain tool to give an LLM agent browsing capability with clean text output.

```python
from langchain.tools import Tool
from carbonyl import Carbonyl

runtime = Carbonyl()

async def browse(url: str) -> str:
    session = await runtime.create_session()
    await session.navigate(url)
    obs = await session.observe()
    await session.close()
    return obs.terminal_text  # clean text suitable for LLM consumption

browse_tool = Tool(
    name="browse",
    description="Navigate to a URL and return the page content as plain text",
    func=browse,
)
```

`obs.terminal_text` strips JavaScript, navigation chrome, and styling — returning only the readable content as rendered in the terminal. For vision-model consumption, use `obs.screenshot` (raw JPEG bytes) instead.

---

## Reference

- `docs/api-specification.md` — Full gRPC service and message definitions
- `docs/session-model.md` — Session lifecycle, hibernation, shared topology
- `docs/presence-layer.md` — PresenceProfile options and timing behavior
- `docs/architecture.md` — System architecture and component boundaries
