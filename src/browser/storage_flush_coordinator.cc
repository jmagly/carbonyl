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

}  // namespace carbonyl
