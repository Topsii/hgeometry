module Geometry.SoS.Determinant where

import           Data.Sign
import           Data.RealNumber.Symbolic
import           Geometry.Matrix


-- | pre: computes the sign of the determinant
signDet   :: (HasDeterminant d, Ord i, Num r, Ord r) => Matrix d d (Symbolic i r) -> Sign
signDet m = case det m `compare` 0 of
              LT -> Negative
              GT -> Positive
              EQ -> error "signDet: determinant is zero! this should not happen!"
