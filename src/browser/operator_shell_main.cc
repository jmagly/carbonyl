#include <utility>

#include "carbonyl/src/browser/operator_shell_command_line.h"
#include "carbonyl/src/browser/renderer.h"
#include "content/public/app/content_main.h"
#include "headless/public/headless_shell.h"

int main(int argc, const char** argv) {
  carbonyl::Renderer::Main();

  // HeadlessShell initializes base::CommandLine itself. Add the operator-mode
  // argument to the raw argv first so browser and child startup consistently
  // select the X11 Ozone path. Preserve an explicit caller argument without
  // duplicating it.
  std::vector<const char*> operator_argv =
      carbonyl::BuildOperatorShellArguments(argc, argv);

  content::ContentMainParams params(nullptr);
  params.argc = static_cast<int>(operator_argv.size());
  params.argv = operator_argv.data();
  return headless::HeadlessShellMain(std::move(params));
}
