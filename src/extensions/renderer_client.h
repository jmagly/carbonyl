#ifndef CARBONYL_SRC_EXTENSIONS_RENDERER_CLIENT_H_
#define CARBONYL_SRC_EXTENSIONS_RENDERER_CLIENT_H_

#include <cstdint>

#include "v8/include/v8-forward.h"

class GURL;

namespace content {
class RenderFrame;
}

namespace blink {
class ServiceWorkerToken;
class WebView;
class WebServiceWorkerContextProxy;
}

namespace url {
class Origin;
}

namespace carbonyl {

// Installs the renderer-process extension client. Its process interface is
// always registered because browser keyed services bind it even when loading
// is disabled; frame initialization and script execution remain opt-in.
void InstallExtensionsRendererClient();
void ExtensionsRenderThreadStarted();
void ExtensionsRenderFrameCreated(content::RenderFrame* render_frame);
void ExtensionsWebViewCreated(blink::WebView* web_view,
                              const url::Origin* outermost_origin);
void RunExtensionScriptsAtDocumentStart(content::RenderFrame* render_frame);
void RunExtensionScriptsAtDocumentEnd(content::RenderFrame* render_frame);
void RunExtensionScriptsAtDocumentIdle(content::RenderFrame* render_frame);
bool AllowExtensionScriptForServiceWorker(const url::Origin& script_origin);
void ExtensionsDidInitializeServiceWorkerContext(
    blink::WebServiceWorkerContextProxy* context_proxy,
    const GURL& service_worker_scope,
    const GURL& script_url);
void ExtensionsWillEvaluateServiceWorker(
    blink::WebServiceWorkerContextProxy* context_proxy,
    v8::Local<v8::Context> v8_context,
    int64_t service_worker_version_id,
    const GURL& service_worker_scope,
    const GURL& script_url,
    const blink::ServiceWorkerToken& service_worker_token);
void ExtensionsDidStartServiceWorker(
    int64_t service_worker_version_id,
    const GURL& service_worker_scope,
    const GURL& script_url,
    const blink::ServiceWorkerToken& service_worker_token);
void ExtensionsWillDestroyServiceWorker(
    v8::Local<v8::Context> context,
    int64_t service_worker_version_id,
    const GURL& service_worker_scope,
    const GURL& script_url,
    const blink::ServiceWorkerToken& service_worker_token);

}  // namespace carbonyl

#endif  // CARBONYL_SRC_EXTENSIONS_RENDERER_CLIENT_H_
