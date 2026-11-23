module Main
  ( main
  ) where

import Control.Monad (unless, when)
import Data.Foldable (traverse_)
import Data.IORef (IORef, atomicModifyIORef', newIORef)
import GitPuller.Application.Event (Event)
import GitPuller.Application.Roles
  ( Cast (..)
  , Inspector (..)
  , Observer (..)
  , Surveyor (..)
  , Updater (..)
  )
import GitPuller.Application.UpdateWorktrees qualified as UpdateWorktrees
import GitPuller.Cli.Arguments (Command (..), Options (..))
import GitPuller.Cli.Arguments qualified as Arguments
import GitPuller.Cli.Progress (Output (..), Progress)
import GitPuller.Cli.Progress qualified as Progress
import GitPuller.Cli.Render qualified as Render
import GitPuller.Domain.Outcome (Outcome)
import GitPuller.Domain.Outcome qualified as Outcome
import GitPuller.Infrastructure.BatchRunner qualified as BatchRunner
import GitPuller.Infrastructure.Descriptors qualified as Descriptors
import GitPuller.Infrastructure.Encoding qualified as Encoding
import GitPuller.Infrastructure.Filesystem qualified as Filesystem
import GitPuller.Infrastructure.Git qualified as Git
import GitPuller.Infrastructure.Terminal (Terminal (..))
import GitPuller.Infrastructure.Terminal qualified as Terminal
import System.Environment (getArgs, lookupEnv)
import System.Exit (ExitCode (..), exitWith)
import System.IO (hPutStrLn, stderr, stdout)

display :: (Progress -> String) -> Terminal -> Output -> IO ()
display _ terminal (Line text) = writeLine terminal text
display renderProgress terminal (Status progress) = writeProgress terminal (renderProgress progress)

reporter :: Bool -> (Output -> IO ()) -> IORef Progress -> Event -> IO ()
reporter isVerbose emit state event =
  atomicModifyIORef' state (Progress.observe isVerbose event)
    >>= traverse_ emit

startupError :: String -> IO ExitCode
startupError diagnostic = ExitFailure 2 <$ hPutStrLn stderr diagnostic

runBatch :: Options -> FilePath -> (Event -> IO ()) -> IO [Outcome]
runBatch options root reportEvent =
  BatchRunner.run cast (jobs options) (UpdateWorktrees.start (mode options) root)
  where
    cast =
      Cast
        { surveyor = Surveyor {listDirectory = Filesystem.listDirectory}
        , inspector = Inspector {inspectRepository = Git.inspectRepository}
        , updater = Updater {pull = Git.pull}
        , observer = Observer {notify = reportEvent}
        }

update :: Options -> FilePath -> IO ExitCode
update options root = do
  interactiveProgress <- Terminal.isInteractive stderr
  interactiveSummary <- Terminal.isInteractive stdout
  colors <- maybe True null <$> lookupEnv "NO_COLOR"
  let bar = if interactiveProgress then Render.progressBar colors else Render.progress
      summary = if interactiveSummary then Render.summaryTable colors else Render.summary
  outcomes <-
    if interactiveProgress || verbose options
      then Terminal.withProgress interactiveProgress $ \terminal -> do
        state <- newIORef Progress.initial
        let emit = display (Progress.render bar) terminal
        runBatch options root (reporter (verbose options) emit state)
      else runBatch options root (const (pure ()))
  unless (verbose options) (traverse_ (putStrLn . Render.outcome False) outcomes)
  when (null outcomes) (putStrLn "No Git worktrees found.")
  putStrLn (summary outcomes)
  pure (if Outcome.hasFailures outcomes then ExitFailure 1 else ExitSuccess)

run :: Options -> IO ExitCode
run options = do
  Descriptors.limitTo (Descriptors.budget (jobs options))
  normalized <- Filesystem.normalizeRoot (path options)
  case normalized of
    Left diagnostic -> startupError (Render.quoted (path options) <> " " <> diagnostic)
    Right root -> do
      available <- Git.check
      case available of
        Left diagnostic -> startupError ("Cannot run Git. " <> diagnostic)
        Right ()        -> update options root

execute :: [String] -> IO ExitCode
execute arguments = case Arguments.parse arguments of
  Left diagnostic     -> startupError (diagnostic <> "\n" <> Arguments.usage)
  Right Help          -> ExitSuccess <$ putStrLn Arguments.usage
  Right (Run options) -> run options

main :: IO ()
main = do
  Encoding.useLosslessUtf8
  getArgs >>= execute >>= exitWith
