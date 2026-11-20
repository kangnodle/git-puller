module GitPuller.Infrastructure.PathStatus
  ( pathKind
  ) where

import Control.Exception (IOException, try)
import GitPuller.Infrastructure.PathKind (PathKind (..))
import System.Directory (doesDirectoryExist, doesFileExist, pathIsSymbolicLink)
import System.IO.Error (isDoesNotExistError)

pathKind :: FilePath -> IO PathKind
pathKind location = either unreadable id <$> try classify
  where
    classify = do
      link <- pathIsSymbolicLink location
      if link then pure Symlink else unlinked
    unlinked = do
      directory <- doesDirectoryExist location
      if directory then pure Directory else file
    file = do
      regular <- doesFileExist location
      pure (if regular then Regular else Other)
    unreadable :: IOException -> PathKind
    unreadable failure
      | isDoesNotExistError failure = Missing
      | otherwise = Unavailable
