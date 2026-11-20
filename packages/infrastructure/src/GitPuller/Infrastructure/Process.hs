module GitPuller.Infrastructure.Process
  ( CompletedProcess (..)
  , run
  ) where

import Control.Exception (bracket, finally, try)
import Data.Bifunctor (first)
import Data.Foldable (traverse_)
import GHC.IO.Encoding (getFileSystemEncoding)
import GitPuller.Infrastructure.Failure qualified as Failure
import System.Directory (getTemporaryDirectory, removeFile)
import System.Exit (ExitCode)
import System.IO
  ( Handle
  , IOMode (ReadMode)
  , hClose
  , hGetContents'
  , hSetEncoding
  , openBinaryTempFile
  , withFile
  )
import System.Process
  ( CreateProcess (close_fds, env, std_err, std_in, std_out)
  , StdStream (CreatePipe, UseHandle)
  , proc
  , waitForProcess
  , withCreateProcess
  )

data CompletedProcess = CompletedProcess
  { status     :: ExitCode
  , output     :: String
  , diagnostic :: String
  }
  deriving (Eq, Show)

readCaptured :: FilePath -> IO String
readCaptured location = withFile location ReadMode $ \captured -> do
  getFileSystemEncoding >>= hSetEncoding captured
  hGetContents' captured

withCapture :: (Handle -> IO result) -> IO (result, String)
withCapture action = do
  directory <- getTemporaryDirectory
  bracket (openBinaryTempFile directory "git-puller-.capture") discard $ \(location, capture) -> do
    result <- action capture
    hClose capture
    captured <- readCaptured location
    pure (result, captured)
  where
    discard (location, capture) = hClose capture `finally` removeFile location

run :: FilePath -> [String] -> [(String, String)] -> IO (Either String CompletedProcess)
run program arguments environment = first Failure.reason <$> try captured
  where
    captured = do
      ((exit, errors), standard) <-
        withCapture $ \standardOutput ->
          withCapture $ \standardError ->
            withCreateProcess
              (specification standardOutput standardError)
              (\standardInput _ _ child -> traverse_ hClose standardInput >> waitForProcess child)
      pure CompletedProcess {status = exit, output = standard, diagnostic = errors}
    specification standardOutput standardError =
      (proc program arguments)
        { env = Just environment
        , std_in = CreatePipe
        , std_out = UseHandle standardOutput
        , std_err = UseHandle standardError
        , close_fds = True
        }
