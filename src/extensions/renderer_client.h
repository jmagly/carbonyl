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

}  // namespace carbonyl

#endif  // CARBONYL_SRC_EXTENSIONS_RENDERER_CLIENT_H_
