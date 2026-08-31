#include "carbonyl/src/browser/shutdown_state_machine.h"

#include <iostream>
#include <string_view>

namespace carbonyl {
namespace {

int failures = 0;

void Expect(bool condition, std::string_view expression) {
  if (condition) {
    return;
  }
  std::cerr << "FAIL: " << expression << std::endl;
  ++failures;
}

void ZeroPartitionsCompletesImmediately() {
  ShutdownStateMachine machine;

  Expect(machine.BeginDrain(0), "zero-partition drain begins");
  Expect(machine.summary().state == ShutdownState::kFlushed,
         "zero-partition drain is flushed");
  Expect(machine.summary().result == StorageFlushResult::kComplete,
         "zero-partition drain is complete");
  Expect(machine.summary().partitions == 0u, "zero partitions recorded");
  Expect(machine.summary().acknowledged == 0u,
         "zero acknowledgements recorded");
}

void OnePartitionRequiresOneAcknowledgement() {
  ShutdownStateMachine machine;

  Expect(machine.BeginDrain(1), "one-partition drain begins");
  Expect(machine.summary().state == ShutdownState::kDraining,
         "one-partition drain waits");
  Expect(machine.AcknowledgePartition(), "one partition acknowledges");
  Expect(machine.summary().state == ShutdownState::kFlushed,
         "one-partition drain flushes");
  Expect(machine.summary().result == StorageFlushResult::kComplete,
         "one-partition result is complete");
}

void MultiplePartitionsRequireEveryAcknowledgement() {
  ShutdownStateMachine machine;

  Expect(machine.BeginDrain(3), "multi-partition drain begins");
  Expect(machine.AcknowledgePartition(), "first partition acknowledges");
  Expect(machine.AcknowledgePartition(), "second partition acknowledges");
  Expect(machine.summary().state == ShutdownState::kDraining,
         "multi-partition drain still waits");
  Expect(machine.summary().acknowledged == 2u,
         "two acknowledgements recorded");
  Expect(machine.AcknowledgePartition(), "third partition acknowledges");
  Expect(machine.summary().state == ShutdownState::kFlushed,
         "all partitions flush");
}

void RepeatedShutdownAndCallbackAreIdempotent() {
  ShutdownStateMachine machine;

  Expect(machine.BeginDrain(1), "idempotency drain begins");
  Expect(!machine.BeginDrain(1), "repeated drain is rejected");
  Expect(machine.AcknowledgePartition(), "idempotency callback arrives");
  Expect(!machine.AcknowledgePartition(), "repeated callback is rejected");
  Expect(machine.summary().acknowledged == 1u,
         "repeated callback does not increment");
}

void CallbackFailureIsNeverReportedAsSuccess() {
  ShutdownStateMachine machine;

  Expect(machine.BeginDrain(2), "failure drain begins");
  Expect(machine.AcknowledgePartition(), "pre-failure callback arrives");
  Expect(machine.Fail(), "failure transition succeeds");
  Expect(machine.summary().state == ShutdownState::kFailed,
         "failure state is recorded");
  Expect(machine.summary().result == StorageFlushResult::kFailed,
         "failure result is recorded");
  Expect(!machine.AcknowledgePartition(), "post-failure callback is rejected");
}

void TimeoutIsNeverReportedAsSuccess() {
  ShutdownStateMachine machine;

  Expect(machine.BeginDrain(2), "timeout drain begins");
  Expect(machine.AcknowledgePartition(), "pre-timeout callback arrives");
  Expect(machine.TimeOut(), "timeout transition succeeds");
  Expect(machine.summary().state == ShutdownState::kFailed,
         "timeout enters failed state");
  Expect(machine.summary().result == StorageFlushResult::kTimedOut,
         "timeout result is recorded");
  Expect(machine.summary().acknowledged == 1u,
         "timeout preserves acknowledgement count");
}

void DestructionHasExplicitFinalStates() {
  ShutdownStateMachine machine;

  Expect(machine.BeginDrain(0), "destruction drain begins");
  Expect(machine.BeginDestroy(), "destruction begins");
  Expect(machine.summary().state == ShutdownState::kDestroying,
         "destroying state is recorded");
  Expect(machine.MarkStopped(), "stopped transition succeeds");
  Expect(machine.summary().state == ShutdownState::kStopped,
         "stopped state is recorded");
  Expect(machine.summary().result == StorageFlushResult::kComplete,
         "complete result survives destruction");
}

void FailedFlushCanStopWithoutMaskingFailure() {
  ShutdownStateMachine machine;

  Expect(machine.BeginDrain(1), "failed-stop drain begins");
  Expect(machine.Fail(), "failed-stop failure transition succeeds");
  Expect(machine.BeginDestroy(), "failed-stop destruction begins");
  Expect(machine.MarkStopped(), "failed-stop reaches stopped");
  Expect(machine.summary().state == ShutdownState::kStopped,
         "failed flush reaches stopped state");
  Expect(machine.summary().result == StorageFlushResult::kFailed,
         "failure survives stopped state");
}

void TimedOutFlushCanStopWithoutMaskingTimeout() {
  ShutdownStateMachine machine;

  Expect(machine.BeginDrain(1), "timed-out stop drain begins");
  Expect(machine.TimeOut(), "timed-out stop timeout succeeds");
  Expect(machine.BeginDestroy(), "timed-out stop destruction begins");
  Expect(machine.MarkStopped(), "timed-out stop reaches stopped");
  Expect(machine.summary().state == ShutdownState::kStopped,
         "timed-out flush reaches stopped state");
  Expect(machine.summary().result == StorageFlushResult::kTimedOut,
         "timeout survives stopped state");
}

void InvalidTransitionsDoNotChangeState() {
  ShutdownStateMachine machine;

  Expect(!machine.AcknowledgePartition(), "early callback is rejected");
  Expect(!machine.Fail(), "early failure is rejected");
  Expect(!machine.TimeOut(), "early timeout is rejected");
  Expect(!machine.BeginDestroy(), "early destruction is rejected");
  Expect(!machine.MarkStopped(), "early stopped is rejected");
  Expect(machine.summary().state == ShutdownState::kRunning,
         "invalid transitions preserve running state");
}

}  // namespace
}  // namespace carbonyl

int main() {
  carbonyl::ZeroPartitionsCompletesImmediately();
  carbonyl::OnePartitionRequiresOneAcknowledgement();
  carbonyl::MultiplePartitionsRequireEveryAcknowledgement();
  carbonyl::RepeatedShutdownAndCallbackAreIdempotent();
  carbonyl::CallbackFailureIsNeverReportedAsSuccess();
  carbonyl::TimeoutIsNeverReportedAsSuccess();
  carbonyl::DestructionHasExplicitFinalStates();
  carbonyl::FailedFlushCanStopWithoutMaskingFailure();
  carbonyl::TimedOutFlushCanStopWithoutMaskingTimeout();
  carbonyl::InvalidTransitionsDoNotChangeState();

  if (carbonyl::failures != 0) {
    std::cerr << "FAIL: " << carbonyl::failures
              << " shutdown state-machine assertions failed" << std::endl;
    return 1;
  }
  std::cout << "PASS: 10 shutdown state-machine cases" << std::endl;
  return 0;
}
