module GitPuller.Infrastructure.Descriptors
  ( budget
  , limitTo
  ) where

import GitPuller.Infrastructure.OpenFileLimit (limitTo)

budget :: Int -> Integer
budget jobs = max 1024 (64 + 4 * toInteger jobs)
