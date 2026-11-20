module GitPuller.Domain.Discovery
  ( EntryKind (..)
  , Entry (..)
  , Candidate (..)
  , Listing (..)
  , Discovery (..)
  , start
  , location
  , afterListings
  ) where

import Data.List (sortOn)
import Data.List.NonEmpty (NonEmpty (..), nonEmpty)
import System.FilePath ((</>))

data EntryKind = Directory | Regular | Other | Unavailable
  deriving (Eq, Show)

data Entry = Entry
  { path :: FilePath
  , kind :: EntryKind
  }
  deriving (Eq, Show)

data Candidate = Worktree FilePath
               | Inaccessible FilePath String
  deriving (Eq, Show)

data Listing = Listing
  { directory :: FilePath
  , entries   :: Either String [Entry]
  }
  deriving (Eq, Show)

data Discovery = Exploring (NonEmpty FilePath) [Candidate]
               | Complete [Candidate]
  deriving (Eq, Show)

data Wave = Wave
  { unexplored :: [FilePath]
  , candidates :: [Candidate]
  , discovered :: Int
  }

start :: FilePath -> Discovery
start root = Exploring (root :| []) []

location :: Candidate -> FilePath
location (Worktree worktree)           = worktree
location (Inaccessible inaccessible _) = inaccessible

afterListings :: Discovery -> [Listing] -> (Discovery, Int)
afterListings (Complete found) _ = (Complete found, 0)
afterListings (Exploring _ found) listings = (next, discovered wave)
  where
    wave = foldl' absorb Wave {unexplored = [], candidates = found, discovered = 0} listings
    next = case nonEmpty (unexplored wave) of
      Nothing          -> Complete (sortOn location (candidates wave))
      Just directories -> Exploring directories (candidates wave)

include :: Candidate -> Wave -> Wave
include candidate wave = wave {candidates = candidate : candidates wave}

absorb :: Wave -> Listing -> Wave
absorb wave listing = case entries listing of
  Left diagnostic -> include (Inaccessible (directory listing) diagnostic) wave
  Right listed
    | any (isMetadata (directory listing)) listed -> recordWorktree (directory listing) wave
    | otherwise -> foldl' visit wave listed

isMetadata :: FilePath -> Entry -> Bool
isMetadata parent entry =
  path entry == parent </> ".git" && kind entry `elem` [Directory, Regular]

recordWorktree :: FilePath -> Wave -> Wave
recordWorktree root wave = (include (Worktree root) wave) {discovered = discovered wave + 1}

visit :: Wave -> Entry -> Wave
visit wave entry = case kind entry of
  Unavailable -> include (Inaccessible (path entry) "cannot inspect path") wave
  Directory   -> wave {unexplored = path entry : unexplored wave}
  Regular     -> wave
  Other       -> wave
