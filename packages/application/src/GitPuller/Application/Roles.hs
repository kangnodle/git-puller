{-# LANGUAGE GADTs #-}

module GitPuller.Application.Roles
  ( Surveyor (..)
  , Inspector (..)
  , Updater (..)
  , Observer (..)
  , Cast (..)
  , perform
  ) where

import GitPuller.Application.Event (Event)
import GitPuller.Application.Program (Request (..))
import GitPuller.Domain.Discovery (Entry)
import GitPuller.Domain.Repository (Inspection)

newtype Surveyor effect = Surveyor { listDirectory :: FilePath -> effect (Either String [Entry]) }

newtype Inspector effect = Inspector { inspectRepository :: FilePath -> effect (Either String Inspection) }

newtype Updater effect = Updater { pull :: FilePath -> effect (Either String ()) }

newtype Observer effect = Observer { notify :: Event -> effect () }

data Cast effect = Cast
  { surveyor  :: Surveyor effect
  , inspector :: Inspector effect
  , updater   :: Updater effect
  , observer  :: Observer effect
  }

perform :: Cast effect -> Request reply -> effect reply
perform cast request = case request of
  ListDirectory location     -> listDirectory (surveyor cast) location
  InspectRepository location -> inspectRepository (inspector cast) location
  Pull location              -> pull (updater cast) location
  Report event               -> notify (observer cast) event
