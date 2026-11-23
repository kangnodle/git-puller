module GitPuller.Application.UpdateWorktrees
  ( start
  ) where

import Data.List (sortOn)
import GitPuller.Application.Event (Event (..))
import GitPuller.Application.Interaction.Survey (survey)
import GitPuller.Application.Interaction.Update (update)
import GitPuller.Application.Program (Program, concurrently, report)
import GitPuller.Domain.Outcome (Outcome (..))
import GitPuller.Domain.Update (Mode)

start :: Mode -> FilePath -> Program [Outcome]
start mode root = do
  found <- survey root
  report (Processing (length found))
  sortOn path <$> concurrently (map (update mode) found)
