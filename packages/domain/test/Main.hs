module Main
  ( main
  ) where

import Data.Foldable (for_, toList)
import Data.List.NonEmpty (NonEmpty (..))
import GitPuller.Domain.Discovery
  ( Candidate (..)
  , Discovery (..)
  , Entry (..)
  , EntryKind (..)
  , Listing (..)
  )
import GitPuller.Domain.Discovery qualified as Discovery
import GitPuller.Domain.Outcome (Outcome (..), Status (..), Summary (..))
import GitPuller.Domain.Outcome qualified as Outcome
import GitPuller.Domain.Repository
  ( Branch (..)
  , Eligibility (..)
  , Inspection (..)
  , Operation (..)
  , SkipReason (..)
  , State (..)
  , classify
  )
import GitPuller.Domain.Update (Mode (..), Step (..))
import GitPuller.Domain.Update qualified as Update
import Test.Hspec (Spec, describe, expectationFailure, hspec, it, shouldBe)

main :: IO ()
main = hspec $ do
  repositorySpec
  discoverySpec
  outcomeSpec
  updateSpec

clean :: State
clean = State {branch = Attached, operation = Idle, upstream = True, dirty = False}

repositorySpec :: Spec
repositorySpec = describe "Repository.classify" $ do
  it "reports an unborn branch before anything else" $
    classify (State Unborn Merge False True) `shouldBe` Ineligible UnbornBranch
  it "reports a merge before a detached head" $
    classify (State Detached Merge False True) `shouldBe` Ineligible MergeInProgress
  it "reports a rebase before a detached head" $
    classify (State Detached Rebase False True) `shouldBe` Ineligible RebaseInProgress
  it "reports a detached head before a missing upstream" $
    classify (State Detached Idle False True) `shouldBe` Ineligible DetachedHead
  it "reports a missing upstream before a dirty worktree" $
    classify (State Attached Idle False True) `shouldBe` Ineligible NoUpstream
  it "reports a dirty worktree" $
    classify (State Attached Idle True True) `shouldBe` Ineligible Dirty
  it "accepts a clean tracking branch" $
    classify clean `shouldBe` Eligible

outcomeSpec :: Spec
outcomeSpec = describe "Outcome" $ do
  let outcomes = [Outcome "a" Planned, Outcome "b" (Failed "error")]
  it "counts outcomes by status" $
    Outcome.summarize outcomes
      `shouldBe` Summary {updated = 0, planned = 1, skipped = 0, failed = 1}
  it "counts every status" $
    Outcome.summarize [Outcome "a" Updated, Outcome "b" (Skipped Dirty), Outcome "c" Updated]
      `shouldBe` Summary {updated = 2, planned = 0, skipped = 1, failed = 0}
  it "identifies a batch with a failed outcome" $
    Outcome.hasFailures outcomes `shouldBe` True
  it "accepts a batch without failures" $ do
    Outcome.hasFailures [] `shouldBe` False
    Outcome.hasFailures [Outcome "a" (Skipped Dirty)] `shouldBe` False

updateSpec :: Spec
updateSpec = describe "Update" $ do
  let standalone = Right . Standalone "/shared/.git"
      inspect mode reply = case Update.begin mode (Worktree "/a") of
        Pending inspection -> Update.afterInspection inspection reply
        Settled outcome    -> Settled outcome
      pulled reply = case inspect Apply (standalone clean) of
        Pending pull -> Just (Update.afterPull pull reply)
        Settled _    -> Nothing
  it "carries the discovered worktree path into inspection" $
    case Update.begin Apply (Worktree "/a") of
      Pending inspection -> Update.worktreeToInspect inspection `shouldBe` "/a"
      Settled outcome    -> expectationFailure ("unexpected outcome: " <> show outcome)
  it "begins an inaccessible directory as settled with its failure" $
    Update.begin Apply (Inaccessible "/a" "blocked")
      `shouldBe` Settled (Outcome "/a" (Failed "blocked"))
  it "plans an eligible repository during a dry run" $
    inspect DryRun (standalone clean) `shouldBe` Settled (Outcome "/a" Planned)
  it "keeps the worktree path and its shared Git directory distinct when applying" $
    case inspect Apply (standalone clean) of
      Pending pull ->
        (Update.worktreeToPull pull, Update.commonDirectory pull)
          `shouldBe` ("/a", "/shared/.git")
      Settled outcome -> expectationFailure ("unexpected outcome: " <> show outcome)
  for_ [DryRun, Apply] $ \mode -> describe (show mode) $ do
    it "skips an ineligible repository" $
      inspect mode (standalone clean {dirty = True})
        `shouldBe` Settled (Outcome "/a" (Skipped Dirty))
    it "skips a submodule" $
      inspect mode (Right Nested) `shouldBe` Settled (Outcome "/a" (Skipped Submodule))
    it "fails when inspection fails" $
      inspect mode (Left "inspection failed")
        `shouldBe` Settled (Outcome "/a" (Failed "inspection failed"))
  it "marks a successful pull as updated at the worktree path" $
    pulled (Right ()) `shouldBe` Just (Outcome "/a" Updated)
  it "marks a failed pull as failed at the worktree path" $
    pulled (Left "pull failed") `shouldBe` Just (Outcome "/a" (Failed "pull failed"))

discoverySpec :: Spec
discoverySpec = describe "Discovery" $ do
  let rootListing = Discovery.afterListings (Discovery.start "/root") . pure . Listing "/root"
      listed listing directory = Listing directory (listing directory)
      explore listing discovery = case discovery of
        Complete found -> (found, [], 0 :: Int)
        Exploring directories _ ->
          let wave = toList directories
              (next, discovered) = Discovery.afterListings discovery (map (listed listing) wave)
              (found, waves, total) = explore listing next
           in (found, wave : waves, discovered + total)
  it "starts by exploring the root" $
    Discovery.start "/root" `shouldBe` Exploring ("/root" :| []) []
  it "completes without candidates when the root holds no worktree" $
    rootListing (Right [Entry "/root/file" Regular]) `shouldBe` (Complete [], 0)
  it "records the root as inaccessible when it cannot be listed" $
    rootListing (Left "blocked") `shouldBe` (Complete [Inaccessible "/root" "blocked"], 0)
  it "recognizes a directory or a file named .git as worktree metadata" $ do
    rootListing (Right [Entry "/root/.git" Directory])
      `shouldBe` (Complete [Worktree "/root"], 1)
    rootListing (Right [Entry "/root/.git" Regular])
      `shouldBe` (Complete [Worktree "/root"], 1)
  it "leaves a completed discovery unchanged" $
    Discovery.afterListings
      (Complete [Worktree "/root"])
      [Listing "/root" (Right [Entry "/root/.git" Directory])]
      `shouldBe` (Complete [Worktree "/root"], 0)
  it "explores every directory of a level in one wave and yields candidates in path order" $ do
    let listing "/root" =
          Right
            [ Entry "/root/z" Directory
            , Entry "/root/link" Other
            , Entry "/root/gone" Unavailable
            , Entry "/root/a" Directory
            , Entry "/root/b" Directory
            ]
        listing "/root/a" = Left "blocked"
        listing directory = Right [Entry (directory <> "/.git") Regular]
    explore listing (Discovery.start "/root")
      `shouldBe` (
                   [ Inaccessible "/root/a" "blocked"
                   , Worktree "/root/b"
                   , Inaccessible "/root/gone" "cannot inspect path"
                   , Worktree "/root/z"
                   ]
                 , [["/root"], ["/root/b", "/root/a", "/root/z"]]
                 , 2
                 )
  it "does not explore inside a worktree" $
    rootListing
      ( Right
          [ Entry "/root/deep" Directory
          , Entry "/root/gone" Unavailable
          , Entry "/root/.git" Directory
          ]
      )
      `shouldBe` (Complete [Worktree "/root"], 1)
  it "keeps exploring past an unreadable .git entry" $
    rootListing (Right [Entry "/root/.git" Unavailable, Entry "/root/deep" Directory])
      `shouldBe` (Exploring ("/root/deep" :| []) [Inaccessible "/root/.git" "cannot inspect path"], 0)
