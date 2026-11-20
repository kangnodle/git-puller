module GitPuller.Infrastructure.TerminalCapability
  ( supportsEscapes
  ) where

import System.Environment (lookupEnv)
import System.IO (Handle, hIsTerminalDevice)

supportsEscapes :: Handle -> IO Bool
supportsEscapes handle = do
  terminalType <- lookupEnv "TERM"
  if terminalType `elem` [Nothing, Just "", Just "dumb"]
    then pure False
    else hIsTerminalDevice handle
