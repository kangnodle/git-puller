module GitPuller.Domain.Update
  ( Mode (..)
  , Step (..)
  , InspectionPending
  , PullPending
  , begin
  , worktreeToInspect
  , afterInspection
  , worktreeToPull
  , commonDirectory
  , afterPull
  ) where

import GitPuller.Domain.Discovery (Candidate (..))
import GitPuller.Domain.Outcome (Outcome (..), Status (..))
import GitPuller.Domain.Repository
  ( Eligibility (..)
  , Inspection (..)
  , SkipReason (Submodule)
  , classify
  )

data Mode = DryRun | Apply
  deriving (Eq, Show)

data Step pending = Pending pending
                  | Settled Outcome
  deriving (Eq, Show)

data InspectionPending = InspectionPending FilePath Mode
  deriving (Eq, Show)

data PullPending = PullPending FilePath FilePath
  deriving (Eq, Show)

begin :: Mode -> Candidate -> Step InspectionPending
begin mode (Worktree worktree) = Pending (InspectionPending worktree mode)
begin _ (Inaccessible location diagnostic) = Settled (Outcome location (Failed diagnostic))

worktreeToInspect :: InspectionPending -> FilePath
worktreeToInspect (InspectionPending worktree _) = worktree

afterInspection :: InspectionPending -> Either String Inspection -> Step PullPending
afterInspection (InspectionPending worktree mode) inspection = case inspection of
  Left diagnostic -> settle (Failed diagnostic)
  Right Nested -> settle (Skipped Submodule)
  Right (Standalone shared state) -> case (classify state, mode) of
    (Ineligible reason, _) -> settle (Skipped reason)
    (Eligible, DryRun)     -> settle Planned
    (Eligible, Apply)      -> Pending (PullPending worktree shared)
  where
    settle = Settled . Outcome worktree

worktreeToPull :: PullPending -> FilePath
worktreeToPull (PullPending worktree _) = worktree

commonDirectory :: PullPending -> FilePath
commonDirectory (PullPending _ shared) = shared

afterPull :: PullPending -> Either String () -> Outcome
afterPull pending result = Outcome (worktreeToPull pending) (either Failed (const Updated) result)
