#include "carbonyl/src/browser/operator_shell_command_line.h"

#include <string_view>

namespace carbonyl {

std::vector<const char*> BuildOperatorShellArguments(
    int argc,
    const char* const* argv) {
  bool has_operator_argument = false;
  for (int index = 1; index < argc; ++index) {
    has_operator_argument |=
        std::string_view(argv[index]) == kOperatorShellArgument;
  }

  std::vector<const char*> operator_argv;
  operator_argv.reserve(static_cast<std::size_t>(argc) +
                        (has_operator_argument ? 0 : 1));
  if (argc > 0) {
    operator_argv.push_back(argv[0]);
  }
  if (!has_operator_argument) {
    operator_argv.push_back(kOperatorShellArgument);
  }
  for (int index = 1; index < argc; ++index) {
    operator_argv.push_back(argv[index]);
  }
  return operator_argv;
}

}  // namespace carbonyl
