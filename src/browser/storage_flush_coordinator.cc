#include "carbonyl/src/browser/storage_flush_coordinator.h"

#include <utility>

#include "base/check.h"
#include "base/functional/bind.h"
#include "base/location.h"
#include "content/public/browser/browser_context.h"
#include "content/public/browser/browser_thread.h"
#include "content/public/browser/storage_partition.h"
#include "services/network/public/mojom/cookie_manager.mojom.h"

namespace carbonyl {

ShutdownStateMachine::ShutdownStateMachine() = default;
ShutdownStateMachine::~ShutdownStateMachine() = default;

bool ShutdownStateMachine::BeginDrain(size_t partitions) {
  if (summary_.state != ShutdownState::kRunning) {
    return false;
  }
  summary_.state =
      partitions == 0 ? ShutdownState::kFlushed : ShutdownState::kDraining;
  summary_.result = partitions == 0 ? StorageFlushResult::kComplete
                                    : StorageFlushResult::kNone;
  summary_.partitions = partitions;
  return true;
}

bool ShutdownStateMachine::AcknowledgePartition() {
  if (summary_.state != ShutdownState::kDraining ||
      summary_.acknowledged >= summary_.partitions) {
    return false;
  }
  ++summary_.acknowledged;
  if (summary_.acknowledged == summary_.partitions) {
    summary_.state = ShutdownState::kFlushed;
    summary_.result = StorageFlushResult::kComplete;
  }
  return true;
}

bool ShutdownStateMachine::Fail() {
  if (summary_.state != ShutdownState::kDraining) {
    return false;
  }
  summary_.state = ShutdownState::kFailed;
  summary_.result = StorageFlushResult::kFailed;
  return true;
}

bool ShutdownStateMachine::TimeOut() {
  if (summary_.state != ShutdownState::kDraining) {
    return false;
  }
  summary_.state = ShutdownState::kFailed;
  summary_.result = StorageFlushResult::kTimedOut;
  return true;
}

bool ShutdownStateMachine::BeginDestroy() {
  if (summary_.state != ShutdownState::kFlushed &&
      summary_.state != ShutdownState::kFailed) {
    return false;
  }
  summary_.state = ShutdownState::kDestroying;
  return true;
}

bool ShutdownStateMachine::MarkStopped() {
  if (summary_.state != ShutdownState::kDestroying) {
    return false;
  }
  summary_.state = ShutdownState::kStopped;
  return true;
}

bool ShutdownStateMachine::IsAcceptingPageWork() const {
  return summary_.state == ShutdownState::kRunning;
}

StorageFlushSummary ShutdownStateMachine::summary() const {
  return summary_;
}

StorageFlushCoordinator::StorageFlushCoordinator(base::TimeDelta timeout)
    : timeout_(timeout) {
  CHECK(timeout_.is_positive());
}

StorageFlushCoordinator::~StorageFlushCoordinator() = default;

void StorageFlushCoordinator::Start(
    const std::vector<content::BrowserContext*>& contexts,
    CompletionCallback callback) {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!state_machine_.IsAcceptingPageWork()) {
    return;
  }

  std::vector<content::StoragePartition*> partitions;
  for (content::BrowserContext* context : contexts) {
    if (!context) {
      continue;
    }
    context->ForEachLoadedStoragePartition(
        [&partitions](content::StoragePartition* partition) {
          partitions.push_back(partition);
        });
  }

  callback_ = std::move(callback);
  CHECK(state_machine_.BeginDrain(partitions.size()));
  if (partitions.empty()) {
    Finish();
    return;
  }

  timeout_timer_.Start(FROM_HERE, timeout_, this,
                       &StorageFlushCoordinator::OnTimeout);
  for (content::StoragePartition* partition : partitions) {
    partition->Flush();
    network::mojom::CookieManager* cookie_manager =
        partition->GetCookieManagerForBrowserProcess();
    if (!cookie_manager) {
      state_machine_.Fail();
      Finish();
      return;
    }
    cookie_manager->FlushCookieStore(
        base::BindOnce(&StorageFlushCoordinator::OnPartitionAcknowledged,
                       weak_ptr_factory_.GetWeakPtr()));
  }
}

bool StorageFlushCoordinator::IsAcceptingPageWork() const {
  return state_machine_.IsAcceptingPageWork();
}

void StorageFlushCoordinator::OnPartitionAcknowledged() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (!state_machine_.AcknowledgePartition()) {
    return;
  }
  if (state_machine_.summary().state == ShutdownState::kFlushed) {
    Finish();
  }
}

void StorageFlushCoordinator::OnTimeout() {
  DCHECK_CURRENTLY_ON(content::BrowserThread::UI);
  if (state_machine_.TimeOut()) {
    Finish();
  }
}

void StorageFlushCoordinator::Finish() {
  if (completion_dispatched_) {
    return;
  }
  completion_dispatched_ = true;
  timeout_timer_.Stop();
  weak_ptr_factory_.InvalidateWeakPtrs();
  if (callback_) {
    std::move(callback_).Run(state_machine_.summary());
  }
}

std::string_view ToString(ShutdownState state) {
  switch (state) {
    case ShutdownState::kRunning:
      return "running";
    case ShutdownState::kDraining:
      return "draining";
    case ShutdownState::kFlushed:
      return "flushed";
    case ShutdownState::kDestroying:
      return "destroying";
    case ShutdownState::kStopped:
      return "stopped";
    case ShutdownState::kFailed:
      return "failed";
  }
  return "unknown";
}

std::string_view ToString(StorageFlushResult result) {
  switch (result) {
    case StorageFlushResult::kNone:
      return "none";
    case StorageFlushResult::kComplete:
      return "complete";
    case StorageFlushResult::kTimedOut:
      return "timed_out";
    case StorageFlushResult::kFailed:
      return "failed";
  }
  return "unknown";
}

}  // namespace carbonyl
