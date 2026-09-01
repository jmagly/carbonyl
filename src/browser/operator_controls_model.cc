#include "carbonyl/src/browser/operator_controls_model.h"

#include <algorithm>

namespace carbonyl {
namespace {

std::string LabelWithOrigin(std::string_view label,
                            std::string_view committed_origin) {
  std::string result(label);
  if (!committed_origin.empty()) {
    result.append(" - ");
    result.append(committed_origin);
  }
  return result;
}

bool ContainsAsciiWhitespace(std::string_view value) {
  return std::ranges::any_of(value, [](char character) {
    return character == ' ' || character == '\t' || character == '\r' ||
           character == '\n';
  });
}

}  // namespace

OperatorSecurityPresentation BuildOperatorSecurityPresentation(
    const OperatorSecuritySignals& signals,
    std::string_view committed_origin) {
  if (signals.error_page) {
    return {OperatorSecurityLevel::kError,
            LabelWithOrigin("Error page", committed_origin)};
  }
  if (signals.certificate_error) {
    return {OperatorSecurityLevel::kCertificateError,
            LabelWithOrigin("Certificate error", committed_origin)};
  }
  if (signals.file) {
    return {OperatorSecurityLevel::kFile,
            LabelWithOrigin("Local file", committed_origin)};
  }
  if (signals.local) {
    return {OperatorSecurityLevel::kLocal,
            LabelWithOrigin("Local", committed_origin)};
  }
  if (signals.internal) {
    return {OperatorSecurityLevel::kInternal,
            LabelWithOrigin("Internal", committed_origin)};
  }
  if (signals.https && signals.ssl_initialized && !signals.insecure_content) {
    return {OperatorSecurityLevel::kSecure,
            LabelWithOrigin("Secure", committed_origin)};
  }
  if (signals.https || !committed_origin.empty()) {
    return {OperatorSecurityLevel::kInsecure,
            LabelWithOrigin("Not secure", committed_origin)};
  }
  return {OperatorSecurityLevel::kInternal,
          LabelWithOrigin("Internal", committed_origin)};
}

bool ShouldSearchOperatorAddress(std::string_view typed_text,
                                 bool fixed_url_valid,
                                 bool fixed_scheme_allowed,
                                 bool explicit_scheme,
                                 bool fixed_host_is_ip,
                                 std::string_view fixed_host) {
  if (!fixed_url_valid || !fixed_scheme_allowed) {
    return true;
  }
  if (explicit_scheme) {
    return false;
  }
  if (ContainsAsciiWhitespace(typed_text)) {
    return true;
  }
  if (fixed_host_is_ip || fixed_host == "localhost" ||
      fixed_host.find('.') != std::string_view::npos) {
    return false;
  }
  return true;
}

}  // namespace carbonyl
