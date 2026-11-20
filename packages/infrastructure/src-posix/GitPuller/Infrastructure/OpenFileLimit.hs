module GitPuller.Infrastructure.OpenFileLimit
  ( limitTo
  ) where

import System.Posix.Resource
  ( Resource (ResourceOpenFiles)
  , ResourceLimit (..)
  , ResourceLimits (..)
  , getResourceLimit
  , setResourceLimit
  )

bounded :: Integer -> ResourceLimit -> ResourceLimit
bounded allowance current = case current of
  ResourceLimit allowed -> ResourceLimit (min allowed allowance)
  ResourceLimitInfinity -> ResourceLimit allowance
  ResourceLimitUnknown  -> ResourceLimit allowance

limitTo :: Integer -> IO ()
limitTo allowance = do
  limits <- getResourceLimit ResourceOpenFiles
  setResourceLimit
    ResourceOpenFiles
    limits {softLimit = bounded allowance (softLimit limits)}
