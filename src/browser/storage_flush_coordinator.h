#ifndef CARBONYL_SRC_BROWSER_STORAGE_FLUSH_COORDINATOR_H_
#define CARBONYL_SRC_BROWSER_STORAGE_FLUSH_COORDINATOR_H_

#include <vector>

#include "base/functional/callback.h"
#include "base/memory/weak_ptr.h"
#include "base/time/time.h"
#include "base/timer/timer.h"
#include "carbonyl/src/browser/export.h"
#include "carbonyl/src/browser/shutdown_state_machine.h"

namespace content {
class BrowserContext;
}

namespace carbonyl {

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

}  // namespace carbonyl

#endif  // CARBONYL_SRC_BROWSER_STORAGE_FLUSH_COORDINATOR_H_
