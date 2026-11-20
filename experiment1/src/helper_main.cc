#include "include/cef_app.h"

// Entry point for all helper (sub)processes: renderer, GPU, etc.
// The helper app bundles live in Experiment.app/Contents/Frameworks/.
int main(int argc, char* argv[]) {
  CefMainArgs main_args(argc, argv);
  // No CefApp implementation for helpers in this minimal experiment.
  return CefExecuteProcess(main_args, nullptr, nullptr);
}
