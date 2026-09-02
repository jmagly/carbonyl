#ifndef CARBONYL_SRC_BROWSER_OPERATOR_SHELL_COMMAND_LINE_H_
#define CARBONYL_SRC_BROWSER_OPERATOR_SHELL_COMMAND_LINE_H_

#include <span>
#include <vector>

namespace carbonyl {

inline constexpr char kOperatorShellArgument[] = "--carbonyl-operator-window";

// Return argv with the dedicated operator-shell switch present exactly once.
// The injected switch follows argv[0], before caller-supplied switches and the
// navigation argument.
std::vector<const char*> BuildOperatorShellArguments(
    std::span<const char* const> arguments);

}  // namespace carbonyl

#endif  // CARBONYL_SRC_BROWSER_OPERATOR_SHELL_COMMAND_LINE_H_
