#ifndef CARBONYL_SRC_EXTENSIONS_SWITCHES_H_
#define CARBONYL_SRC_EXTENSIONS_SWITCHES_H_

namespace carbonyl {

// Path-free browser-to-renderer marker. The browser appends this only after
// validating the explicit unpacked-extension opt-in switches.
inline constexpr char kEnableExtensionsRendererSwitch[] =
    "carbonyl-enable-extensions-renderer";

}  // namespace carbonyl

#endif  // CARBONYL_SRC_EXTENSIONS_SWITCHES_H_
