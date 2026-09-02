#include "carbonyl/src/extensions/content_browser_client_hooks.h"

#include <memory>
#include <utility>

#include "base/command_line.h"
#include "base/functional/bind.h"
#include "content/public/browser/render_frame_host.h"
#include "content/public/browser/render_process_host.h"
#include "content/public/browser/security_principal.h"
#include "content/public/browser/service_worker_version_base_info.h"
#include "content/public/browser/site_instance.h"
#include "content/public/browser/web_contents.h"
#include "extensions/browser/api/web_request/web_request_api.h"
#include "extensions/browser/browser_context_keyed_api_factory.h"
#include "extensions/browser/event_router.h"
#include "extensions/browser/extension_navigation_throttle.h"
#include "extensions/browser/extension_protocols.h"
#include "extensions/browser/extension_registry.h"
#include "extensions/browser/extension_web_contents_observer.h"
#include "extensions/browser/extensions_browser_client.h"
#include "extensions/browser/process_map.h"
#include "extensions/browser/renderer_startup_helper.h"
#include "extensions/browser/service_worker/service_worker_host.h"
#include "extensions/browser/url_loader_factory_manager.h"
#include "extensions/common/constants.h"
#include "extensions/common/extension.h"
#include "extensions/common/manifest_handlers/sandboxed_page_info.h"
#include "extensions/common/mojom/event_router.mojom.h"
#include "extensions/common/mojom/frame.mojom.h"
#include "extensions/common/mojom/renderer_host.mojom.h"
#include "extensions/common/switches.h"
#include "mojo/public/cpp/bindings/binder_map.h"
#include "services/network/public/cpp/url_loader_factory_builder.h"
#include "third_party/blink/public/common/associated_interfaces/associated_interface_registry.h"

namespace carbonyl {

void RegisterExtensionBrowserInterfaceBindersForFrame(
    content::RenderFrameHost* render_frame_host,
    mojo::BinderMapWithContext<content::RenderFrameHost*>* map) {
  if (!render_frame_host->GetSiteInstance()->GetSecurityPrincipal().SchemeIs(
          extensions::kExtensionScheme)) {
    return;
  }
  auto* extension = extensions::ExtensionRegistry::Get(
                        render_frame_host->GetProcess()->GetBrowserContext())
                        ->enabled_extensions()
                        .GetByID(render_frame_host->GetSiteInstance()
                                     ->GetSecurityPrincipal()
                                     .GetHost());
  if (!extension) {
    return;
  }
  extensions::ExtensionsBrowserClient::Get()
      ->RegisterBrowserInterfaceBindersForFrame(map, render_frame_host,
                                                extension);
}

bool IsExtensionHandledURL(const GURL& url) {
  return url.SchemeIs(extensions::kExtensionScheme);
}

std::optional<GURL> GetExtensionEffectiveURL(
    content::BrowserContext* browser_context,
    const GURL& url) {
  auto* registry = extensions::ExtensionRegistry::Get(browser_context);
  if (registry && url.SchemeIs(extensions::kExtensionScheme) &&
      !registry->enabled_extensions().GetExtensionOrAppByURL(url)) {
    return GURL(extensions::kExtensionInvalidRequestURL);
  }
  return std::nullopt;
}

bool ShouldUseExtensionProcessPerSite(content::BrowserContext* browser_context,
                                      const GURL& site_url) {
  auto* registry = extensions::ExtensionRegistry::Get(browser_context);
  return registry &&
         registry->enabled_extensions().GetExtensionOrAppByURL(site_url);
}

bool ShouldUseSpareProcessForExtensionURL(const GURL& site_url) {
  return !site_url.SchemeIs(extensions::kExtensionScheme);
}

bool DoesExtensionSiteRequireDedicatedProcess(
    content::BrowserContext* browser_context,
    const GURL& effective_site_url) {
  auto* registry = extensions::ExtensionRegistry::Get(browser_context);
  return registry && registry->enabled_extensions().GetExtensionOrAppByURL(
                         effective_site_url);
}

bool IsSuitableExtensionProcessHost(content::RenderProcessHost* process_host,
                                    const GURL& site_url) {
  auto* registry =
      extensions::ExtensionRegistry::Get(process_host->GetBrowserContext());
  auto* process_map =
      extensions::ProcessMap::Get(process_host->GetBrowserContext());
  if (!registry || !process_map) {
    return true;
  }
  const extensions::Extension* extension =
      registry->enabled_extensions().GetExtensionOrAppByURL(site_url);
  if (extension &&
      !process_map->Contains(extension->id(), process_host->GetID())) {
    return false;
  }
  return extension || !process_map->Contains(process_host->GetID());
}

void AppendExtensionRendererCommandLineSwitches(
    base::CommandLine* command_line,
    content::RenderProcessHost* process_host) {
  if (extensions::ProcessMap::Get(process_host->GetBrowserContext())
          ->GetEnabledExtensionByProcessID(process_host->GetID())) {
    command_line->AppendSwitch(extensions::switches::kExtensionProcess);
  }
}

bool HasExtensionWebRequestAPIProxy(content::BrowserContext* browser_context) {
  auto* api =
      extensions::BrowserContextKeyedAPIFactory<extensions::WebRequestAPI>::Get(
          browser_context);
  return api && api->HasWebRequestOrDeclarativeWebRequestExtension();
}

bool CanCommitExtensionURL(content::RenderProcessHost* process_host,
                           const GURL& url) {
  auto* registry =
      extensions::ExtensionRegistry::Get(process_host->GetBrowserContext());
  const extensions::Extension* extension =
      registry ? registry->enabled_extensions().GetExtensionOrAppByURL(url)
               : nullptr;
  if (!extension) {
    return true;
  }
  if (extensions::ProcessMap::Get(process_host->GetBrowserContext())
          ->Contains(extension->id(), process_host->GetID())) {
    return true;
  }
  return extensions::SandboxedPageInfo::IsSandboxedPage(extension,
                                                        url.GetPath());
}

void AddExtensionNavigationThrottle(
    content::NavigationThrottleRegistry& registry) {
  registry.AddThrottle(
      std::make_unique<extensions::ExtensionNavigationThrottle>(registry));
}

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
    scoped_refptr<base::SequencedTaskRunner> navigation_response_task_runner) {
  auto* api =
      extensions::BrowserContextKeyedAPIFactory<extensions::WebRequestAPI>::Get(
          browser_context);
  if (!api) {
    return;
  }
  const bool proxied = api->MaybeProxyURLLoaderFactory(
      browser_context, frame, render_process_id, type, std::move(navigation_id),
      ukm_source_id, factory_builder, header_client,
      std::move(navigation_response_task_runner), request_initiator);
  if (bypass_redirect_checks) {
    *bypass_redirect_checks = proxied;
  }
}

void ExtensionSiteInstanceGotProcessAndSite(content::SiteInstance* instance) {
  auto* registry =
      extensions::ExtensionRegistry::Get(instance->GetBrowserContext());
  const extensions::Extension* extension =
      registry->enabled_extensions().GetExtensionOrAppByURL(
          instance->GetSecurityPrincipal().GetDeprecatedSiteURL());
  if (!extension || instance->GetSecurityPrincipal().IsSandboxed()) {
    return;
  }
  extensions::ProcessMap::Get(instance->GetBrowserContext())
      ->Insert(extension->id(), instance->GetProcess()->GetID());
}

void ExposeExtensionInterfacesToRenderer(
    blink::AssociatedInterfaceRegistry* associated_registry,
    content::RenderProcessHost* render_process_host) {
  associated_registry->AddInterface<extensions::mojom::RendererHost>(
      base::BindRepeating(&extensions::RendererStartupHelper::BindForRenderer,
                          render_process_host->GetID()));
}

void RegisterExtensionAssociatedFrameBinders(
    content::RenderFrameHost& render_frame_host,
    blink::AssociatedInterfaceRegistry& associated_registry) {
  const content::ChildProcessId process_id =
      render_frame_host.GetProcess()->GetID();
  associated_registry.AddInterface<extensions::mojom::EventRouter>(
      base::BindRepeating(&extensions::EventRouter::BindForRenderer,
                          process_id));
  associated_registry.AddInterface<extensions::mojom::RendererHost>(
      base::BindRepeating(&extensions::RendererStartupHelper::BindForRenderer,
                          process_id));
  associated_registry.AddInterface<extensions::mojom::LocalFrameHost>(
      base::BindRepeating(
          [](content::RenderFrameHost* frame,
             mojo::PendingAssociatedReceiver<extensions::mojom::LocalFrameHost>
                 receiver) {
            extensions::ExtensionWebContentsObserver::BindLocalFrameHost(
                std::move(receiver), frame);
          },
          &render_frame_host));
}

void RegisterExtensionAssociatedServiceWorkerBinders(
    const content::ServiceWorkerVersionBaseInfo& service_worker_version_info,
    blink::AssociatedInterfaceRegistry& associated_registry) {
  CHECK(service_worker_version_info.process_id);
  const content::ChildProcessId process_id =
      service_worker_version_info.process_id;
  associated_registry.AddInterface<extensions::mojom::RendererHost>(
      base::BindRepeating(&extensions::RendererStartupHelper::BindForRenderer,
                          process_id));
  associated_registry.AddInterface<extensions::mojom::ServiceWorkerHost>(
      base::BindRepeating(&extensions::ServiceWorkerHost::BindReceiver,
                          process_id));
  associated_registry.AddInterface<extensions::mojom::EventRouter>(
      base::BindRepeating(&extensions::EventRouter::BindForRenderer,
                          process_id));
}

mojo::PendingRemote<network::mojom::URLLoaderFactory>
CreateExtensionNavigationFactory(const std::string& scheme,
                                 content::FrameTreeNodeId frame_tree_node_id) {
  if (scheme != extensions::kExtensionScheme) {
    return {};
  }
  content::WebContents* contents =
      content::WebContents::FromFrameTreeNodeId(frame_tree_node_id);
  return extensions::CreateExtensionNavigationURLLoaderFactory(
      contents->GetBrowserContext(), /*is_web_view=*/false);
}

void RegisterExtensionWorkerFactories(
    content::BrowserContext* browser_context,
    const std::optional<url::Origin>& request_initiator,
    content::ContentBrowserClient::NonNetworkURLLoaderFactoryMap* factories) {
  factories->emplace(
      extensions::kExtensionScheme,
      extensions::CreateExtensionWorkerMainResourceURLLoaderFactory(
          browser_context, request_initiator));
}

void RegisterExtensionServiceWorkerUpdateFactories(
    content::BrowserContext* browser_context,
    content::ContentBrowserClient::NonNetworkURLLoaderFactoryMap* factories) {
  factories->emplace(
      extensions::kExtensionScheme,
      extensions::CreateExtensionServiceWorkerScriptURLLoaderFactory(
          browser_context));
}

void RegisterExtensionSubresourceFactories(
    int render_process_id,
    int render_frame_id,
    content::ContentBrowserClient::NonNetworkURLLoaderFactoryMap* factories) {
  factories->emplace(
      extensions::kExtensionScheme,
      extensions::CreateExtensionURLLoaderFactory(
          content::ChildProcessId::FromUnsafeValue(render_process_id),
          render_frame_id));
}

void OverrideExtensionURLLoaderFactoryParams(
    content::BrowserContext* browser_context,
    const url::Origin& origin,
    bool is_for_isolated_world,
    bool is_for_service_worker,
    network::mojom::URLLoaderFactoryParams* factory_params) {
  extensions::URLLoaderFactoryManager::OverrideURLLoaderFactoryParams(
      browser_context, origin, is_for_isolated_world, is_for_service_worker,
      factory_params);
}

}  // namespace carbonyl
