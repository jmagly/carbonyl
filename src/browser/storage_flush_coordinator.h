#ifndef CARBONYL_SRC_BROWSER_STORAGE_FLUSH_COORDINATOR_H_
#define CARBONYL_SRC_BROWSER_STORAGE_FLUSH_COORDINATOR_H_

#include <cstddef>
#include <string_view>
#include <vector>

#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "carbonyl/src/browser/export.h"

namespace content {
class BrowserContext;
}

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

// Pure transition/counting core. All methods run on the browser UI sequence.
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

// Enumerates loaded partitions, starts their generic flushes, and waits for
// every cookie-store callback or a bounded timeout. It never reads stored data.
class CARBONYL_STORAGE_FLUSH_EXPORT StorageFlushCoordinator {
 public:
  using CompletionCallback = base::OnceCallback<void(StorageFlushSummary)>;

  explicit StorageFlushCoordinator(base::TimeDelta timeout);
  ~StorageFlushCoordinator();

  StorageFlushCoordinator(const StorageFlushCoordinator&) = delete;
  StorageFlushCoordinator& operator=(const StorageFlushCoordinator&) = delete;

  void Start(const std::vector<content::BrowserContext*>& contexts,
             CompletionCallback callback);
  bool IsAcceptingPageWork() const;
  ShutdownStateMachine& state_machine() { return state_machine_; }
  const ShutdownStateMachine& state_machine() const { return state_machine_; }

 private:
  void OnPartitionAcknowledged();
  void OnTimeout();
  void Finish();

  const base::TimeDelta timeout_;
  ShutdownStateMachine state_machine_;
  base::OneShotTimer timeout_timer_;
  CompletionCallback callback_;
  bool completion_dispatched_ = false;
  base::WeakPtrFactory<StorageFlushCoordinator> weak_ptr_factory_{this};
};

CARBONYL_STORAGE_FLUSH_EXPORT std::string_view ToString(ShutdownState state);
CARBONYL_STORAGE_FLUSH_EXPORT std::string_view ToString(
    StorageFlushResult result);

}  // namespace carbonyl

#endif  // CARBONYL_SRC_BROWSER_STORAGE_FLUSH_COORDINATOR_H_
