module GitPuller.Infrastructure.PathStatus
  ( pathKind
  ) where

import Control.Exception (IOException, try)
import Foreign.C.Error (Errno (..), eNOENT, eNOTDIR)
import GHC.IO.Exception (IOException (ioe_errno))
import GitPuller.Infrastructure.PathKind (PathKind (..))
import System.Posix.Files
  ( getSymbolicLinkStatus
  , isDirectory
  , isRegularFile
  , isSymbolicLink
  )

pathKind :: FilePath -> IO PathKind
pathKind location = either unreadable readable <$> try (getSymbolicLinkStatus location)
  where
    readable status
      | isDirectory status = Directory
      | isRegularFile status = Regular
      | isSymbolicLink status = Symlink
      | otherwise = Other
    unreadable :: IOException -> PathKind
    unreadable failure
      | fmap Errno (ioe_errno failure) `elem` [Just eNOENT, Just eNOTDIR] = Missing
      | otherwise = Unavailable
