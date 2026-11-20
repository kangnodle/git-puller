module GitPuller.Infrastructure.Filesystem
  ( PathKind (..)
  , pathKind
  , listDirectory
  , normalizeRoot
  ) where

import Control.Exception (IOException, try)
import Data.List (dropWhileEnd)
import GitPuller.Domain.Discovery (Entry (..))
import GitPuller.Domain.Discovery qualified as Discovery
import GitPuller.Infrastructure.Failure qualified as Failure
import GitPuller.Infrastructure.PathKind (PathKind (..))
import GitPuller.Infrastructure.PathStatus (pathKind)
import System.Directory qualified as Directory
import System.FilePath (isPathSeparator, (</>))

entry :: FilePath -> FilePath -> IO Entry
entry parent name = Entry location . entryKind <$> pathKind location
  where
    location = parent </> name
    entryKind Directory   = Discovery.Directory
    entryKind Regular     = Discovery.Regular
    entryKind Missing     = Discovery.Unavailable
    entryKind Unavailable = Discovery.Unavailable
    entryKind Symlink     = Discovery.Other
    entryKind Other       = Discovery.Other

listDirectory :: FilePath -> IO (Either String [Entry])
listDirectory location = do
  listed <- try (Directory.listDirectory location)
  case listed of
    Left failure -> pure (Left (Failure.reasonWithLocation failure))
    Right names  -> Right <$> traverse (entry location) names

normalizeRoot :: FilePath -> IO (Either String FilePath)
normalizeRoot location = do
  kind <- pathKind trimmed
  case kind of
    Directory -> either unreadable Right <$> try readableRoot
    _         -> pure (Left "start path must be a readable directory")
  where
    trimmed = case dropWhileEnd isPathSeparator location of
      ""             -> take 1 location
      withoutSlashes -> withoutSlashes
    readableRoot = do
      root <- Directory.canonicalizePath trimmed
      root <$ Directory.listDirectory root
    unreadable :: IOException -> Either String FilePath
    unreadable _ = Left "cannot read start directory"
