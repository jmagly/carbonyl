#ifndef CARBONYL_SRC_EXTENSIONS_RENDERER_CLIENT_H_
#define CARBONYL_SRC_EXTENSIONS_RENDERER_CLIENT_H_

namespace carbonyl {

// Installs the renderer-process extension client without creating a
// Dispatcher or forwarding execution hooks. #289 owns that later activation.
void InstallExtensionsRendererClient();

}  // namespace carbonyl

#endif  // CARBONYL_SRC_EXTENSIONS_RENDERER_CLIENT_H_
