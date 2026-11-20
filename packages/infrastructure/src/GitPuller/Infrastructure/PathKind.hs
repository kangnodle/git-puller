module GitPuller.Infrastructure.PathKind
  ( PathKind (..)
  ) where

data PathKind = Directory | Regular | Symlink | Other | Missing | Unavailable
  deriving (Eq, Show)
