#ifndef CARBONYL_SRC_BROWSER_OPERATOR_CONTROLS_MODEL_H_
#define CARBONYL_SRC_BROWSER_OPERATOR_CONTROLS_MODEL_H_

#include <string>
#include <string_view>

namespace carbonyl {

enum class OperatorSecurityLevel {
  kSecure,
  kInsecure,
  kLocal,
  kFile,
  kCertificateError,
  kInternal,
  kError,
};

struct OperatorSecuritySignals {
  bool error_page = false;
  bool internal = false;
  bool file = false;
  bool local = false;
  bool https = false;
  bool ssl_initialized = false;
  bool certificate_error = false;
  bool insecure_content = false;
};

struct OperatorSecurityPresentation {
  OperatorSecurityLevel level = OperatorSecurityLevel::kInternal;
  std::string label;
};

OperatorSecurityPresentation BuildOperatorSecurityPresentation(
    const OperatorSecuritySignals& signals,
    std::string_view committed_origin);

// Returns true when user-typed text should go to the browser's search URL
// rather than the fixed-up URL. The caller supplies the canonical URL facts so
// this policy remains independently testable without Chromium's URL runtime.
bool ShouldSearchOperatorAddress(std::string_view typed_text,
                                 bool fixed_url_valid,
                                 bool fixed_scheme_allowed,
                                 bool explicit_scheme,
                                 bool fixed_host_is_ip,
                                 std::string_view fixed_host);

}  // namespace carbonyl

#endif  // CARBONYL_SRC_BROWSER_OPERATOR_CONTROLS_MODEL_H_
