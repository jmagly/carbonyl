#ifndef CARBONYL_SRC_BROWSER_SHUTDOWN_STATE_MACHINE_H_
#define CARBONYL_SRC_BROWSER_SHUTDOWN_STATE_MACHINE_H_

#include <cstddef>
#include <string_view>

#include "carbonyl/src/browser/export.h"

namespace carbonyl {

enum class ShutdownState {
  kRunning,
  kDraining,
  kFlushed,
  kDestroying,
  kStopped,
  kFailed,
};

enum class StorageFlushResult {
  kNone,
  kComplete,
  kTimedOut,
  kFailed,
};

struct CARBONYL_STORAGE_FLUSH_EXPORT StorageFlushSummary {
  ShutdownState state = ShutdownState::kRunning;
  StorageFlushResult result = StorageFlushResult::kNone;
  size_t partitions = 0;
  size_t acknowledged = 0;
};

// Pure transition/counting core. All methods run on the browser UI sequence
// in production, but the type itself has no Chromium runtime dependencies.
class CARBONYL_STORAGE_FLUSH_EXPORT ShutdownStateMachine {
 public:
  ShutdownStateMachine();
  ~ShutdownStateMachine();

  ShutdownStateMachine(const ShutdownStateMachine&) = delete;
  ShutdownStateMachine& operator=(const ShutdownStateMachine&) = delete;

  // Returns false for an idempotent repeated request or an invalid terminal
  // replay. A zero-partition drain transitions directly to kFlushed.
  bool BeginDrain(size_t partitions);
  bool AcknowledgePartition();
  bool Fail();
  bool TimeOut();
  bool BeginDestroy();
  bool MarkStopped();

  bool IsAcceptingPageWork() const;
  StorageFlushSummary summary() const;

 private:
  StorageFlushSummary summary_;
};

CARBONYL_STORAGE_FLUSH_EXPORT std::string_view ToString(ShutdownState state);
CARBONYL_STORAGE_FLUSH_EXPORT std::string_view ToString(
    StorageFlushResult result);

}  // namespace carbonyl

#endif  // CARBONYL_SRC_BROWSER_SHUTDOWN_STATE_MACHINE_H_
