#ifndef CARBONYL_SRC_EXTENSIONS_RENDERER_CLIENT_H_
#define CARBONYL_SRC_EXTENSIONS_RENDERER_CLIENT_H_

namespace content {
class RenderFrame;
}

namespace blink {
class WebView;
}

namespace url {
class Origin;
}

namespace carbonyl {

// Installs the renderer-process extension client. Dispatcher creation and
// script execution remain gated by the browser's paired opt-in switches.
void InstallExtensionsRendererClient();
void ExtensionsRenderThreadStarted();
void ExtensionsRenderFrameCreated(content::RenderFrame* render_frame);
void ExtensionsWebViewCreated(blink::WebView* web_view,
                              const url::Origin* outermost_origin);
void RunExtensionScriptsAtDocumentStart(content::RenderFrame* render_frame);
void RunExtensionScriptsAtDocumentEnd(content::RenderFrame* render_frame);
void RunExtensionScriptsAtDocumentIdle(content::RenderFrame* render_frame);

}  // namespace carbonyl

#endif  // CARBONYL_SRC_EXTENSIONS_RENDERER_CLIENT_H_
