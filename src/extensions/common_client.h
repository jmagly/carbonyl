#ifndef CARBONYL_SRC_EXTENSIONS_COMMON_CLIENT_H_
#define CARBONYL_SRC_EXTENSIONS_COMMON_CLIENT_H_

namespace carbonyl {

// Installs Carbonyl's process-global extension client. The client registers
// Chromium's core MV3 schema/manifest provider, but denies scriptability,
// privileged schemes, web-store/update traffic, and host permissions.
void InstallExtensionsCommonClient();

}  // namespace carbonyl

#endif  // CARBONYL_SRC_EXTENSIONS_COMMON_CLIENT_H_
