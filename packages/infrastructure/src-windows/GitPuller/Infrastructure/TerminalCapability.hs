module GitPuller.Infrastructure.TerminalCapability
  ( supportsEscapes
  ) where

import Control.Exception (IOException, try)
import Data.Bits ((.|.))
import System.Environment (lookupEnv)
import System.IO (Handle, hIsTerminalDevice)
import System.Win32.Console
  ( eNABLE_VIRTUAL_TERMINAL_PROCESSING
  , getConsoleMode
  , setConsoleMode
  )
import System.Win32.Types (withHandleToHANDLE)

supportsEscapes :: Handle -> IO Bool
supportsEscapes handle = do
  terminalType <- lookupEnv "TERM"
  console <- hIsTerminalDevice handle
  if terminalType == Just "dumb" || not console
    then pure False
    else enableVirtualTerminal handle

enableVirtualTerminal :: Handle -> IO Bool
enableVirtualTerminal handle = either unsupported (const True) <$> try enable
  where
    enable = withHandleToHANDLE handle $ \native -> do
      mode <- getConsoleMode native
      setConsoleMode native (mode .|. eNABLE_VIRTUAL_TERMINAL_PROCESSING)
    unsupported :: IOException -> Bool
    unsupported _ = False
