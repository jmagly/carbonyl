#include "carbonyl/src/extensions/renderer_client.h"
#include "carbonyl/src/extensions/switches.h"

#include <memory>
#include <string>

#include "base/command_line.h"
#include "content/public/renderer/render_frame.h"
#include "content/public/renderer/render_frame_observer.h"
#include "extensions/common/constants.h"
#include "extensions/common/switches.h"
#include "extensions/renderer/api/core_extensions_renderer_api_provider.h"
#include "extensions/renderer/dispatcher.h"
#include "extensions/renderer/extensions_renderer_client.h"
#include "services/service_manager/public/cpp/binder_registry.h"
#include "url/origin.h"

namespace extensions {
namespace {

class CarbonylExtensionsRendererClient : public ExtensionsRendererClient {
 public:
  bool IsIncognitoProcess() const override { return false; }

  int GetLowestIsolatedWorldId() const override {
    // World zero is Blink's main world. Content scripts start at world one so
    // terminal extraction never aliases extension execution with page JS.
    return 1;
  }
};

}  // namespace
}  // namespace extensions

namespace carbonyl {
namespace {

extensions::CarbonylExtensionsRendererClient* g_client = nullptr;

bool RuntimeEnabled() {
  const auto& command_line = *base::CommandLine::ForCurrentProcess();
  return command_line.HasSwitch(kEnableExtensionsRendererSwitch);
}

class CarbonylRenderFrameObserver : public content::RenderFrameObserver {
 public:
  explicit CarbonylRenderFrameObserver(content::RenderFrame* render_frame)
      : content::RenderFrameObserver(render_frame) {}

  service_manager::BinderRegistry* registry() { return &registry_; }

 private:
  void OnInterfaceRequestForFrame(
      const std::string& interface_name,
      mojo::ScopedMessagePipeHandle* interface_pipe) override {
    registry_.TryBindInterface(interface_name, interface_pipe);
  }

  void OnDestruct() override { delete this; }

  service_manager::BinderRegistry registry_;
};

}  // namespace

void InstallExtensionsRendererClient() {
  if (!g_client) {
    g_client = new extensions::CarbonylExtensionsRendererClient();
    g_client->AddAPIProvider(
        std::make_unique<extensions::CoreExtensionsRendererAPIProvider>());
    extensions::ExtensionsRendererClient::Set(g_client);
  }
}

void ExtensionsRenderThreadStarted() {
  // Chromium constructs RendererStartupHelper factories even while extension
  // loading is disabled, and those factories bind extensions.mojom.Renderer.
  // The dispatcher must therefore register its process interface
  // unconditionally; command-line and per-frame gates below still prevent
  // extension execution without explicit opt-in.
  g_client->RenderThreadStarted();
}

void ExtensionsRenderFrameCreated(content::RenderFrame* render_frame) {
  if (!RuntimeEnabled()) {
    return;
  }
  auto* observer = new CarbonylRenderFrameObserver(render_frame);
  g_client->RenderFrameCreated(render_frame, observer->registry());
}

void ExtensionsWebViewCreated(blink::WebView* web_view,
                              const url::Origin* outermost_origin) {
  if (RuntimeEnabled()) {
    g_client->WebViewCreated(web_view, outermost_origin);
  }
}

void RunExtensionScriptsAtDocumentStart(content::RenderFrame* render_frame) {
  if (RuntimeEnabled()) {
    g_client->RunScriptsAtDocumentStart(render_frame);
  }
}

void RunExtensionScriptsAtDocumentEnd(content::RenderFrame* render_frame) {
  if (RuntimeEnabled()) {
    g_client->RunScriptsAtDocumentEnd(render_frame);
  }
}

void RunExtensionScriptsAtDocumentIdle(content::RenderFrame* render_frame) {
  if (RuntimeEnabled()) {
    g_client->RunScriptsAtDocumentIdle(render_frame);
  }
}

bool AllowExtensionScriptForServiceWorker(const url::Origin& script_origin) {
  return RuntimeEnabled() &&
         script_origin.scheme() == extensions::kExtensionScheme;
}

void ExtensionsDidInitializeServiceWorkerContext(
    blink::WebServiceWorkerContextProxy* context_proxy,
    const GURL& service_worker_scope,
    const GURL& script_url) {
  if (RuntimeEnabled()) {
    g_client->dispatcher()->DidInitializeServiceWorkerContextOnWorkerThread(
        context_proxy, service_worker_scope, script_url);
  }
}

void ExtensionsWillEvaluateServiceWorker(
    blink::WebServiceWorkerContextProxy* context_proxy,
    v8::Local<v8::Context> v8_context,
    int64_t service_worker_version_id,
    const GURL& service_worker_scope,
    const GURL& script_url,
    const blink::ServiceWorkerToken& service_worker_token) {
  if (RuntimeEnabled()) {
    g_client->dispatcher()->WillEvaluateServiceWorkerOnWorkerThread(
        context_proxy, v8_context, service_worker_version_id,
        service_worker_scope, script_url, service_worker_token);
  }
}

void ExtensionsDidStartServiceWorker(
    int64_t service_worker_version_id,
    const GURL& service_worker_scope,
    const GURL& script_url,
    const blink::ServiceWorkerToken& service_worker_token) {
  if (RuntimeEnabled()) {
    g_client->dispatcher()->DidStartServiceWorkerContextOnWorkerThread(
        service_worker_version_id, service_worker_scope, script_url,
        service_worker_token);
  }
}

void ExtensionsWillDestroyServiceWorker(
    v8::Local<v8::Context> context,
    int64_t service_worker_version_id,
    const GURL& service_worker_scope,
    const GURL& script_url,
    const blink::ServiceWorkerToken& service_worker_token) {
  if (RuntimeEnabled()) {
    g_client->dispatcher()->WillDestroyServiceWorkerContextOnWorkerThread(
        context, service_worker_version_id, service_worker_scope, script_url,
        service_worker_token);
  }
}

}  // namespace carbonyl
