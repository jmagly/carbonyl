#include "carbonyl/src/browser/operator_controls_model.h"

#include <iostream>
#include <string_view>

namespace carbonyl {
namespace {

int failures = 0;

void Expect(bool condition, std::string_view expression) {
  if (condition) {
    return;
  }
  std::cerr << "FAIL: " << expression << std::endl;
  ++failures;
}

void SecurityStatesAreConservative() {
  OperatorSecuritySignals secure;
  secure.https = true;
  secure.ssl_initialized = true;
  const OperatorSecurityPresentation secure_presentation =
      BuildOperatorSecurityPresentation(secure, "https://example.test");
  Expect(secure_presentation.level == OperatorSecurityLevel::kSecure,
         "initialized clean HTTPS is secure");
  Expect(secure_presentation.label == "Secure - https://example.test",
         "secure label includes only the committed origin");

  secure.insecure_content = true;
  Expect(
      BuildOperatorSecurityPresentation(secure, "https://example.test").level ==
          OperatorSecurityLevel::kInsecure,
      "mixed HTTPS content is not secure");

  secure.certificate_error = true;
  const OperatorSecurityPresentation certificate_error =
      BuildOperatorSecurityPresentation(secure, "https://example.test");
  Expect(certificate_error.level == OperatorSecurityLevel::kCertificateError,
         "certificate error takes priority");
  Expect(certificate_error.label == "Certificate error - https://example.test",
         "certificate-error label remains explicit");

  OperatorSecuritySignals loading_https;
  loading_https.https = true;
  Expect(
      BuildOperatorSecurityPresentation(loading_https, "https://example.test")
              .level == OperatorSecurityLevel::kInsecure,
      "uninitialized HTTPS is never labeled secure");

  OperatorSecuritySignals http;
  Expect(BuildOperatorSecurityPresentation(http, "http://example.test").level ==
             OperatorSecurityLevel::kInsecure,
         "HTTP is not secure");
}

void LocalFileInternalAndErrorStatesAreDistinct() {
  OperatorSecuritySignals local;
  local.local = true;
  Expect(
      BuildOperatorSecurityPresentation(local, "http://localhost:8000").level ==
          OperatorSecurityLevel::kLocal,
      "localhost is local");

  OperatorSecuritySignals file;
  file.file = true;
  Expect(BuildOperatorSecurityPresentation(file, "file://").level ==
             OperatorSecurityLevel::kFile,
         "file URL is local file");

  OperatorSecuritySignals internal;
  internal.internal = true;
  Expect(BuildOperatorSecurityPresentation(internal, "").level ==
             OperatorSecurityLevel::kInternal,
         "opaque internal page is internal");

  OperatorSecuritySignals error;
  error.error_page = true;
  Expect(BuildOperatorSecurityPresentation(error, "https://bad.test").level ==
             OperatorSecurityLevel::kError,
         "committed error page is error");
}

void AddressPolicySeparatesUrlsFromSearches() {
  Expect(!ShouldSearchOperatorAddress("https://example.test", true, true, true,
                                      false, "example.test"),
         "explicit allowed URL navigates");
  Expect(!ShouldSearchOperatorAddress("example.test", true, true, false, false,
                                      "example.test"),
         "domain-like input navigates");
  Expect(!ShouldSearchOperatorAddress("127.0.0.1:8000", true, true, false, true,
                                      "127.0.0.1"),
         "IP-like input navigates");
  Expect(!ShouldSearchOperatorAddress("file:///tmp/example.html", true, true,
                                      true, false, ""),
         "explicit allowed file URL navigates");
  Expect(
      !ShouldSearchOperatorAddress("about:blank", true, true, true, false, ""),
      "explicit allowed internal URL navigates");
  Expect(ShouldSearchOperatorAddress("browser controls", false, true, false,
                                     false, ""),
         "words search");
  Expect(ShouldSearchOperatorAddress("singleword", true, true, false, false,
                                     "singleword"),
         "single word searches");
  Expect(ShouldSearchOperatorAddress("javascript:alert(1)", true, false, true,
                                     false, ""),
         "disallowed scheme searches instead of executing");
}

}  // namespace
}  // namespace carbonyl

int main() {
  carbonyl::SecurityStatesAreConservative();
  carbonyl::LocalFileInternalAndErrorStatesAreDistinct();
  carbonyl::AddressPolicySeparatesUrlsFromSearches();

  if (carbonyl::failures != 0) {
    std::cerr << "FAIL: " << carbonyl::failures
              << " operator-controls assertions failed" << std::endl;
    return 1;
  }
  std::cout << "PASS: operator security and address policy" << std::endl;
  return 0;
}
