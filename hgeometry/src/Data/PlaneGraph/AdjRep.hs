--------------------------------------------------------------------------------
-- |
-- Module      :  Data.PlaneGraph.AdjRep
-- Copyright   :  (C) Frank Staals
-- License     :  see the LICENSE file
-- Maintainer  :  Frank Staals
--
-- Data types that help encode/decode a planegraph as a JSON/YAML file.
--
--------------------------------------------------------------------------------
module Data.PlaneGraph.AdjRep( Gr(..)
                             , Vtx(..)
                             , Face(..)
                             ) where

import Data.PlanarGraph.AdjRep(Gr(..), Face(..))
import Data.Aeson
import Geometry.Point
import GHC.Generics (Generic)

--------------------------------------------------------------------------------

-- | A vertex, represented by an id, location, its adjacencies, and its data.
data Vtx v e r = Vtx { id    :: {-# UNPACK #-} !Int
                     , loc   :: !(Point 2 r)
                     , adj   :: [(Int,e)]
                       -- ^ adjacent vertices + data on the
                       -- edge. Idealy adjacencies are given in CCW
                       -- order around the vertex.
                     , vData :: !v
                     } deriving (Generic, Show, Eq, Functor, Foldable, Traversable)

instance (ToJSON r,   ToJSON v, ToJSON e)     => ToJSON   (Vtx v e r) where
  toEncoding = genericToEncoding defaultOptions
instance (FromJSON r, FromJSON v, FromJSON e) => FromJSON (Vtx v e r)
