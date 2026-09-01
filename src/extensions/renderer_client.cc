#include "carbonyl/src/extensions/renderer_client.h"

#include "extensions/renderer/extensions_renderer_client.h"

namespace extensions {
namespace {

class CarbonylExtensionsRendererClient : public ExtensionsRendererClient {
 public:
  bool IsIncognitoProcess() const override { return false; }

  int GetLowestIsolatedWorldId() const override {
    // World zero is Blink's main world. This ID is reserved now so #289 cannot
    // accidentally regress dump-text's existing main-world assumption while
    // adding isolated-world execution.
    return 1;
  }
};

}  // namespace
}  // namespace extensions

namespace carbonyl {

void InstallExtensionsRendererClient() {
  static auto* const client =
      new extensions::CarbonylExtensionsRendererClient();
  extensions::ExtensionsRendererClient::Set(client);
}

}  // namespace carbonyl
