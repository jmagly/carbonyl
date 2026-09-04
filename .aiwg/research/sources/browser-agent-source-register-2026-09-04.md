# Browser-agent source register

All sources were retrieved or checked on 2026-09-04. `HIGH` means an official
standard, repository, documentation site, or original benchmark artifact directly
supports the catalog claim. `MODERATE` denotes first-party commercial claims that
still require trial or contractual diligence. Links are direct primary sources.

| ID | Source | Kind | Quality | Used for |
|---|---|---|---|---|
| SRC-001 | [Microsoft Playwright](https://github.com/microsoft/playwright) | Official repository | HIGH | Engines, languages, automation baseline |
| SRC-002 | [Playwright MCP](https://github.com/microsoft/playwright-mcp) | Official repository | HIGH | MCP features, profiles, security caveat, CLI comparison |
| SRC-003 | [Chrome DevTools MCP](https://github.com/ChromeDevTools/chrome-devtools-mcp) | Official repository | HIGH | Diagnostics-focused MCP |
| SRC-004 | [Puppeteer](https://github.com/puppeteer/puppeteer) | Official repository | HIGH | CDP/BiDi automation |
| SRC-005 | [Selenium](https://github.com/SeleniumHQ/selenium) | Official repository | HIGH | WebDriver/Grid/BiDi baseline |
| SRC-006 | [WebDriver](https://www.w3.org/TR/webdriver1/) | W3C Recommendation | HIGH | Stable cross-browser protocol |
| SRC-007 | [WebDriver BiDi](https://www.w3.org/TR/webdriver-bidi/) | W3C Working Draft | HIGH | Bidirectional cross-browser protocol status |
| SRC-008 | [Chrome DevTools Protocol](https://chromedevtools.github.io/devtools-protocol/) | Chromium protocol documentation | HIGH | CDP domains and compatibility warning |
| SRC-009 | [chromedp](https://github.com/chromedp/chromedp) | Official repository | HIGH | Go CDP client |
| SRC-010 | [Rod](https://github.com/go-rod/rod) | Official repository | HIGH | Go CDP client |
| SRC-011 | [chrome-remote-interface](https://github.com/cyrus-and/chrome-remote-interface) | Official repository | HIGH | Low-level Node CDP client |
| SRC-012 | [Browser Use](https://github.com/browser-use/browser-use) | Official repository | HIGH | Agent framework and local MCP |
| SRC-013 | [Stagehand](https://github.com/browserbase/stagehand) | Official repository | HIGH | Semantic automation/agent SDK |
| SRC-014 | [Skyvern](https://github.com/Skyvern-AI/skyvern) | Official repository | HIGH | Vision/LLM workflow agent and license |
| SRC-015 | [LaVague](https://github.com/lavague-ai/LaVague) | Official repository | HIGH | Driver-pluggable agent and telemetry |
| SRC-016 | [Agent-E](https://github.com/EmergenceAI/Agent-E) | Official repository | HIGH | Browser-agent architecture |
| SRC-017 | [AgentQL](https://github.com/tinyfish-io/agentql) | Official repository | HIGH | Semantic locator/extraction layer |
| SRC-018 | [AgentQL docs](https://docs.agentql.com/home) | Official documentation | HIGH | SDK/API and Playwright integration |
| SRC-019 | [Steel Browser](https://github.com/steel-dev/steel-browser) | Official repository | HIGH | Self-hosted browser infrastructure |
| SRC-020 | [Steel MCP](https://github.com/steel-dev/steel-mcp-server) | Official experimental repository | HIGH | MCP maturity boundary |
| SRC-021 | [Browserless core](https://github.com/browserless/browserless) | Official repository | HIGH | Self-host features and license |
| SRC-022 | [Browserless MCP](https://github.com/browserless/browserless-mcp) | Official repository | HIGH | Hosted/self-hosted MCP |
| SRC-023 | [Hyperbrowser MCP](https://github.com/hyperbrowserai/mcp) | Official repository | HIGH | OSS wrapper over hosted service |
| SRC-024 | [Browser MCP](https://github.com/BrowserMCP/mcp) | Official repository | HIGH | Existing-profile extension bridge |
| SRC-025 | [Archived MCP Puppeteer server](https://github.com/modelcontextprotocol/servers-archived/tree/main/src/puppeteer) | Official archive | HIGH | Historical/non-production status |
| SRC-026 | [Archived Browserbase MCP](https://github.com/browserbase/mcp-server-browserbase) | Official archive | HIGH | Superseded implementation status |
| SRC-027 | [Lightpanda](https://github.com/lightpanda-io/browser) | Official repository | HIGH | Alternative engine/CDP compatibility |
| SRC-028 | [Vercel agent-browser](https://github.com/vercel-labs/agent-browser) | Official repository | HIGH | Agent-oriented CLI/daemon |
| SRC-029 | [Crawlee](https://github.com/apify/crawlee) | Official repository | HIGH | Crawl orchestration |
| SRC-030 | [BrowserGym](https://github.com/ServiceNow/BrowserGym) | Official repository/paper links | HIGH | Unified evaluation harness |
| SRC-031 | [AgentLab](https://github.com/ServiceNow/AgentLab) | Official repository | HIGH | Experiment and trace management |
| SRC-032 | [WebArena paper](https://arxiv.org/abs/2307.13854) | Original paper | HIGH | Realistic self-hosted benchmark |
| SRC-033 | [WebArena code](https://github.com/web-arena-x/webarena) | Official repository | HIGH | Executable benchmark |
| SRC-034 | [WebArena-Verified](https://servicenow.github.io/webarena-verified/) | Official benchmark documentation | HIGH | Re-audited reproducible task set |
| SRC-035 | [VisualWebArena paper](https://arxiv.org/abs/2401.13649) | Original paper | HIGH | Visually grounded benchmark |
| SRC-036 | [VisualWebArena code](https://github.com/web-arena-x/visualwebarena) | Official repository | HIGH | Executable visual benchmark |
| SRC-037 | [WorkArena paper](https://arxiv.org/abs/2403.07718) | Original paper | HIGH | Enterprise tasks |
| SRC-038 | [WorkArena code](https://github.com/ServiceNow/WorkArena) | Official repository | HIGH | Executable enterprise benchmark |
| SRC-039 | [WebLINX paper](https://arxiv.org/abs/2402.05930) | Original paper | HIGH | Conversational multi-turn benchmark |
| SRC-040 | [WebLINX code](https://github.com/McGill-NLP/weblinx) | Official repository | HIGH | Dataset/version semantics |
| SRC-041 | [Mind2Web paper](https://arxiv.org/abs/2306.06070) | Original paper | HIGH | Generalist grounding benchmark |
| SRC-042 | [Mind2Web code](https://github.com/OSU-NLP-Group/Mind2Web) | Official repository | HIGH | Dataset and evaluation |
| SRC-043 | [Online-Mind2Web](https://github.com/OSU-NLP-Group/Online-Mind2Web) | Official repository | HIGH | Versioned live-web benchmark |
| SRC-044 | [WebVoyager paper](https://arxiv.org/abs/2401.13919) | Original paper | HIGH | Screenshot/set-of-marks technique |
| SRC-045 | [WebVoyager code](https://github.com/MinorJerry/WebVoyager) | Official repository | HIGH | Live-web baseline implementation |
| SRC-046 | [OSWorld paper](https://arxiv.org/abs/2404.07972) | Original paper | HIGH | Browser-plus-desktop stress tier |
| SRC-047 | [OSWorld code](https://github.com/xlang-ai/OSWorld) | Official repository | HIGH | Executable environment |
| SRC-048 | [AgentDojo paper](https://arxiv.org/abs/2406.13352) | Original paper | HIGH | Prompt-injection evaluation |
| SRC-049 | [AgentDojo code](https://github.com/ethz-spylab/agentdojo) | Official repository | HIGH | Executable security benchmark |
| SRC-050 | [DoomArena](https://github.com/ServiceNow/doomarena) | Official repository | HIGH | BrowserGym injection benchmark |
| SRC-051 | [Browserbase](https://www.browserbase.com/) | First-party product documentation | MODERATE | Managed browser/agent capabilities |
| SRC-052 | [Browserbase pricing](https://www.browserbase.com/pricing) | First-party pricing | MODERATE | Dated trial economics |
| SRC-053 | [Browserbase MCP](https://docs.browserbase.com/integrations/mcp/introduction) | Official documentation | HIGH | Current hosted MCP path |
| SRC-054 | [Browserbase security](https://docs.browserbase.com/account/enterprise/security) | First-party security documentation | MODERATE | Isolation/residency/compliance diligence |
| SRC-055 | [Steel docs](https://docs.steel.dev/) | Official documentation | HIGH | Managed/self-host feature surface |
| SRC-056 | [Steel pricing and limits](https://docs.steel.dev/overview/pricinglimits) | First-party pricing | MODERATE | Metering, concurrency, retention |
| SRC-057 | [Browserless docs](https://docs.browserless.io/) | Official documentation | HIGH | API, agent, profile, proxy surface |
| SRC-058 | [Browserless unit consumption](https://docs.browserless.io/overview/unit-consumption) | First-party pricing documentation | MODERATE | Usage accounting |
| SRC-059 | [Hyperbrowser docs](https://www.hyperbrowser.ai/docs/introduction) | Official documentation | HIGH | Sessions, agents, MCP, SDKs |
| SRC-060 | [Hyperbrowser pricing](https://www.hyperbrowser.ai/docs/pricing) | First-party pricing | MODERATE | Credit model |
| SRC-061 | [Browser Use Cloud](https://browser-use.com/) | First-party product documentation | MODERATE | Hosted agent/browser capabilities |
| SRC-062 | [Browser Use pricing](https://browser-use.com/pricing) | First-party pricing | MODERATE | Agent/browser/proxy metering |
| SRC-063 | [Cloudflare Browser Run](https://developers.cloudflare.com/browser-run/) | Official documentation | HIGH | Edge browser and Quick Actions |
| SRC-064 | [Cloudflare Browser Run pricing](https://developers.cloudflare.com/browser-run/pricing/) | First-party pricing | MODERATE | Duration/concurrency economics |
| SRC-065 | [Bright Data Browser API](https://brightdata.com/products/scraping-browser) | First-party product documentation | MODERATE | Managed unblocking/proxy browser |
| SRC-066 | [Bright Data MCP](https://docs.brightdata.com/ai/mcp-server/remote/advanced) | Official documentation | HIGH | Hosted MCP scope |
| SRC-067 | [Oxylabs Headless Browser](https://oxylabs.io/headless-browser-service) | First-party product documentation | MODERATE | Managed CDP/proxy browser |
| SRC-068 | [Zyte CDP](https://docs.zyte.com/zyte-api/usage/cdp.html) | Official documentation | HIGH | CDP semantics and limits |
| SRC-069 | [Zyte pricing](https://docs.zyte.com/zyte-api/pricing.html) | First-party pricing | MODERATE | Success/tier billing |
| SRC-070 | [Apify MCP](https://docs.apify.com/integrations/mcp) | Official documentation | HIGH | Actor/MCP integration |
| SRC-071 | [Apify platform](https://docs.apify.com/platform) | Official documentation | HIGH | Actors, storage, proxy, schedules |
| SRC-072 | [Amazon Bedrock AgentCore](https://aws.amazon.com/bedrock/agentcore/) | Official product documentation | MODERATE | AWS-managed browser/governance integration |
| SRC-073 | [Anchor Browser security](https://docs.anchorbrowser.io/security) | First-party security documentation | MODERATE | Ephemeral browser isolation claims |
| SRC-074 | [ScrapingBee docs](https://www.scrapingbee.com/documentation/) | Official documentation | HIGH | Render/extract retrieval rail |
| SRC-075 | [ScrapingAnt docs](https://docs.scrapingant.com/) | Official documentation | HIGH | Render/proxy retrieval rail |
| SRC-076 | [Scrapfly docs](https://scrapfly.io/docs/scrape-api/getting-started) | Official documentation | HIGH | Browser/anti-bot retrieval rail |
| SRC-077 | [Firecrawl](https://github.com/firecrawl/firecrawl) | Official repository | HIGH | Crawl/extract service and self-hosting |
| SRC-078 | [BrowserStack Automate](https://www.browserstack.com/docs/automate) | Official documentation | HIGH | Cross-browser QA cloud |
| SRC-079 | [LambdaTest automation](https://www.lambdatest.com/support/docs/) | Official documentation | HIGH | Cross-browser QA cloud |
| SRC-080 | [Sauce Labs web testing](https://docs.saucelabs.com/web-apps/automated-testing/) | Official documentation | HIGH | Cross-browser QA cloud |
| SRC-081 | [TestingBot](https://testingbot.com/support/) | Official documentation | HIGH | Cross-browser QA cloud |
| SRC-082 | [Multilogin automation](https://multilogin.com/help/en_US/getting-started-with-multilogin-x-automation) | Official documentation | HIGH | Profile-isolation automation |
| SRC-083 | [GoLogin API](https://gologin.com/docs/api-reference/introduction) | Official documentation | HIGH | Profile-isolation automation |
| SRC-084 | [MCP authorization specification](https://modelcontextprotocol.io/specification/2025-06-18/basic/authorization) | Official protocol specification | HIGH | MCP authentication boundary |
