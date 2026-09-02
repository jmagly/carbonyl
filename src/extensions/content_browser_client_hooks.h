#ifndef CARBONYL_SRC_EXTENSIONS_CONTENT_BROWSER_CLIENT_HOOKS_H_
#define CARBONYL_SRC_EXTENSIONS_CONTENT_BROWSER_CLIENT_HOOKS_H_

#include <optional>
#include <string>

#include "content/public/browser/content_browser_client.h"
#include "mojo/public/cpp/bindings/binder_map.h"

namespace blink {
class AssociatedInterfaceRegistry;
}

namespace content {
class RenderFrameHost;
class RenderProcessHost;
struct ServiceWorkerVersionBaseInfo;
class SiteInstance;
}  // namespace content

namespace base {
class CommandLine;
}

namespace carbonyl {

void RegisterExtensionBrowserInterfaceBindersForFrame(
    content::RenderFrameHost* render_frame_host,
    mojo::BinderMapWithContext<content::RenderFrameHost*>* map);
bool IsExtensionHandledURL(const GURL& url);
std::optional<GURL> GetExtensionEffectiveURL(
    content::BrowserContext* browser_context,
    const GURL& url);
bool ShouldUseExtensionProcessPerSite(content::BrowserContext* browser_context,
                                      const GURL& site_url);
bool ShouldUseSpareProcessForExtensionURL(const GURL& site_url);
bool DoesExtensionSiteRequireDedicatedProcess(
    content::BrowserContext* browser_context,
    const GURL& effective_site_url);
bool IsSuitableExtensionProcessHost(content::RenderProcessHost* process_host,
                                    const GURL& site_url);
void AppendExtensionRendererCommandLineSwitches(
    base::CommandLine* command_line,
    content::RenderProcessHost* process_host);
bool HasExtensionWebRequestAPIProxy(content::BrowserContext* browser_context);
bool CanCommitExtensionURL(content::RenderProcessHost* process_host,
                           const GURL& url);
void AddExtensionNavigationThrottle(
    content::NavigationThrottleRegistry& registry);
void MaybeProxyExtensionURLLoaderFactory(
    content::BrowserContext* browser_context,
    content::RenderFrameHost* frame,
    int render_process_id,
    content::ContentBrowserClient::URLLoaderFactoryType type,
    const url::Origin& request_initiator,
    std::optional<int64_t> navigation_id,
    ukm::SourceIdObj ukm_source_id,
    network::URLLoaderFactoryBuilder& factory_builder,
    mojo::PendingRemote<network::mojom::TrustedURLLoaderHeaderClient>*
        header_client,
    bool* bypass_redirect_checks,
    scoped_refptr<base::SequencedTaskRunner> navigation_response_task_runner);
void ExtensionSiteInstanceGotProcessAndSite(content::SiteInstance* instance);
void ExposeExtensionInterfacesToRenderer(
    blink::AssociatedInterfaceRegistry* associated_registry,
    content::RenderProcessHost* render_process_host);
void RegisterExtensionAssociatedFrameBinders(
    content::RenderFrameHost& render_frame_host,
    blink::AssociatedInterfaceRegistry& associated_registry);
void RegisterExtensionAssociatedServiceWorkerBinders(
    const content::ServiceWorkerVersionBaseInfo& service_worker_version_info,
    blink::AssociatedInterfaceRegistry& associated_registry);
mojo::PendingRemote<network::mojom::URLLoaderFactory>
CreateExtensionNavigationFactory(const std::string& scheme,
                                 content::FrameTreeNodeId frame_tree_node_id);
void RegisterExtensionWorkerFactories(
    content::BrowserContext* browser_context,
    const std::optional<url::Origin>& request_initiator,
    content::ContentBrowserClient::NonNetworkURLLoaderFactoryMap* factories);
void RegisterExtensionServiceWorkerUpdateFactories(
    content::BrowserContext* browser_context,
    content::ContentBrowserClient::NonNetworkURLLoaderFactoryMap* factories);
void RegisterExtensionSubresourceFactories(
    int render_process_id,
    int render_frame_id,
    content::ContentBrowserClient::NonNetworkURLLoaderFactoryMap* factories);
void OverrideExtensionURLLoaderFactoryParams(
    content::BrowserContext* browser_context,
    const url::Origin& origin,
    bool is_for_isolated_world,
    bool is_for_service_worker,
    network::mojom::URLLoaderFactoryParams* factory_params);

}  // namespace carbonyl

#endif  // CARBONYL_SRC_EXTENSIONS_CONTENT_BROWSER_CLIENT_HOOKS_H_
