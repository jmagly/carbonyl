#include "carbonyl/src/browser/operator_shell_command_line.h"

#include <string_view>

namespace carbonyl {

std::vector<const char*> BuildOperatorShellArguments(
    std::span<const char* const> arguments) {
  bool has_operator_argument = false;
  if (!arguments.empty()) {
    for (const char* argument : arguments.subspan(1)) {
      has_operator_argument |=
          std::string_view(argument) == kOperatorShellArgument;
    }
  }

  std::vector<const char*> operator_argv;
  operator_argv.reserve(arguments.size() + (has_operator_argument ? 0 : 1));
  if (!arguments.empty()) {
    operator_argv.push_back(arguments.front());
  }
  if (!has_operator_argument) {
    operator_argv.push_back(kOperatorShellArgument);
  }
  if (!arguments.empty()) {
    for (const char* argument : arguments.subspan(1)) {
      operator_argv.push_back(argument);
    }
  }
  return operator_argv;
}

}  // namespace carbonyl
