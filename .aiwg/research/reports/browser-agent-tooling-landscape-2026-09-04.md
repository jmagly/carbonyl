# Browser-agent and headless-browser tooling landscape

**Status:** research synthesis · **Measured:** 2026-09-04 · **Scope:** open-source
software, hosted services, MCP servers, browser-control protocols, documented
agent techniques, benchmarks, and Carbonyl positioning.

## Executive conclusion

There is no single “browser tool” market. The available systems occupy five
layers: browser engines, automation protocols/libraries, agent policy layers,
MCP/CLI adapters, and managed browser infrastructure. Comparing a hosted agent
such as Browser Use Cloud directly with Playwright, or a scraping API directly
with Browserbase, produces a misleading result. The accompanying evaluation
therefore freezes and scores each layer independently.

Carbonyl's highest-leverage near-term strategy is **CDP compatibility first**.
A reliable CDP endpoint makes Playwright, Puppeteer, Browser Use, Stagehand,
chromedp, Rod, Chrome DevTools MCP, and raw protocol clients potential consumers
without Carbonyl-specific forks. A thin Carbonyl CLI/skill and MCP adapter can
then expose the project's distinct advantages: terminal-native human
observability, low-cost text/AX output, trusted-input mode, fused observations,
and supervised shared sessions. WebDriver BiDi is the logical second protocol
only if vendor-neutral browser compatibility becomes a product goal.

The first evaluation wave should compare Carbonyl direct/CDP, Playwright native,
Playwright MCP, Playwright CLI/skill, Chrome DevTools MCP, `agent-browser`, Browser
Use local, and Stagehand local. The second wave should compare Carbonyl Fleet
with Steel and Browserless self-hosted. Managed finalists should initially be
Browserbase, Steel, Browserless, Hyperbrowser, Browser Use Cloud, Cloudflare
Browser Run, Bright Data Browser API, Oxylabs Headless Browser, Zyte CDP, and
Apify. AgentQL belongs in an augmentation arm, not the browser-runtime column.

## Carbonyl current fit

Repository evidence shows that Carbonyl is already more than a terminal UI:

- Chromium is controllable through CDP while terminal rendering continues;
  `scripts/test-cdp.sh` exercises Page, Runtime, DOM, Accessibility, Network, and
  screenshots.
- `--dump-text` provides inner text, raw DOM, and browser-process accessibility
  snapshots; visual dump modes provide PNG and terminal-image output.
- X11 plus `uinput` can deliver trusted browser input, while X-mirror provides a
  supervisor-visible framebuffer.
- `carbonyl-agent` supplies PTY automation, persistent personas, Unix-socket
  daemon reconnection, and trusted-input support.
- `carbonyl-fleet` supplies concurrent session supervision, REST/gRPC, snapshots,
  AX/screenshot/network observations, and authenticated service boundaries.

Some API documents describe target-state surfaces. Evaluation claims must be
backed by a runnable binary and test result, not documentation alone.

## Market map

### Browser engines and runtimes

| Candidate | Shape | License | Assessment |
|---|---|---|---|
| [Chromium](https://www.chromium.org/chromium-projects/) | Full browser engine; CDP reference implementation | BSD-family/open-source components | Compatibility baseline and Carbonyl substrate |
| [Carbonyl](https://github.com/jmagly/carbonyl) | Chromium fork with terminal, text, AX, screenshot, CDP, and trusted-input modes | BSD-3-Clause | Primary subject; unique operator-observability hypothesis |
| [Lightpanda](https://github.com/lightpanda-io/browser) | Zig, CDP-compatible headless engine | AGPL-3.0 | High-value startup/RSS comparator; incomplete web/CDP compatibility must be measured |
| [Camoufox](https://github.com/daijro/camoufox) | Firefox-derived anti-detect browser | MPL-2.0-derived project terms | Specialized fingerprint/proxy test arm, not a general control library |
| [CloakBrowser](https://github.com/CloakHQ/CloakBrowser) | Chromium-derived browser for automation/agents | Verify at selected revision | Discovery candidate; require provenance and compatibility diligence before execution |

### Deterministic automation and protocol clients

| Candidate | Runtime/protocol | License | Best role |
|---|---|---|---|
| [Playwright](https://github.com/microsoft/playwright) | Node/Python/Java/.NET; Chromium, Firefox, WebKit; native protocol and CDP attach | Apache-2.0 | Primary deterministic and cross-browser baseline |
| [Puppeteer](https://github.com/puppeteer/puppeteer) | Node; CDP with growing WebDriver BiDi support | Apache-2.0 | Chrome-depth and raw-CDP comparison |
| [Selenium](https://github.com/SeleniumHQ/selenium) | Multi-language WebDriver/Grid/BiDi | Apache-2.0 | Standards, browser matrix, and grid baseline |
| [chromedp](https://github.com/chromedp/chromedp) | Go; direct CDP | MIT | Lean Go conformance and cancellation testing |
| [Rod](https://github.com/go-rod/rod) | Go; higher-level CDP | MIT | Auto-wait/recovery comparison with chromedp |
| [chrome-remote-interface](https://github.com/cyrus-and/chrome-remote-interface) | Node; near-direct CDP | MIT | Precise domain/event conformance probe |
| [SeleniumBase](https://github.com/seleniumbase/SeleniumBase) | Python; Selenium/CDP automation and testing | MIT | Higher-level test and anti-detection comparison |
| [Patchright](https://github.com/Kaliiiiiiiiii-Vinyzu/patchright) | Patched Playwright | Apache-2.0 lineage; verify distribution | Specialized detection-resistance arm |
| [nodriver](https://github.com/ultrafunkamsterdam/nodriver) | Python; direct Chrome control | AGPL-3.0 | Specialized Chrome automation/anti-detection arm |
| [undetected-chromedriver](https://github.com/ultrafunkamsterdam/undetected-chromedriver) | Python/Selenium Chrome patching | GPL-3.0 | Historical/specialized baseline; maintenance and policy risk |
| [rebrowser-patches](https://github.com/rebrowser/rebrowser-patches) | Patches for Puppeteer/Playwright | MIT | Controlled fingerprint experiment only |
| [Crawlee](https://github.com/apify/crawlee) | TypeScript/Python crawler with Playwright/Puppeteer | Apache-2.0 | Crawl orchestration, queues, retries, datasets |
| [Scrapy](https://github.com/scrapy/scrapy) | Python HTTP crawler; browser integrations external | BSD-3-Clause | Non-browser retrieval ceiling and crawl baseline |
| [Ferrum](https://github.com/rubycdp/ferrum) | Ruby; CDP | MIT | Language ecosystem completeness, lower priority |
| [Taiko](https://github.com/getgauge/taiko) | Node; Chrome automation | Apache-2.0 | Semantic test authoring, secondary |

### Agent policy and semantic automation layers

| Candidate | Control substrate | License/deployment | Notes |
|---|---|---|---|
| [Browser Use](https://github.com/browser-use/browser-use) | CDP/local Chrome or cloud | MIT plus hosted service | Leading Python agent baseline; evaluate local and cloud separately |
| [Stagehand](https://github.com/browserbase/stagehand) | Pluggable Playwright/Puppeteer/Patchright adapters | MIT; local or Browserbase | `act`/`observe`/`extract`, schemas, caching, iframe/shadow support |
| [Skyvern](https://github.com/Skyvern-AI/skyvern) | Playwright plus vision/LLM workflow | AGPL-3.0 plus cloud | Strong unfamiliar-form/RPA candidate; cloud-only anti-bot features |
| [LaVague](https://github.com/lavague-ai/LaVague) | Selenium, Playwright, extension drivers | Apache-2.0 | Useful architectural baseline; repository activity indicates maintenance risk |
| [Agent-E](https://github.com/EmergenceAI/Agent-E) | AG2 browser agent | MIT | Research/legacy agent baseline |
| [AgentQL](https://github.com/tinyfish-io/agentql) | Semantic query/locator layer on Playwright | SDK plus hosted API | Augmentation arm, not a browser runtime |
| [AutoGen MultimodalWebSurfer](https://microsoft.github.io/autogen/stable/reference/python/autogen_ext.agents.web_surfer.html) | Playwright-backed agent | MIT project | Framework integration baseline |
| [LangChain PlayWright toolkit](https://python.langchain.com/docs/integrations/tools/playwright/) | Playwright tools | MIT project | General agent-framework integration baseline |
| [CrewAI browser tools](https://docs.crewai.com/en/tools/web-scraping) | Browser/scrape tool wrappers | MIT core plus services | Workflow-framework integration baseline |
| [OpenHands browser environment](https://github.com/All-Hands-AI/OpenHands) | Browser/computer tools inside coding agent | MIT | Browser-plus-code workflow candidate |
| [Magnitude](https://github.com/magnitudedev/magnitude) | Vision-first browser automation | MIT | Visual grounding comparator |
| [Shortest](https://github.com/anti-work/shortest) | Natural-language E2E tests using Playwright | Verify selected revision | Test-generation candidate, not infrastructure |
| [Vercel agent-browser](https://github.com/vercel-labs/agent-browser) | Rust CLI/daemon over Chrome/CDP | Apache-2.0 | High-priority CLI/skill token-efficiency comparator |

### Browser-control MCP servers

| MCP | Current status | Important boundary |
|---|---|---|
| [Microsoft Playwright MCP](https://github.com/microsoft/playwright-mcp) | Active, Apache-2.0; local, Docker, HTTP, extension/existing browser | AX-first and deterministic; project explicitly says it is not a security boundary |
| [Chrome DevTools MCP](https://github.com/ChromeDevTools/chrome-devtools-mcp) | Active, Apache-2.0 | Best console/network/performance diagnostic depth; Chromium-only |
| [Browser Use MCP](https://github.com/browser-use/browser-use/blob/main/skills/open-source/references/integrations.md) | Active first-party local stdio and cloud HTTP | Separate privacy/cost scores for local and cloud |
| [Browserless MCP](https://github.com/browserless/browserless-mcp) | Active hosted and self-hosted MCP | Browserless core license is source-available/SSPL, not permissive OSS |
| [Steel MCP](https://github.com/steel-dev/steel-mcp-server) | Official experimental server; newer session-handle patterns in [cookbook](https://docs.steel.dev/cookbook/mcp) | Score MCP maturity separately from Steel browser infrastructure |
| [Hyperbrowser MCP](https://github.com/hyperbrowserai/mcp) | Active MIT wrapper over hosted backend | Wrapper is OSS; browser service is SaaS |
| [Browserbase MCP](https://docs.browserbase.com/integrations/mcp/introduction) | Current hosted Stagehand-backed service | Former [OSS server](https://github.com/browserbase/mcp-server-browserbase) was archived 2026-07-20 |
| [Browser MCP](https://github.com/BrowserMCP/mcp) | Active local extension bridge, Apache-2.0 | Uses the operator's real profile; high-value and high-consequence boundary |
| [Puppeteer reference MCP](https://github.com/modelcontextprotocol/servers-archived/tree/main/src/puppeteer) | Archived 2025-05-29 | Historical baseline only; do not select for production |
| [Cloudflare Playwright MCP path](https://developers.cloudflare.com/browser-run/) | Documented remote Browser Run integration | Managed service; pin adapter and browser versions |
| [Bright Data MCP](https://docs.brightdata.com/ai/mcp-server/remote/advanced) | Hosted/local vendor MCP | Mixes browser, scrape, search, and data tools; scope least privilege |
| [Apify MCP](https://docs.apify.com/integrations/mcp) | Hosted/local gateway to Actors | Marketplace execution and data lineage differ from direct browser control |
| [ScrapingBee remote MCP](https://www.scrapingbee.com/documentation/remote-mcp/) | Hosted retrieval/extraction MCP | Not a bidirectional long-running browser session |

MCP registries such as the GitHub MCP Registry, Smithery, and PulseMCP are useful
discovery leads only. Each candidate must be verified at the publisher repository,
package registry, and owned endpoint; registry popularity is not evidence of
authenticity or maintenance. In particular, the official Playwright package is
`@playwright/mcp`, not the confusing unscoped package `playwright-mcp`.

### Managed browser infrastructure and hosted agents

| Service | Product shape | Key evaluation reason |
|---|---|---|
| [Browserbase](https://www.browserbase.com/) | Browser-as-a-service, Stagehand, MCP, profiles, proxies, CAPTCHA, replay/live view | Strongest agent-native managed baseline |
| [Steel Cloud](https://steel.dev/) | Open-core browser infrastructure with cloud sessions, profiles, proxies, CAPTCHA, SDKs | Direct cloud/self-host comparison and transparent metering |
| [Browserless](https://www.browserless.io/) | CDP/Playwright/Puppeteer service, BrowserQL/BAP, profiles, proxy/CAPTCHA, agents | Mature infrastructure and queueing baseline |
| [Hyperbrowser](https://www.hyperbrowser.ai/docs/introduction) | Cloud sessions, scraping, profiles, stealth, agents, MCP | Broad agent/service feature comparison |
| [Browser Use Cloud](https://browser-use.com/) | Hosted browser agent and raw browser/CDP | End-to-end agent baseline |
| [Cloudflare Browser Run](https://developers.cloudflare.com/browser-run/) | Edge browser sessions plus stateless content/screenshot/snapshot/crawl APIs | Low-cost clean infrastructure and global-edge baseline |
| [Bright Data Browser API](https://brightdata.com/products/scraping-browser) | CDP browser with residential network, unlocking, geo, CAPTCHA | Hard-target/geo infrastructure baseline |
| [Oxylabs Headless Browser](https://oxylabs.io/headless-browser-service) | Managed CDP/Playwright/Puppeteer with residential proxy and CAPTCHA | Enterprise hard-target comparator |
| [Zyte API CDP](https://docs.zyte.com/zyte-api/usage/cdp.html) | Stateful-within-connection managed browser/unblocking | Scraping/unblocking comparator, not durable workflow identity |
| [Apify](https://docs.apify.com/platform) | Actor platform, Crawlee, proxy, storage, schedules, marketplace | Packaged workflows, crawl lineage, and operations |
| [Amazon Bedrock AgentCore Browser](https://aws.amazon.com/bedrock/agentcore/) | AWS-managed agent browser with enterprise integration | Cloud/IAM/governance fit |
| [Anchor Browser](https://docs.anchorbrowser.io/) | Headful isolated browser environments and agent APIs | Human supervision and ephemeral-VM security candidate |
| [CloudBrowser AI](https://cloudbrowser.ai/) | Remote browser infrastructure | Diligence/trial candidate; evidence depth below shortlist |
| BrowserCat | Multi-browser remote endpoint claim | Discovery lead only: its first-party site returned HTTP 402 during verification, so it is not admitted to the shortlist |

### Retrieval, rendering, and extraction services

These can be dramatically cheaper and safer than an autonomous browser when the
task is “obtain content,” but must be scored in their own track.

| Service | Shape |
|---|---|
| [ScrapingBee](https://www.scrapingbee.com/documentation/) | Rendered HTML, scripted scenarios, screenshots, proxy/stealth, extraction and MCP |
| [ScrapingAnt](https://docs.scrapingant.com/) | Headless rendering, proxies, anti-bot, AI extraction |
| [Scrapfly](https://scrapfly.io/docs/scrape-api/getting-started) | Browser rendering, adaptive anti-bot, sessions, extraction |
| [Zyte API](https://docs.zyte.com/zyte-api/usage/index.html) | Browser actions, extraction, automatic proxy/unblocking |
| [Bright Data Web Unlocker](https://brightdata.com/products/web-unlocker) | Managed unlocking and rendered retrieval |
| [Oxylabs Web Unblocker](https://oxylabs.io/products/web-unblocker) | Proxy-like managed unblocking with browser instructions |
| [Firecrawl](https://github.com/firecrawl/firecrawl) | Crawl/scrape/search/extract API with self-host option |
| [Jina Reader](https://jina.ai/reader/) | URL-to-model-friendly content |
| [FetchFox](https://github.com/fetchfox/fetchfox) | Browser-extension extraction with natural-language schemas |

### Cross-browser testing clouds

[BrowserStack Automate](https://www.browserstack.com/docs/automate),
[LambdaTest](https://www.lambdatest.com/support/docs/),
[Sauce Labs](https://docs.saucelabs.com/web-apps/automated-testing/), and
[TestingBot](https://testingbot.com/support/) are valuable for browser/OS/device
correctness, private tunnels, video, and logs. They should not be scored as if
they promised residential identity, CAPTCHA solving, persistent personas, or
agent planning. Begin with BrowserStack as one representative and expand only if
cross-browser compatibility is a deciding requirement.

### Profile-isolation browsers

[Multilogin](https://multilogin.com/help/en_US/getting-started-with-multilogin-x-automation)
and [GoLogin](https://gologin.com/docs/api-reference/introduction) expose
fingerprint-isolated persistent profiles and automation APIs. Evaluate them only
for legitimate, explicitly authorized multi-profile requirements. Their proxy
provenance, credential storage, target terms, abuse controls, and governance risk
require separate approval; they are not general agent planners.

## Protocol and observation techniques

| Technique | Advantages | Failure modes / use |
|---|---|---|
| [Chrome DevTools Protocol](https://chromedevtools.github.io/devtools-protocol/) | Deep DOM, AX, network, trace, runtime, input, and screenshot access | Chromium-specific; tip-of-tree has no compatibility guarantee. Pin protocol/browser revisions |
| [WebDriver](https://www.w3.org/TR/webdriver1/) | Stable vendor-neutral command model | Less browser-internal diagnostic depth |
| [WebDriver BiDi](https://www.w3.org/TR/webdriver-bidi/) | Eventful bidirectional cross-browser direction | Still a W3C Working Draft; test per-browser domain support |
| Accessibility snapshot | Compact semantic roles/names and stable grounding without vision | Misses canvas, spatial state, images, and visual-only affordances; hidden/ARIA text can carry injections |
| DOM/HTML | Maximum structure and programmatic power | Large/noisy/unstable context and hidden hostile content |
| Screenshot plus vision | Captures human-visible layout, canvas, images, and spatial state | Higher latency/tokens; coordinate, scale, and DPI brittleness |
| Set-of-marks | Numbers candidate elements over screenshots for grounding | Visual clutter and dependency on correct candidate enumeration |
| Terminal-rendered text | Very compact, human-supervisable stream | Loses some semantics and visual/spatial cues; requires task-specific validation |
| Hybrid adaptive observation | AX first, screenshot/marks for ambiguity, targeted DOM/CDP for diagnosis | Best default hypothesis; complexity and modality-switch policy must be measured |
| Semantic locators/action caching | Resilient intent-level scripts and reusable actions | LLM/schema dependency; stale cache and incorrect match require deterministic validation |
| Persistent profiles | Amortizes login/MFA and supports long workflows | Profiles are bearer credentials; enforce isolation, encryption, revoke/delete, and exclusive ownership |
| Human takeover | Handles MFA, ambiguity, and consequential actions | Requires explicit control transfer, audit, timeout, and no simultaneous actor writes |

## Evaluation and benchmark evidence

- [BrowserGym](https://github.com/ServiceNow/BrowserGym) and
  [AgentLab](https://github.com/ServiceNow/AgentLab) provide the strongest common
  OSS harness for unified observation/action spaces, experiment configuration,
  traces, and benchmark adapters.
- [WebArena](https://github.com/web-arena-x/webarena) supplies realistic,
  self-hosted, execution-scored sites. Prefer
  [WebArena-Verified](https://servicenow.github.io/webarena-verified/) where its
  re-audited tasks cover the need.
- [VisualWebArena](https://github.com/web-arena-x/visualwebarena) is required to
  test visual grounding rather than rewarding AX/DOM-only systems.
- [WorkArena](https://github.com/ServiceNow/WorkArena) covers enterprise knowledge
  work; WorkArena++ adds compositional planning.
- [WebLINX](https://github.com/McGill-NLP/weblinx) covers conversational multi-turn
  traces. Always label WebLINX 1.0 versus 1.1/BrowserGym evaluation.
- [Mind2Web](https://github.com/OSU-NLP-Group/Mind2Web) covers offline generalist
  grounding. [Online-Mind2Web](https://github.com/OSU-NLP-Group/Online-Mind2Web)
  adds current live tasks but must be version/date stamped.
- [WebVoyager](https://github.com/MinorJerry/WebVoyager) is a useful
  screenshot/set-of-marks live-web baseline, but site drift and model judging
  weaken reproducibility.
- [OSWorld](https://github.com/xlang-ai/OSWorld) tests browser-plus-desktop and
  cross-application behavior; it is a stress tier rather than a browser-only
  aggregate.
- [AgentDojo](https://github.com/ethz-spylab/agentdojo) and
  [DoomArena](https://github.com/ServiceNow/doomarena) supply executable
  prompt-injection/security evaluation patterns.

“BrowserBench” is overloaded across browser-engine performance, vendor
infrastructure/stealth, and agent benchmarks. “BrowserGym2” is used for the
evolved BrowserGym ecosystem rather than a separately verified package. Every
reported score must name publisher, repository, dataset version, task subset,
metric, model, and run date.

## Security and governance findings

Browser agents process adversarial content while holding network, profile, file,
and action authority. Model instructions are not a security boundary.

Production gates should require:

1. external egress/origin enforcement that survives redirects, plus blocks on
   loopback, RFC1918, link-local, metadata endpoints, and unauthorized `file://`;
2. per-session ephemeral credentials, isolated profiles, exclusive actor leases,
   bounded steps/time/spend, and verified cleanup;
3. confirmation for purchases, submissions, messages, deletions, permission
   grants, credential entry, and other consequential actions;
4. quarantined/scanned downloads and workspace-scoped uploads;
5. prompt-injection cases in visible text, hidden DOM, ARIA, alt, metadata,
   images, and tool results;
6. auditable control transfer for human takeover;
7. explicit retention/redaction for screenshots, HAR, traces, video, DOM, form
   contents, cookies, and support access.

For hosted vendors, require DPA/subprocessor evidence, encryption, deletion SLA,
residency, incident notice, tenant isolation, staff-access controls, profile
export/revoke/delete, training-data terms, proxy sourcing, CAPTCHA-solver data
handling, and billing cleanup. Marketing claims such as “stealth” or “unlimited”
are hypotheses until reproduced on authorized targets.

## Recommendation

1. Implement the local deterministic/security suite in `eval/browser-agent` and
   build adapters around a common run-result envelope.
2. Establish Carbonyl's raw CDP ceiling with Playwright, Puppeteer,
   chrome-remote-interface, and chromedp before testing an LLM.
3. Compare AX, screenshot, terminal text, and adaptive hybrid observation with
   the same browser/model/tasks.
4. Add Playwright MCP, Playwright CLI/skill, Chrome DevTools MCP,
   `agent-browser`, Browser Use, and Stagehand while keeping the browser fixed.
5. Run self-hosted Carbonyl Fleet, Steel, and Browserless under the same resource
   limits and session-cleanup tests.
6. Trial the managed shortlist using synthetic/owned targets, recording pricing
   snapshots and effective cost per successful task.
7. Adopt neither anti-detect tooling nor profile-isolation services without a
   separate legal/security decision.

## Method and confidence

The study used primary vendor documentation, official repositories, standards,
and original benchmark papers/repositories retrieved on 2026-09-04. Product
existence, architecture, license, maintenance status, and documented integration
claims have moderate-to-high confidence. Vendor security, performance, stealth,
scale, and cost-effectiveness claims have low-to-moderate confidence until the
evaluation reproduces them. Pricing is intentionally linked rather than copied
as a timeless fact; record a dated pricing snapshot at trial time.

The companion [source register](../sources/browser-agent-source-register-2026-09-04.md)
records retrieval provenance. No vendor directory, affiliate comparison, search
snippet, or community popularity figure is used as proof of capability.

BrowserCat's first-party site returned HTTP 402 during the citation check and is
retained only as an unverified discovery lead. It contributes no capability or
ranking evidence.
