module GitPuller.Cli.Progress
  ( Progress (..)
  , Output (..)
  , initial
  , transition
  , observe
  , render
  ) where

import GitPuller.Application.Event (Event (..))
import GitPuller.Cli.Render qualified as Render

data Progress = Surveying Int
              | Working Int Int
  deriving (Eq, Show)

data Output = Line String
            | Status Progress
  deriving (Eq, Show)

initial :: Progress
initial = Surveying 0

transition :: Event -> Progress -> Progress
transition Discovered (Surveying discovered)       = Surveying (discovered + 1)
transition (Processing total) _                    = Working 0 total
transition (Processed _) (Working completed total) = Working (completed + 1) total
transition _ progress                              = progress

observe :: Bool -> Event -> Progress -> (Progress, [Output])
observe verbose event progress = (next, outputs)
  where
    next = transition event progress
    status = Status next
    narrate text = [Line text | verbose]
    outputs = case event of
      Scanning            -> [status]
      Discovered          -> [status]
      Processing _        -> [status]
      Inspecting location -> narrate ("Inspecting " <> Render.quoted location)
      Pulling location    -> narrate ("Pulling " <> Render.quoted location)
      Processed result    -> narrate (Render.outcome verbose result) <> [status]

render :: (Int -> Int -> String) -> Progress -> String
render _ (Surveying discovered) = "Scanning: " <> show discovered <> " repositories found"
render bar (Working completed total) = bar completed total
