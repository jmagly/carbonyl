#ifndef CARBONYL_SRC_EXTENSIONS_BROWSER_CLIENT_H_
#define CARBONYL_SRC_EXTENSIONS_BROWSER_CLIENT_H_

namespace content {
class BrowserContext;
class WebContents;
}  // namespace content

namespace carbonyl {

// Installs the browser-process extension client. Runtime activation remains
// fail-closed unless the standard paired opt-in switches are present.
void InstallExtensionsBrowserClient();

// Enters the idempotent fail-closed teardown state before BrowserContexts are
// destroyed.
void StartExtensionsBrowserClientTearDown();

// Registers a profile context after its writable extension preferences exist,
// and unregisters it before keyed services and preferences are destroyed.
void RegisterExtensionContext(content::BrowserContext* context);
void UnregisterExtensionContext(content::BrowserContext* context);

// Attaches the core extension frame/message observer to a new WebContents.
void CreateExtensionWebContentsObserver(content::WebContents* web_contents);

}  // namespace carbonyl

#endif  // CARBONYL_SRC_EXTENSIONS_BROWSER_CLIENT_H_
