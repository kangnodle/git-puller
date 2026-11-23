module GitPuller.Application.Interaction.Update
  ( update
  ) where

import GitPuller.Application.Event (Event (..))
import GitPuller.Application.Program (Program, Request (..), await, exclusively, report)
import GitPuller.Domain.Discovery (Candidate)
import GitPuller.Domain.Outcome (Outcome)
import GitPuller.Domain.Update (InspectionPending, Mode, PullPending, Step (..))
import GitPuller.Domain.Update qualified as Update

settle :: Outcome -> Program Outcome
settle outcome = outcome <$ report (Processed outcome)

inspect :: InspectionPending -> Program Outcome
inspect pending = do
  report (Inspecting location)
  result <- await (InspectRepository location)
  case Update.afterInspection pending result of
    Pending eligible -> pull eligible
    Settled outcome  -> settle outcome
  where
    location = Update.worktreeToInspect pending

pull :: PullPending -> Program Outcome
pull pending = do
  result <- exclusively (Update.commonDirectory pending) $ do
    report (Pulling location)
    await (Pull location)
  settle (Update.afterPull pending result)
  where
    location = Update.worktreeToPull pending

update :: Mode -> Candidate -> Program Outcome
update mode candidate = case Update.begin mode candidate of
  Pending pending -> inspect pending
  Settled outcome -> settle outcome
