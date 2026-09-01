#include "carbonyl/src/browser/operator_shell_command_line.h"

#include <iostream>
#include <string_view>
#include <vector>

namespace {

bool Matches(const std::vector<const char*>& actual,
             const std::vector<std::string_view>& expected) {
  if (actual.size() != expected.size()) {
    return false;
  }
  for (std::size_t index = 0; index < actual.size(); ++index) {
    if (std::string_view(actual[index]) != expected[index]) {
      return false;
    }
  }
  return true;
}

bool RunCases() {
  {
    const char* argv[] = {"carbonyl_operator_shell", "https://example.com"};
    if (!Matches(carbonyl::BuildOperatorShellArguments(argv),
                 {"carbonyl_operator_shell", carbonyl::kOperatorShellArgument,
                  "https://example.com"})) {
      return false;
    }
  }
  {
    const char* argv[] = {"carbonyl_operator_shell",
                          carbonyl::kOperatorShellArgument,
                          "https://example.com"};
    if (!Matches(carbonyl::BuildOperatorShellArguments(argv),
                 {"carbonyl_operator_shell", carbonyl::kOperatorShellArgument,
                  "https://example.com"})) {
      return false;
    }
  }
  {
    const char* argv[] = {"carbonyl_operator_shell", "--user-data-dir=/tmp/p",
                          "https://example.com"};
    if (!Matches(carbonyl::BuildOperatorShellArguments(argv),
                 {"carbonyl_operator_shell", carbonyl::kOperatorShellArgument,
                  "--user-data-dir=/tmp/p", "https://example.com"})) {
      return false;
    }
  }
  return true;
}

}  // namespace

int main() {
  if (!RunCases()) {
    std::cerr << "FAIL: operator shell argv contract\n";
    return 1;
  }
  std::cout << "PASS: operator shell argv contract\n";
  return 0;
}
