module GitPuller.Infrastructure.BatchRunner
  ( run
  ) where

import Control.Concurrent.MVar (newMVar, withMVar)
import GitPuller.Application.Program (Program (..))
import GitPuller.Application.Roles (Cast (..), Observer (..), perform)
import GitPuller.Infrastructure.Exclusion qualified as Exclusion
import GitPuller.Infrastructure.WorkerPool qualified as WorkerPool

run :: Cast IO -> Int -> Program result -> IO result
run cast jobs action = do
  reporting <- newMVar ()
  exclusion <- Exclusion.new
  let serialized = cast {observer = Observer (withMVar reporting . const . notify (observer cast))}
      execute :: Bool -> Int -> Program result -> IO result
      execute _ _ (Finished result) = pure result
      execute locked concurrency (Await request resume) =
        perform serialized request >>= execute locked concurrency . resume
      execute locked concurrency (Concurrently programs resume) =
        WorkerPool.mapConcurrently concurrency (execute locked 1) programs
          >>= execute locked concurrency . resume
      execute locked concurrency (Exclusively resource program resume)
        | locked = ioError (userError "Cannot nest exclusive program scopes")
        | otherwise =
            Exclusion.within exclusion resource (execute True concurrency program)
              >>= execute False concurrency . resume
  execute False jobs action
