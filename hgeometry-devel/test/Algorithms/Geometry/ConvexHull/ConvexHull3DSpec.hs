module Algorithms.Geometry.ConvexHull.ConvexHull3DSpec where

import           Data.Coerce
import qualified Data.Foldable as F
import           Geometry.Boundary (PointLocationResult(..))
import           Geometry.HalfSpace
import           Geometry.HyperPlane
import           Prelude hiding (filter)
import           Witherable
-- import qualified Algorithms.Geometry.ConvexHull.KineticDivideAndConquer as DivAndConc
import qualified Algorithms.Geometry.ConvexHull.Minimalist as Minimalist
-- import qualified Algorithms.Geometry.ConvexHull.MinimalistImperative as MinimalistImp
import           Algorithms.Geometry.ConvexHull.Naive (ConvexHull)
import qualified Algorithms.Geometry.ConvexHull.Naive as Naive
import           Control.Lens
import           Control.Monad (forM_)
import           Data.Ext
import           Geometry.Point
import           Geometry.Triangle
import           Geometry.Vector
import qualified Data.List as List
import           Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.List.Set as ListSet
import           Data.List.Util (leaveOutOne)
import           Data.Maybe
import           Data.RealNumber.Rational
import qualified Data.Set as Set
import           Data.Util
-- import           Algorithms.Util
import           Test.Hspec
import           Test.QuickCheck
import           Test.QuickCheck.Instances ()
import           Data.RealNumber.Symbolic
-- import           Test.Hspec.Core.QuickCheck (modifyMaxSuccess)
import           Geometry.Point.Random

--------------------------------------------------------------------------------

-- test :: Fractional r => IO [Triangle 3 Int r]
-- test = Minimalist.lowerHull' <$> samplePoints


-- samplePoints :: IO (NonEmpty (Point 3 R :+ Int))
-- samplePoints = (\pts -> withIndices (unGP <$> pts)) . NonEmpty.fromList <$> sample' arbitrary


--------------------------------------------------------------------------------
type R = RealNumber 10
-- type RBase = RealNumber 5
-- type R = Symbolic SoSI RBase


spec :: Spec
spec = describe "3D ConvexHull tests" $ do
         describe "Naive algorithm tests" $ do
           it "manual on myPts"  $ H (Naive.lowerHull' myPts)  `shouldBe` myHull
           it "manual on myPts'" $ H (Naive.lowerHull' myPts') `shouldBe` myHull'
           allHaveTriangleBelowTests Naive.lowerHull'

         describe "Minimalist Implementation" $ do
           allHaveTriangleBelowTests Minimalist.lowerHull'
           specAlg Minimalist.lowerHull'
         -- it "minimalist and Div&Conc quickcheck" $ property $ \(HI pts) ->
         --     DivAndConc.lowerHull' pts == Minimalist.lowerHull' pts
         -- it "Imperative minimalist and divide and conquer quickcheck" $ property $ \(HI pts) ->
         --     DivAndConc.lowerHull' pts == MinimalistImp.lowerHull' pts

--------------------------------------------------------------------------------

-- | Tests correctness of the lower hull
allHaveTriangleBelowTests     :: (NonEmpty (Point 3 R :+ Int) -> ConvexHull 3 Int R)
                              -> Spec
allHaveTriangleBelowTests alg = do
    allHaveTriangleBelow alg GeneralPos
    allHaveTriangleBelow alg DelaunayP
    allHaveTriangleBelow alg UniformInBall

allHaveTriangleBelow             :: forall tagType.
                                    ( Coercible tagType (Point 3 R)
                                    , Arbitrary tagType, Show tagType
                                    )
                                 => (NonEmpty (Point 3 R :+ Int) -> ConvexHull 3 Int R)
                                 -> (Point 3 R -> tagType)
                                 -> Spec
allHaveTriangleBelow lowerHull _ = it "allHaveTriangleBelow" $ property $ \p q r pts ->
    allHaveTriangleBelow' lowerHull (withIndices $ unTag @tagType (p :| q : r : pts))

unTag :: Coercible wrappedA a => NonEmpty wrappedA -> NonEmpty a
unTag = coerce

-- | Make sure that every point has a triangle below it (and that
-- actually that the point in question is above or on all triangles
-- that are stabbed by the vertical line through the point).
allHaveTriangleBelow'               :: (Ord r, Num r)
                                   => (NonEmpty (Point 3 r :+ p) -> ConvexHull 3 p r)
                                   -> NonEmpty (Point 3 r :+ p)
                                   -> Bool
allHaveTriangleBelow' lowerHull pts = all (hasTriangBelow ts . view core) pts
  where
    ts = lowerHull pts

-- | get all triangles stabbed by the vertical line through the query
findStabbed   :: (Num r, Ord r) => Filterable f
              => Point 3 r -> f (Triangle 3 p r) -> f (Triangle 3 p r)
findStabbed q = filter (\t -> projectPoint' q `onTriangle` pmap' projectPoint' t)
  where
    projectPoint' :: Point 3 r -> Point 2 r
    projectPoint' = projectPoint

pmap'  :: (Point d r -> Point d' s) -> Triangle d extra r -> Triangle d' extra s
pmap' f (Triangle p q' r) = Triangle (p&core %~ f) (q'&core %~ f) (r&core %~ f)

-- | Test if there is a triangle intersecting the vertical line
-- through q, and that actually all such all triangles are below q
hasTriangBelow      :: (Filterable f, Foldable f, Ord r, Num r)
                    => f (Triangle 3 p r) -> Point 3 r -> Bool
hasTriangBelow ts q = case F.toList $ findStabbed q ts of
                        []  -> False
                        ts' -> all (\t -> q `inHalfSpace` toHalfspace t /= Outside) ts'


-- | the halfspace above the triangle
toHalfspace :: forall r p. (Num r, Ord r) => Triangle 3 p r -> HalfSpace 3 r
toHalfspace = HalfSpace . supportingPlane . toCounterClockwiseTriangle
  where
    toCounterClockwiseTriangle :: Triangle 3 p r -> Triangle 3 p r
    toCounterClockwiseTriangle t@(Triangle p q r) | ccw p' q' r' == CCW = t
                                                  | otherwise           = Triangle p r q
      where
        Triangle p' q' r' = pmap' (projectPoint @2) t

--------------------------------------------------------------------------------


-- | Test if the given algorithm produces the same output as the naive algo
specAlg     :: (NonEmpty (Point 3 R :+ Int) -> ConvexHull 3 Int R) -- ^ the algorithm
            -> Spec
specAlg alg = do
  describe "same as naive on manual samples" $ do
    forM_ inputs $ \(msg,pts) ->
      it msg $ sameAsNaive alg pts
  -- modifyMaxSuccess (const 1000) $
  --   it "same as naive quickcheck" $ property $ \(HI pts) -> sameAsNaive alg pts
    describe "same as naive quickcheck" $ do
      it "uniform in box" $ property $ \pts ->
        sameAsNaive alg (withIndices (unGP <$> pts))
      it "uniform in ball" $ property $ \pts ->
        sameAsNaive alg (withIndices (unUniformInBall <$> pts))
      it "delaunay set" $ property $ \pts ->
        sameAsNaive alg (withIndices (unDelaunay <$> pts))

withIndices    :: NonEmpty a -> NonEmpty (a :+ Int)
withIndices xs = NonEmpty.zipWith (:+) xs (NonEmpty.fromList [0..])

inputs :: [(String, NonEmpty (Point 3 R :+ Int))]
inputs =
  [ ("myPts",myPts)
  , ("myPts'",myPts')
  , ("buggyPoints6",buggyPoints6)
  , ("buggyPoints",buggyPointsN)
  ]
  -- -- I've uncommented the ones below fow now, since they involve degeneracies.
  -- [ ("buggyPoints",buggyPoints)
  -- , ("buggyPoints2",buggyPoints2)
  -- , ("buggyPoints3",buggyPoints3)
  -- , ("buggyPointsSpeedup", NonEmpty.fromList buggySpeedup)
  -- , ("buggyPoints9",NonEmpty.fromList buggy9)
  -- , ("buggyPoints7SS", NonEmpty.fromList buggyPoints7SS)
  -- , ("buggyPoints7S", NonEmpty.fromList buggyPoints7S)
  -- , ("buggyPoints8",mkBuggy buggy8)
  -- , ("buggy10S",mkBuggy buggy10S)
  -- , ("buggy10",mkBuggy buggy10)
  -- , ("buggy11",mkBuggy buggy11)
  -- ]










--------------------------------------------------------------------------------

spec' :: Spec
spec' = describe "test" $ do
  it "same as naive on buggyPoints " $ sameAsNaive Minimalist.lowerHull' buggyPointsN

specShrink :: Spec
specShrink = describe "shrink" $ forM_ sets' $ \(_:+i,pts) ->
               it ("same as Naive " <> show i) $ sameAsNaive Minimalist.lowerHull' (mkBuggy pts)
  where
    sets' = leaveOutOne buggy11S






-- shrink     :: NonEmpty (Point 3 R :+ Int) -> NonEmpty (Point 3 R :+ Int)
-- shrink pts = leaveOutOne
-- leaveOutOne



newtype HullInput = HI (NonEmpty (Point 3 (RealNumber 10) :+ Int)) deriving (Eq,Show)

instance Arbitrary HullInput where
  arbitrary = (\as bs -> fromPts $ as <> bs) <$> setOf 3 arbitrary <*> arbitrary
    where
      fromPts pts = HI . NonEmpty.fromList
                 $ zipWith (:+) (fmap (realToFrac @Int @(RealNumber 10)) <$> Set.toList pts) ([0..])

-- FIXME: This actually works only for non-degenerate outputs. I.e. if
-- the output contains a face with more than three sides (i.e. not a
-- triangle) there are multiple, valid, ways of triangulating it.

-- sameAsNaive pts = (H $ DivAndConc.lowerHull' pts) `shouldBe` (H $ Naive.lowerHull' pts)

sameAsNaive         :: (Show r, Show p, Ord r, Fractional r)
                    => (NonEmpty (Point 3 r :+ p) -> ConvexHull 3 p r)
                    -> NonEmpty (Point 3 r :+ p) -> Expectation
sameAsNaive alg pts = HalfSpacesOf (alg pts)
                      `shouldBe`
                      HalfSpacesOf (Naive.lowerHull' pts)

newtype HalfSpaces p r = HalfSpacesOf (ConvexHull 3 p r) deriving Show

-- instance Show (HalfSpaces p r) where
--   show _ = "HalfSpace"

instance (Ord r, Fractional r) => Eq (HalfSpaces p r) where
  (HalfSpacesOf cha) == (HalfSpacesOf chb) = hsOf cha == hsOf chb
    where
      hsOf = flip ListSet.insertAll mempty . map Naive.upperHalfSpaceOf


newtype Hull p r = H (ConvexHull 3 p r) deriving (Show)

instance (Eq r, Ord p) => Eq (Hull p r) where
  (H ha) == (H hb) = f ha == f hb
    where
      f = List.sortOn g . map reorder
      g = fmap (^.extra) . (^._TriangleThreePoints)

reorder                  :: Ord p => Triangle 3 p r -> Triangle 3 p r
reorder (Triangle p q r) = let [p',q',r'] = List.sortOn (^.extra) [p,q,r] in Triangle p' q' r'


myPts :: NonEmpty (Point 3 R :+ Int)
myPts = NonEmpty.fromList [ Point3 5  5  0  :+ 2
                          , Point3 1  1  10 :+ 1
                          , Point3 0  10 20 :+ 0
                          , Point3 12 1  1  :+ 3
                          , Point3 22 20  1  :+ 4
                          ]

toTri       :: Eq a =>  NonEmpty (Point d r :+ a) -> Three a -> Triangle d a r
toTri pts t = let pt i = List.head $ NonEmpty.filter (\t' -> t'^.extra == i) pts
              in (t&traverse %~ pt)^.from _TriangleThreePoints

myHull :: Hull Int R
myHull = H . map (toTri myPts) $ [ Three 1 2 3
                                 , Three 2 3 4
                                 , Three 0 1 2
                                 , Three 0 2 4
                                 ]

myPts' :: NonEmpty (Point 3 R :+ Int)
myPts' = NonEmpty.fromList [ Point3 5  5  0  :+ 2
                           , Point3 1  1  10 :+ 1
                           , Point3 0  10 20 :+ 0
                           , Point3 12 1  1  :+ 3
                           ]

myHull' :: Hull Int R
myHull' = H . map (toTri myPts') $ [ Three 1 2 3
                                   , Three 0 1 2
                                   , Three 0 2 3
                                   ]








buggyPointsN :: NonEmpty (Point 3 R :+ Int)
buggyPointsN =  NonEmpty.fromList
               [ Point3 48.3650451071 7.4563367715  19.1569282618 :+ 0
               , Point3 20.4118494655 19.5372323335 92.2346920363 :+ 1
               , Point3 8.0610955116  24.8896480153 28.0685516681 :+ 2
               , Point3 30.5286900395 45.7603258350 87.5193514446 :+ 3
               ]




--------------------------------------------------------------------------------

-- | Generates a set of n elements (all being different), using the
-- given generator.
setOf    :: Ord a => Int -> Gen a -> Gen (Set.Set a)
setOf n g = buildSet mempty <$> do sz <- getSize
                                   infiniteListOf (resize (max sz n) g)
  where
    buildSet s (x:xs) | length s == n = s
                      | otherwise     = let s' = Set.insert x s in buildSet s' xs
    buildSet _  _                     = error "setOf: absurd"


--------------------------------------------------------------------------------
-- * Some difficult point sets

buggyPoints :: NonEmpty (Point 3 R :+ Int)
buggyPoints = fmap (bimap (10 *^) id) . NonEmpty.fromList $ [Point3 (-7) 2    4    :+ 0
                                                            ,Point3 (-4) 7    (-5) :+ 1
                                                            ,Point3 0    (-7) (-2) :+ 2
                                                            ,Point3 2    (-7) 0    :+ 3
                                                            ,Point3 2    (-6) (-2) :+ 4
                                                            ,Point3 2    5    4    :+ 5
                                                            ,Point3 5    (-1) 2    :+ 6
                                                            ,Point3 6    6    6    :+ 7
                                                            ,Point3 7    (-5) (-6) :+ 8
                                                            ]

buggyPoints2 :: NonEmpty (Point 3 R :+ Int)
buggyPoints2 = fmap (bimap (10 *^) id) . NonEmpty.fromList $ [ Point3 (-5) (-3) 4 :+ 0
                                                             , Point3 (-5) (-2) 5 :+ 1
                                                             , Point3 (-5) (-1) 4 :+ 2
                                                             , Point3 (0) (2)   2 :+ 3
                                                             , Point3 (1) (-5)  4 :+ 4
                                                             , Point3 (3) (-3)  2 :+ 5
                                                             , Point3 (3) (-1)  1 :+ 6
                                                             ]

buggyPoints3 :: NonEmpty (Point 3 R :+ Int)
buggyPoints3 = fmap (bimap (10 *^) id) . NonEmpty.fromList $ [ Point3 (-9 ) (-9) (  7) :+ 0,
                                                               Point3 (-8 ) (-9) ( -2) :+ 1,
                                                               Point3 (-8 ) (7 ) ( -2) :+ 2,
                                                               Point3 (-6 ) (9 ) ( 7) :+ 3,
                                                               Point3 (-3 ) (-6) ( -8) :+ 4,
                                                               Point3 (-3 ) (4 ) (  1) :+ 5,
                                                               Point3 (-2 ) (-9) ( -9) :+ 6,
                                                               Point3 (1  ) (-3) ( 1) :+ 7,
                                                               Point3 (4  ) (5 ) ( 8) :+ 8,
                                                               Point3 (10 ) (3 ) ( 3) :+ 9
                                                             ]


point3 :: [r] -> Point 3 r
point3 = fromJust . pointFromList

buggyPoints5 :: NonEmpty (Point 3 R :+ Int)
buggyPoints5 = mkBuggy $ buggyPoints5'

mkBuggy = fmap (bimap (10 *^) id) . NonEmpty.fromList

buggyPoints5' :: [Point 3 R :+ Int]
buggyPoints5' = [point3 [-21,14,-4]   :+ 0
                ,point3 [-16,-15,-14] :+ 1
                ,point3 [-14,12,16]   :+ 2
                ,point3 [-11,-19,-7]  :+ 3
                ,point3 [-9,18,14]    :+ 4
                ,point3 [-7,5,5]      :+ 5
                ,point3 [-6,14,11]    :+ 6
                ,point3 [-3,16,10]    :+ 7
                ,point3 [1,-4,0]      :+ 8
                ,point3 [1,19,14]     :+ 9
                ,point3 [3,4,-7]      :+ 10
                ,point3 [6,-8,22]     :+ 11
                ,point3 [8,6,12]      :+ 12
                ,point3 [12,-2,-17]   :+ 13
                ,point3 [23,-18,14]   :+ 14
                ,point3 [23,-6,-18]   :+ 15
                ]


buggyPoints6 = mkBuggy $ buggyPoints6'

buggyPoints6' :: [Point 3 R :+ Int]
buggyPoints6' = [ point3 [0 ,0, 00]   :+ 0
                , point3 [1 ,0, 0]    :+ 1
                , point3 [1, 2, 0 ]  :+ 2
                , point3 [0.5 , -0.0000000000000000000000000000000000000000000000000000000001  , 0]    :+ 3
               ]

-- -- truely vertical
-- buggyPoints6' :: [Point 3 R :+ Int]
-- buggyPoints6' = [ point3 [0 ,0, 00]   :+ 0
--                 , point3 [1 ,0, 0]    :+ 1
--                 , point3 [1, 2, 0 ]  :+ 2
--                 , point3 [2 ,0  , 0]    :+ 3
--                ]


buggyPoints7 :: [Point 3 R :+ Int]
buggyPoints7 = [-- point3 [-82,-84,-74] :+ 0
               point3 [-82,-27,66] :+ 1
               -- ,point3 [-82,6,-62] :+ 2
               -- ,point3 [-75,73,41] :+ 3
               ,point3 [-72,21,-81] :+ 4
               ,point3 [-69,-64,81] :+ 5
               ,point3 [-68,-53,40] :+ 6
               ,point3 [-68,2,-63] :+ 7
               ,point3 [-67,-92,82] :+ 8
               ,point3 [-66,-73,29] :+ 9
               ,point3 [-66,35,-68] :+ 11
               ,point3 [-59,-78,-71] :+ 12
               ,point3 [-58,32,74] :+ 13
               ,point3 [-57,-82,12] :+ 14
               ,point3 [-55,-7,-57] :+ 15
               ,point3 [-50,-77,23] :+ 16
               ,point3 [-48,-9,72] :+ 17
               ,point3 [-41,21,65] :+ 18
               ,point3 [-39,-72,40] :+ 19
               ,point3 [-39,63,-33] :+ 20
               ,point3 [-36,90,86] :+ 21
               ,point3 [-34,6,-3] :+ 22
               ,point3 [-30,-31,68] :+ 23
               ,point3 [-29,-15,53] :+ 24
               ,point3 [-21,-51,-76] :+ 25
               ,point3 [-20,59,26] :+ 26
               ,point3 [-17,-54,-92] :+ 27
               ,point3 [-17,-4,27] :+ 28
               ,point3 [-16,-47,26] :+ 29
               ,point3 [-13,23,-55] :+ 30
               ,point3 [-11,-33,-13] :+ 31
               ,point3 [-9,-32,59] :+ 32
               ,point3 [-9,-1,11] :+ 33
               ,point3 [-6,-68,-27] :+ 34
               ,point3 [-6,25,-20] :+ 35
               ,point3 [-4,85,24] :+ 36
               ,point3 [-1,-39,-89] :+ 37
               ,point3 [2,-36,36] :+ 38
               ,point3 [2,22,28] :+ 39
               ,point3 [4,-42,-27] :+ 40
               ,point3 [8,89,3] :+ 41
               ,point3 [12,-53,-2] :+ 42
               ,point3 [12,32,-28] :+ 43
               ,point3 [13,27,-92] :+ 44
               ,point3 [15,90,79] :+ 45
               ,point3 [16,26,72] :+ 46
               ,point3 [19,91,-30] :+ 47
               ,point3 [20,-57,-3] :+ 48
               ,point3 [21,53,-84] :+ 49
               ,point3 [22,-88,-25] :+ 50
               ,point3 [26,82,20] :+ 51
               ,point3 [27,-68,69] :+ 52
               ,point3 [27,87,-92] :+ 53
               ,point3 [32,-6,83] :+ 54
               ,point3 [33,54,-47] :+ 55
               ,point3 [34,-61,16] :+ 56
               ,point3 [35,-58,21] :+ 57
               ,point3 [37,35,31] :+ 58
               ,point3 [41,-92,-84] :+ 59
               ,point3 [42,-63,59] :+ 60
               ,point3 [44,-84,-90] :+ 61
               ,point3 [47,0,78] :+ 62
               ,point3 [51,-69,44] :+ 63
               ,point3 [51,-49,-20] :+ 64
               ,point3 [51,92,-84] :+ 65
               ,point3 [52,-80,-92] :+ 66
               ,point3 [54,-13,-50] :+ 67
               ,point3 [57,58,-50] :+ 68
               ,point3 [59,83,-29] :+ 69
               ,point3 [71,14,-8] :+ 70
               ,point3 [77,-1,-47] :+ 71
               ,point3 [78,-58,-74] :+ 72
               ,point3 [79,34,-21] :+ 73
               ,point3 [84,-82,-1] :+ 74
               ,point3 [85,38,34] :+ 75
               ]



buggyPoints7S :: [Point 3 R :+ Int]
buggyPoints7S = [point3 [-82,-27,66]  :+ 0
                ,point3 [-72,21,-81]  :+ 1
                ,point3 [-69,-64,81]  :+ 2
                ,point3 [-68,2,-63]   :+ 3
                ,point3 [-67,-92,82]  :+ 4
                ,point3 [-66,-73,29]  :+ 5
                ,point3 [-59,-78,-71] :+ 6
                ,point3 [-58,32,74]   :+ 7
                ,point3 [-57,-82,12]  :+ 8
                ,point3 [-55,-7,-57]  :+ 9
                ,point3 [-50,-77,23]  :+ 10
                ,point3 [-48,-9,72]   :+ 11
                ,point3 [-41,21,65]   :+ 12
                ,point3 [-39,-72,40]  :+ 13
                ,point3 [-39,63,-33]  :+ 14
                ,point3 [-36,90,86]   :+ 15
                ,point3 [-34,6,-3]    :+ 16
                ,point3 [-30,-31,68]  :+ 17
                ,point3 [-29,-15,53]  :+ 18
                ,point3 [-21,-51,-76] :+ 19
                ,point3 [-20,59,26]   :+ 20
                ,point3 [-17,-54,-92] :+ 21
                ,point3 [-16,-47,26]  :+ 22
                ,point3 [-13,23,-55]  :+ 23
                ,point3 [-11,-33,-13] :+ 24
                ,point3 [-9,-32,59]   :+ 25
                ,point3 [-6,-68,-27]  :+ 26
                ,point3 [-4,85,24]    :+ 27
                ,point3 [-1,-39,-89]  :+ 28
                ,point3 [2,-36,36]    :+ 29
                ,point3 [4,-42,-27]   :+ 30
                ,point3 [8,89,3]      :+ 31
                ,point3 [12,-53,-2]   :+ 32
                ,point3 [13,27,-92]   :+ 33
                -- ,point3 [22,-88,-25]  :+ 34
                -- ,point3 [26,82,20]    :+ 35
                ,point3 [27,87,-92]   :+ 36
                ,point3 [52,-80,-92]  :+ 37
                ]

buggySpeedup :: [Point 3 R :+ Int]
buggySpeedup = [ point3 [-33,28,23] :+ 0
               , point3 [-29,-20,-31] :+ 1
               , point3 [-23,-20,-31] :+ 2
               , point3 [-23,19,27] :+ 3
               , point3 [-22,-9,-22] :+ 4
               , point3 [-20,-33,-4] :+ 5
               , point3 [-19,-13,6] :+ 6
               , point3 [-13,15,19] :+ 7
               , point3 [-11,1,-28] :+ 9
               , point3 [-9,-8,8] :+ 10
               , point3 [-8,11,-8] :+ 11
               , point3 [-7,-32,-31] :+ 12
               , point3 [11,12,4] :+ 21
               , point3 [13,-29,3] :+ 22
               , point3 [19,25,-30] :+ 23
               , point3 [22,-21,30] :+ 24
               , point3 [25,-37,0] :+ 25
               , point3 [30,-10,-31] :+ 26
               ]

buggy8 :: [Point 3 R :+ Int]
buggy8 = [ point3 [-11,-5,8] :+ 0
         , point3 [-10,3,-6] :+ 1
         , point3 [-9,3,-7] :+ 2
         , point3 [-7,6,-9] :+ 3
         , point3 [-7,9,-4] :+ 4
         , point3 [-6,-2,-10] :+ 5
         , point3 [-6,11,9] :+ 6
         , point3 [-5,10,5] :+ 7
         , point3 [2,5,-7] :+ 8
         , point3 [5,1,8] :+ 9
         -- , point3 [10,4,-8] :+ 10
         ]

buggy9 :: [Point 3 R :+ Int]
buggy9 = [ point3 [-18,-13,2] :+ 0
         , point3 [-7,6,5] :+ 1
         , point3 [-4,-6,20] :+ 2
         , point3 [-2,-17,-7] :+ 3
         , point3 [-1,-12,-6] :+ 4
         , point3 [-1,4,5] :+ 5
         , point3 [-1,6,16] :+ 6
         , point3 [14,-5,-17] :+ 7
         , point3 [15,-20,19] :+ 8
         , point3 [16,-11,-14] :+ 9]



buggyPoints7SS :: [Point 3 R :+ Int]
buggyPoints7SS = [point3 [-82,-27,66]  :+ 0
                 ,point3 [-17,-54,-92] :+ 1
                 ,point3 [-16,-47,26]  :+ 2
                 ,point3 [13,27,-92]   :+ 3
                 ,point3 [26,82,20]    :+ 4
                 ,point3 [27,87,-92]   :+ 5
                 ,point3 [52,-80,-92]  :+ 6
                 ]

-- so apparently at -9.589.... 1,3,5, and 6 are colinear
-- and the bridge remains on 1-6
buggy10 :: [Point 3 R :+ Int]
buggy10 = [ point3 [-70,-26,-53] :+ 0
          , point3 [-70,45,39] :+ 1
          , point3 [-68,62,8] :+ 2
          , point3 [-57,39,-55] :+ 3
          , point3 [-47,8,70] :+ 4
          , point3 [-45,11,-56] :+ 5
          , point3 [-44,-40,-54] :+ 6
          , point3 [-42,57,24] :+ 7
          , point3 [-40,27,-44] :+ 8
          , point3 [-39,-29,5] :+ 9
          , point3 [-33,10,-25] :+ 10
          , point3 [-33,68,30] :+ 11
          , point3 [-21,-25,-35] :+ 12
          , point3 [-20,-71,-34] :+ 13
          , point3 [-18,-46,27] :+ 14
          , point3 [-16,45,-28] :+ 15
          , point3 [-9,22,-25] :+ 16
          , point3 [4,-55,-16] :+ 17
          , point3 [8,76,-70] :+ 18
          , point3 [11,-26,-21] :+ 19
          , point3 [11,28,-7] :+ 20
          , point3 [12,-27,-72] :+ 21
          , point3 [13,-23,-60] :+ 22
          , point3 [16,-57,41] :+ 23
          , point3 [22,1,-35] :+ 24
          , point3 [25,-4,-5] :+ 25
          , point3 [36,23,-65] :+ 26
          , point3 [37,38,76] :+ 27
          , point3 [37,63,-15] :+ 28
          , point3 [40,-67,24] :+ 29
          , point3 [44,73,59] :+ 30
          , point3 [46,-63,-47] :+ 31
          , point3 [57,-28,46] :+ 32
          , point3 [60,-32,76] :+ 33
          , point3 [62,-68,28] :+ 34
          , point3 [62,30,-52] :+ 35
          , point3 [68,38,-53] :+ 36
          , point3 [69,-40,67] :+ 37
          , point3 [72,-17,-55] :+ 38
          , point3 [74,51,-13] :+ 39
          , point3 [74,73,-10] :+ 40
          , point3 [75,-60,55] :+ 41
          ]

buggy10S :: [Point 3 R :+ Int]
buggy10S = [ point3 [-70,-26,-53] :+ 0
          , point3 [-70,45,39] :+ 1
          , point3 [-68,62,8] :+ 2
          , point3 [-57,39,-55] :+ 3
          , point3 [-47,8,70] :+ 4
          , point3 [-45,11,-56] :+ 5
          , point3 [-44,-40,-54] :+ 6
          , point3 [-42,57,24] :+ 7
          , point3 [-40,27,-44] :+ 8
          , point3 [-33,10,-25] :+ 9
          , point3 [-21,-25,-35] :+ 10
          , point3 [-20,-71,-34] :+ 11
          , point3 [4,-55,-16] :+ 12
          ]

buggy11 :: [Point 3 R :+ Int]
buggy11 = [ point3 [-4,-2,-1] :+ 0
          , point3 [-3,-4,-3] :+ 1
          , point3 [-2,-1,0] :+ 2
          , point3 [-2,0,-2] :+ 3
          , point3 [-1,2,3] :+ 4
          , point3 [1,-4,-4] :+ 5
          , point3 [3,-2,1] :+ 6
          , point3 [5,5,-4] :+ 7
          ]

buggy11S :: [Point 3 R :+ Int]
buggy11S = [ point3 [-4,-2,-1] :+ 0
          , point3 [-3,-4,-3] :+ 1
          , point3 [-2,-1,0] :+ 2
          , point3 [-2,0,-2] :+ 3
          , point3 [-1,2,3] :+ 4
          ]
