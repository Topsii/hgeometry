{-# LANGUAGE OverloadedStrings #-}
module Algorithms.Geometry.PolygonTriangulation.TriangulateSpec (spec) where

import           Algorithms.Geometry.PolygonTriangulation.Triangulate
import           Algorithms.Geometry.PolygonTriangulation.Types
import           Control.Lens
import           Data.Ext
import           Geometry
import           Geometry.PlanarSubdivision (PolygonFaceData)
import           Geometry.PolygonSpec ()
import           Data.PlaneGraph
import qualified Data.Vector as V
import           Test.Hspec
import           Test.QuickCheck
import           Test.QuickCheck.Instances ()

spec :: Spec
spec = do
  it "sum (map area (triangulate polygon)) == area polygon" $ do
    property $ \(poly :: SimplePolygon () Rational) ->
      let g = triangulate' @() poly
          trigs = graphPolygons g
      in sum (map area trigs) === area poly
  it "all isTriangle . triangulate" $ do
    property $ \(poly :: SimplePolygon () Rational) ->
      let g = triangulate' @() poly
          trigs = graphPolygons g
      in all isTriangle trigs

graphPolygons   :: (Ord r, Fractional r)
                => PlaneGraph s p PolygonEdgeType PolygonFaceData r -> [SimplePolygon p r]
graphPolygons g = map (^._2.core) . V.toList . snd $ facePolygons (outerFaceId g) g
