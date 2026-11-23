module GitPuller.Domain.Outcome
  ( Status (..)
  , Outcome (..)
  , Summary (..)
  , summarize
  , hasFailures
  ) where

import GitPuller.Domain.Repository (SkipReason)

data Status = Updated
            | Planned
            | Skipped SkipReason
            | Failed String
  deriving (Eq, Show)

data Outcome = Outcome
  { path   :: FilePath
  , status :: Status
  }
  deriving (Eq, Show)

data Summary = Summary
  { updated :: Int
  , planned :: Int
  , skipped :: Int
  , failed  :: Int
  }
  deriving (Eq, Show)

summarize :: [Outcome] -> Summary
summarize = foldl' count (Summary 0 0 0 0)
  where
    count summary outcome = case status outcome of
      Updated   -> summary {updated = updated summary + 1}
      Planned   -> summary {planned = planned summary + 1}
      Skipped _ -> summary {skipped = skipped summary + 1}
      Failed _  -> summary {failed = failed summary + 1}

hasFailures :: [Outcome] -> Bool
hasFailures = any (isFailure . status)
  where
    isFailure (Failed _) = True
    isFailure _          = False
