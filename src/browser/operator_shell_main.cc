#include <cerrno>
#include <cstdio>
#include <cstring>
#include <limits.h>
#include <string>
#include <vector>

#include <unistd.h>

#include "carbonyl/src/browser/operator_shell_command_line.h"

namespace {

std::string ResolveSiblingHeadlessShell() {
  char executable_path[PATH_MAX];
  const ssize_t length =
      readlink("/proc/self/exe", executable_path, sizeof(executable_path));
  if (length <= 0 || static_cast<std::size_t>(length) >=
                         sizeof(executable_path)) {
    return {};
  }

  std::string path(executable_path, static_cast<std::size_t>(length));
  const std::size_t separator = path.rfind('/');
  if (separator == std::string::npos) {
    return {};
  }
  path.resize(separator + 1);
  path.append("headless_shell");
  return path;
}

}  // namespace

int main(int argc, const char** argv) {
  // Replace this launcher with the already-built sibling HeadlessShell in the
  // same process. That shell owns Carbonyl's one BrowserContext/WebContents;
  // adding the switch before exec makes its existing startup hook select the
  // X11 Views/Aura host without creating a second Chromium link product.
  const std::string headless_shell = ResolveSiblingHeadlessShell();
  if (headless_shell.empty()) {
    std::fprintf(stderr,
                 "carbonyl_operator_shell: cannot resolve /proc/self/exe\n");
    return 127;
  }

  const std::vector<const char*> operator_arguments =
      carbonyl::BuildOperatorShellArguments(argc, argv);
  std::vector<char*> exec_arguments;
  exec_arguments.reserve(operator_arguments.size() + 1);
  for (const char* argument : operator_arguments) {
    exec_arguments.push_back(const_cast<char*>(argument));
  }
  exec_arguments.push_back(nullptr);

  execv(headless_shell.c_str(), exec_arguments.data());
  std::fprintf(stderr, "carbonyl_operator_shell: cannot execute %s: %s\n",
               headless_shell.c_str(), std::strerror(errno));
  return 127;
}
