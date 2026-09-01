#include "carbonyl/src/browser/shutdown_state_machine.h"

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
