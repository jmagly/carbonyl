#ifndef CARBONYL_SRC_EXTENSIONS_BROWSER_CLIENT_H_
#define CARBONYL_SRC_EXTENSIONS_BROWSER_CLIENT_H_

namespace carbonyl {

// Installs the browser-process extension client. This first linkage slice is
// permanently disabled: it owns no ExtensionSystem and rejects installation.
void InstallExtensionsBrowserClient();

// Enters the idempotent fail-closed teardown state before BrowserContexts are
// destroyed.
void StartExtensionsBrowserClientTearDown();

}  // namespace carbonyl

#endif  // CARBONYL_SRC_EXTENSIONS_BROWSER_CLIENT_H_
