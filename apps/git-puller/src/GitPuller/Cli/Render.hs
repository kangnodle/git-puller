module GitPuller.Cli.Render
  ( quoted
  , reason
  , outcome
  , summary
  , summaryTable
  , progress
  , progressBar
  ) where

import Data.Char (ord, toUpper)
import Data.List (intercalate)
import GitPuller.Domain.Outcome (Outcome (..), Status (..), Summary (..), summarize)
import GitPuller.Domain.Repository (SkipReason (..))
import Numeric (showHex)

quoted :: String -> String
quoted text = "\"" <> concatMap escape text <> "\""
  where
    escape '"' = "\\\""
    escape '\\' = "\\\\"
    escape '\a' = "\\a"
    escape '\b' = "\\b"
    escape '\t' = "\\t"
    escape '\n' = "\\n"
    escape '\v' = "\\v"
    escape '\f' = "\\f"
    escape '\r' = "\\r"
    escape character
      | unprintable (ord character) = "\\x" <> map toUpper (showHex (ord character) ";")
      | otherwise = [character]
    unprintable code =
      code < 32 || (code >= 127 && code <= 159) || code == 0x2028 || code == 0x2029

reason :: SkipReason -> String
reason UnbornBranch     = "unborn-branch"
reason MergeInProgress  = "merge-in-progress"
reason RebaseInProgress = "rebase-in-progress"
reason DetachedHead     = "detached-head"
reason NoUpstream       = "no-upstream"
reason Dirty            = "dirty"
reason Submodule        = "submodule"

outcome :: Bool -> Outcome -> String
outcome verbose result = case status result of
  Updated -> "updated " <> location
  Planned -> "planned " <> location
  Skipped why -> "skipped " <> location <> " " <> reason why
  Failed diagnostic -> "failed " <> location <> " " <> (if verbose then quoted diagnostic else diagnostic)
  where
    location = quoted (path result)

summary :: [Outcome] -> String
summary outcomes =
  "Summary updated="
    <> show (updated counts)
    <> " planned="
    <> show (planned counts)
    <> " skipped="
    <> show (skipped counts)
    <> " failed="
    <> show (failed counts)
  where
    counts = summarize outcomes

summaryTable :: Bool -> [Outcome] -> String
summaryTable colors outcomes =
  intercalate "\n"
    ( [border '┌' '┬' '┐', row id "Status" "Count", separator]
        <> map renderCount statuses
        <> [separator, row id "Total" totalText, border '└' '┴' '┘']
    )
  where
    counts = summarize outcomes
    statuses =
      [ ("Updated", 92, updated counts)
      , ("Planned", 94, planned counts)
      , ("Skipped", 93, skipped counts)
      , ("Failed", 91, failed counts)
      ]
    totalText = show (updated counts + planned counts + skipped counts + failed counts)
    statusWidth = length "Updated"
    countWidth = max (length "Count") (length totalText)
    border left middle right =
      [left] <> replicate (statusWidth + 2) '─' <> [middle]
        <> replicate (countWidth + 2) '─' <> [right]
    separator = border '├' '┼' '┤'
    row style label value =
      "│ " <> style (label <> replicate (statusWidth - length label) ' ')
        <> " │ " <> replicate (countWidth - length value) ' ' <> value <> " │"
    renderCount (label, color, count) = row (colorize colors color) label (show count)

progress :: Int -> Int -> String
progress completed total =
  "[" <> replicate filled '#' <> replicate (barWidth - filled) '-' <> "] "
    <> processed completed total
  where
    filled = progressUnits barWidth completed total

progressBar :: Bool -> Int -> Int -> String
progressBar colors completed total =
  "[" <> colorize colors 96 (replicate filled '█') <> replicate (barWidth - filled) '░' <> "] "
    <> processed completed total <> " · " <> show (progressUnits 100 completed total) <> "%"
  where
    filled = progressUnits barWidth completed total

barWidth :: Int
barWidth = 20

progressUnits :: Int -> Int -> Int -> Int
progressUnits units completed total
  | total == 0 = units
  | otherwise = fromInteger (toInteger units * toInteger completed `div` toInteger total)

processed :: Int -> Int -> String
processed completed total = show completed <> "/" <> show total <> " processed"

colorize :: Bool -> Int -> String -> String
colorize enabled color value
  | enabled && not (null value) = "\ESC[" <> show color <> "m" <> value <> "\ESC[0m"
  | otherwise = value
