#include "carbonyl/src/browser/storage_flush_coordinator.h"

#include "testing/gtest/include/gtest/gtest.h"

namespace carbonyl {
namespace {

TEST(ShutdownStateMachineTest, ZeroPartitionsCompletesImmediately) {
  ShutdownStateMachine machine;

  EXPECT_TRUE(machine.BeginDrain(0));
  EXPECT_EQ(machine.summary().state, ShutdownState::kFlushed);
  EXPECT_EQ(machine.summary().result, StorageFlushResult::kComplete);
  EXPECT_EQ(machine.summary().partitions, 0u);
  EXPECT_EQ(machine.summary().acknowledged, 0u);
}

TEST(ShutdownStateMachineTest, OnePartitionRequiresOneAcknowledgement) {
  ShutdownStateMachine machine;

  EXPECT_TRUE(machine.BeginDrain(1));
  EXPECT_EQ(machine.summary().state, ShutdownState::kDraining);
  EXPECT_TRUE(machine.AcknowledgePartition());
  EXPECT_EQ(machine.summary().state, ShutdownState::kFlushed);
  EXPECT_EQ(machine.summary().result, StorageFlushResult::kComplete);
}

TEST(ShutdownStateMachineTest, MultiplePartitionsRequireEveryAcknowledgement) {
  ShutdownStateMachine machine;

  EXPECT_TRUE(machine.BeginDrain(3));
  EXPECT_TRUE(machine.AcknowledgePartition());
  EXPECT_TRUE(machine.AcknowledgePartition());
  EXPECT_EQ(machine.summary().state, ShutdownState::kDraining);
  EXPECT_EQ(machine.summary().acknowledged, 2u);
  EXPECT_TRUE(machine.AcknowledgePartition());
  EXPECT_EQ(machine.summary().state, ShutdownState::kFlushed);
}

TEST(ShutdownStateMachineTest, RepeatedShutdownAndCallbackAreIdempotent) {
  ShutdownStateMachine machine;

  EXPECT_TRUE(machine.BeginDrain(1));
  EXPECT_FALSE(machine.BeginDrain(1));
  EXPECT_TRUE(machine.AcknowledgePartition());
  EXPECT_FALSE(machine.AcknowledgePartition());
  EXPECT_EQ(machine.summary().acknowledged, 1u);
}

TEST(ShutdownStateMachineTest, CallbackFailureIsNeverReportedAsSuccess) {
  ShutdownStateMachine machine;

  EXPECT_TRUE(machine.BeginDrain(2));
  EXPECT_TRUE(machine.AcknowledgePartition());
  EXPECT_TRUE(machine.Fail());
  EXPECT_EQ(machine.summary().state, ShutdownState::kFailed);
  EXPECT_EQ(machine.summary().result, StorageFlushResult::kFailed);
  EXPECT_FALSE(machine.AcknowledgePartition());
}

TEST(ShutdownStateMachineTest, TimeoutIsNeverReportedAsSuccess) {
  ShutdownStateMachine machine;

  EXPECT_TRUE(machine.BeginDrain(2));
  EXPECT_TRUE(machine.AcknowledgePartition());
  EXPECT_TRUE(machine.TimeOut());
  EXPECT_EQ(machine.summary().state, ShutdownState::kFailed);
  EXPECT_EQ(machine.summary().result, StorageFlushResult::kTimedOut);
  EXPECT_EQ(machine.summary().acknowledged, 1u);
}

TEST(ShutdownStateMachineTest, DestructionHasExplicitFinalStates) {
  ShutdownStateMachine machine;

  EXPECT_TRUE(machine.BeginDrain(0));
  EXPECT_TRUE(machine.BeginDestroy());
  EXPECT_EQ(machine.summary().state, ShutdownState::kDestroying);
  EXPECT_TRUE(machine.MarkStopped());
  EXPECT_EQ(machine.summary().state, ShutdownState::kStopped);
  EXPECT_EQ(machine.summary().result, StorageFlushResult::kComplete);
}

TEST(ShutdownStateMachineTest, FailedFlushCanStopWithoutMaskingFailure) {
  ShutdownStateMachine machine;

  EXPECT_TRUE(machine.BeginDrain(1));
  EXPECT_TRUE(machine.Fail());
  EXPECT_TRUE(machine.BeginDestroy());
  EXPECT_TRUE(machine.MarkStopped());
  EXPECT_EQ(machine.summary().state, ShutdownState::kStopped);
  EXPECT_EQ(machine.summary().result, StorageFlushResult::kFailed);
}

TEST(ShutdownStateMachineTest, TimedOutFlushCanStopWithoutMaskingTimeout) {
  ShutdownStateMachine machine;

  EXPECT_TRUE(machine.BeginDrain(1));
  EXPECT_TRUE(machine.TimeOut());
  EXPECT_TRUE(machine.BeginDestroy());
  EXPECT_TRUE(machine.MarkStopped());
  EXPECT_EQ(machine.summary().state, ShutdownState::kStopped);
  EXPECT_EQ(machine.summary().result, StorageFlushResult::kTimedOut);
}

TEST(ShutdownStateMachineTest, InvalidTransitionsDoNotChangeState) {
  ShutdownStateMachine machine;

  EXPECT_FALSE(machine.AcknowledgePartition());
  EXPECT_FALSE(machine.Fail());
  EXPECT_FALSE(machine.TimeOut());
  EXPECT_FALSE(machine.BeginDestroy());
  EXPECT_FALSE(machine.MarkStopped());
  EXPECT_EQ(machine.summary().state, ShutdownState::kRunning);
}

}  // namespace
}  // namespace carbonyl
