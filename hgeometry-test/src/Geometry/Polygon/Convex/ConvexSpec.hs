{-# LANGUAGE ScopedTypeVariables #-}
module Geometry.Polygon.Convex.ConvexSpec (spec) where

import           Algorithms.Geometry.ConvexHull.GrahamScan (convexHull)
import qualified Algorithms.Geometry.Diameter.Naive        as Naive

import           Control.Arrow                ((&&&))
import           Control.Lens                 (over, to, (^.), (^..))
import           Control.Monad.Random
import           Data.Coerce
import           Data.Ext
import qualified Data.Foldable                as F
import           Geometry
import           Geometry.Boundary
import           Geometry.Box            (boundingBox)
import           Geometry.BoxSpec        (arbitraryPointInBoundingBox)
import           Ipe
import           Geometry.Polygon.Convex
import           Geometry.PolygonSpec    ()
import qualified Data.List.NonEmpty           as NonEmpty
import           Data.RealNumber.Rational
import qualified Data.Vector.Circular         as CV
import           Paths_hgeometry_test
import           Test.Hspec
import           Test.QuickCheck              (Arbitrary (..), choose, elements, forAll, property,
                                               sized, suchThat, (=/=), (===), (==>), (.&&.))
import           Test.QuickCheck.Instances    ()
import           Test.Util                    (ZeroToOne (..))

--------------------------------------------------------------------------------

instance Arbitrary (ConvexPolygon () Rational) where
  arbitrary = sized $ \n -> do
    k <- choose (3, max 3 n)
    stdgen <- arbitrary
    pure $ evalRand (randomConvex k granularity) (mkStdGen stdgen)
    where
      granularity = 1000000
  shrink convex = map convexPolygon (shrink (convex^.simplePolygon))

--------------------------------------------------------------------------------

type R = RealNumber 10


spec :: Spec
spec = do
  testCases "src/Geometry/Polygon/Convex/convexTests.ipe"

testCases    :: FilePath -> Spec
testCases fp = runIO (readInputFromFile =<< getDataFileName fp) >>= \case
    Left e    -> it "reading ConvexTests file" $
                   expectationFailure . unwords $
                     [ "Failed to read ipe file", show fp, ":", show e]
    Right tcs -> do mapM_ toSpec tcs
                    minkowskiTests $ map _polygon tcs

data TestCase r = TestCase { _polygon    :: ConvexPolygon () r
                           }
                  deriving (Show)

toSingleSpec        :: (Num r, Ord r, Show r)
                    => ConvexPolygon q r -> Vector 2 r -> Expectation
toSingleSpec poly u =
  -- test that the reported extremes are equally far in direction u
    F.all allEq (unzip [extremes u poly, extremesLinear u (poly^.simplePolygon)])
    `shouldBe` True
  where
    allEq ~(p:ps) = all (\q -> cmpExtreme u p q == EQ) ps

-- | generates 360 vectors "equally" spaced/angled
directions :: Num r => [Vector 2 r]
directions = map (fmap toRat . uncurry Vector2 . (cos &&& sin) . toRad) ([0..359] :: [Double])
  where
    toRad i = i * (pi / 180)
    toRat x = fromIntegral . round $ 100000 * x

toSpec                 :: (Num r, Ord r, Show r) => TestCase r -> SpecWith ()
toSpec (TestCase poly) = do
                           it "Extreme points; binsearch same as linear" $
                             mapM_ (toSingleSpec poly) directions




readInputFromFile    :: FilePath -> IO (Either ConversionError [TestCase R])
readInputFromFile fp = fmap f <$> readSinglePageFile fp
  where
    f page = [ TestCase (ConvexPolygon poly) | (poly :+ _) <- polies ]
      where
        polies = page^..content.traverse._withAttrs _IpePath _asSimplePolygon


--------------------------------------------------------------------------------

minkowskiTests     ::  (Fractional r, Ord r, Show r) => [ConvexPolygon () r] -> Spec
minkowskiTests pgs = do
      minkowskiTests' "polygons in ipe file" pgs
      it "quickcheck minkowskisum same as naive" $
        property $ \(CP p :: CP Double) (CP q) ->
          minkowskiSum p q == naiveMinkowski p q



minkowskiTests'                      ::  (Fractional r, Ord r, Show r)
                                     => String -> [ConvexPolygon () r] -> Spec
minkowskiTests' s (map toCCW -> pgs) = describe ("Minkowskisums on " ++ s) $
    mapM_ (uncurry minkowskiTest) [ (p,q) | p <- pgs, q <- pgs ]


minkowskiTest     ::  (Fractional r, Ord r, Eq p, Show r, Show p)
                  => ConvexPolygon p r -> ConvexPolygon p r -> Spec
minkowskiTest p q = it "minkowskisum" $
  F (p,q) (minkowskiSum p q) `shouldBe` F (p,q) (naiveMinkowski p q)

naiveMinkowski     :: (Fractional r, Ord r)
                   => ConvexPolygon p r -> ConvexPolygon q r -> ConvexPolygon (p, q) r
naiveMinkowski p q = over (simplePolygon.unsafeOuterBoundaryVector) bottomMost
                   . toCCW . convexHull . NonEmpty.fromList
                   $ [ v .+. w | v <- p^..simplePolygon.outerBoundaryVector.traverse
                               , w <- q^..simplePolygon.outerBoundaryVector.traverse
                     ]
  where
    (v :+ ve) .+. (w :+ we) = v .+^ (toVec w) :+ (ve,we)


toCCW :: (Fractional r, Eq r) => ConvexPolygon p r -> ConvexPolygon p r
toCCW = over simplePolygon toCounterClockWiseOrder

data F a b = F a b deriving (Show)

instance Eq b => Eq (F a b) where
  (F _ b1) == (F _ b2) = b1 == b2


newtype CP r = CP (ConvexPolygon () r) deriving (Eq,Show)

instance (Arbitrary r, Fractional r, Ord r) => Arbitrary (CP r) where
  arbitrary =  CP . toCCW <$> suchThat (convexHull <$> arbitrary)
                              (\p -> p^.simplePolygon.outerBoundaryVector.to length > 2)
