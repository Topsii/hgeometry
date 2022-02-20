{-# OPTIONS_GHC -fno-warn-orphans #-}
{-# LANGUAGE BangPatterns #-}
--------------------------------------------------------------------------------
-- |
-- Module      :  Algorithms.Geometry.ConvexHull.KineticDivideAndConquer
-- Copyright   :  (C) Frank Staals
-- License     :  see the LICENSE file
-- Maintainer  :  Frank Staals
--
-- \(3\)-d convex hull algorithm. The implementation is based on
--
-- <http://tmc.web.engr.illinois.edu/ch3d/ch3d.pdf A Minimalist’s Implementationof the3-dDivide-and-ConquerConvex Hull Algorithm>
-- by Timothy M. Chan
--
--------------------------------------------------------------------------------
module Algorithms.Geometry.ConvexHull.MinimalistImperative where


import           Algorithms.DivideAndConquer
import qualified Algorithms.Geometry.ConvexHull.GrahamScan as GrahamScan
import           Algorithms.Geometry.ConvexHull.Debug
import           Algorithms.Geometry.ConvexHull.Helpers
import           Algorithms.Geometry.ConvexHull.Types
import           Control.Applicative (liftA2)
import           Control.Lens ((^.), (&), (%~), bimap, _1, _2)
import           Control.Monad ((<=<), filterM)
import           Control.Monad.State.Class (get, put)
import           Control.Monad.State.Strict (evalStateT)
import           Control.Monad.Trans
import           Data.Either (partitionEithers)
import           Data.Ext
import           Data.Foldable (toList)
import           Data.Geometry.Point
import           Data.Geometry.Polygon.Convex (lowerTangent')
import           Data.Geometry.Triangle
import           Data.IndexedDoublyLinkedList
import qualified Data.List as List
import           Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NonEmpty
import           Data.Maybe
import           Data.Ord (comparing, Down(..))
import           Data.Semigroup (sconcat)
import           Data.UnBounded
import           Data.Util
import qualified Data.Vector as V

import           Ipe
import           Data.Maybe (catMaybes)
import           Data.RealNumber.Rational


import Data.Geometry.Vector
import           Debug.Trace

import Algorithms.Geometry.ConvexHull.RenderPLY

--------------------------------------------------------------------------------

-- TODO: We seem to assume that no four points are coplanar, and no
-- three points lie on a vertical plane. Figure out where we assume that exactly.

-- no four points coplanar:
--     - otherwise events may happen simultaneously
--     - output may not be a set of triangles
-- no three points on a vertical plane:
--     Otherwise the test for computing the next time t does not exist
--       (slope of the supp. plane of three such points is +infty)


-- TODO: The kinetic sim. now treats three points on a vertical plane
-- as happening at time t=-\infty. That means we should find faces on
-- the lower envelope that have that property separately.
--
-- I think we can do that by projecting the points down onto the
-- xy-plane, and computing a 2D convex hull.
--
-- I Think this is actually fine, since for s.t. like the delaunay
-- triangulation you don't want those faces anyway.

-- FIXME: We start with some arbitrary starting slope. Fix that




-- lowerHull :: (Ord r, Fractional r) => [Point 3 r :+ p] -> ConvexHull 3 p r
-- lowerHull = maybe mempty lowerHull' . NonEmpty.nonEmpty


lowerHull'      :: forall r p. (Ord r, Fractional r, Show r, IpeWriteText r)
                => NonEmpty (Point 3 r :+ p) -> ConvexHull 3 p r
lowerHull' pts' = map withPt $ runDLListMonad pts computeHull
  where
    computeHull :: HullM s r [Three Index]
    computeHull = output <=< divideAndConquer1 mkLeaf $ leafIndices pts

    (pts,exts) = bimap V.fromList V.fromList . unExt . NonEmpty.sortBy cmpXYZ $ pts'
    unExt = foldr (\(p :+ e) (ps,es) -> (p:ps,e:es)) ([],[])

    -- withPt = id
    withPt (Three a b c) = let pt i = pts V.! i :+ exts V.! i in Triangle (pt a) (pt b) (pt c)

-- | Comparator for the points. We sort the points lexicographically
-- on increasing x-coordiante, decreasing y-coordinate, and increasing
-- z-coordinate. The extra data is ignored.
--
-- The divide and conquer algorithm needs the points sorted in
-- increasing order on x.
--
-- The choice of sorting order of the y and z-coordinates is such that
-- in a leaf (all points with the same x-coord). Are already
-- pre-sorted in the right way: in particular, increasing on their
-- "slope" in the "Time x Y'" space. This means that when we compute
-- the lower envelope of these lines (using the duality and upper
-- hull) we don't have to re-sort the points. See 'simulateLeaf'' for
-- details.
cmpXYZ :: Ord r => (Point 3 r :+ p) -> (Point 3 r :+ q) -> Ordering
cmpXYZ (Point3 px py pz :+ _) (Point3 qx qy qz :+ _) =
  compare px qx <> compare (Down py) (Down qy) <> compare pz qz

-- | Creates a non-empty list, one for each x-coordinate, with all ids
-- that have that x-coordinate
--
-- pre:  - the input points vector is non-emtpy, and sorted on increasing x-coordinate
leafIndices :: Eq r => V.Vector (Point 3 r) -> NonEmpty (NonEmpty Index)
leafIndices = fmap (fmap (^._1)) . NonEmpty.groupWith1 (^._2.xCoord) . NonEmpty.fromList
            . zip [0..] . V.toList

-- | Creates a Leaf
mkLeaf    :: (Ord r, Fractional r, Show r) => NonEmpty Index -> HullM s r (MergeStatus r)
mkLeaf is = (\(SP i evts) -> MergeStatus i i evts) <$> simulateLeaf is

-- | Computes the first index
simulateLeaf    :: (Ord r, Fractional r, Show r) => NonEmpty Index -> HullM s r (SP Index [Event r])
simulateLeaf is = simulateLeaf' <$> mapM (\i -> (:+ i) <$> pointAt i) is

simulateLeaf' :: (Ord r, Fractional r, Show r) => NonEmpty (Point 3 r :+ Index) -> SP Index [Event r]
simulateLeaf' = (&_2 %~ toEvents) . lowerEnvelope . fmap (&core %~ toDualPoint)
  where
    toEvents = map (&extra %~ fromBreakPoint)
    -- Every point in R^3 maps to a non-vertical line: y' = -y*t + z
    -- which then dualizes to the the point (-y,-z)
    toDualPoint (Point3 _ y z) = Point2 (-1*y) (-1*z)
    -- at every breakpoint we insert b and delete a.
    fromBreakPoint (Two a b) = NonEmpty.fromList [InsertAfter a b, Delete a]


-- | Given a set of lines, represented by their dual points, compute
-- the lower envelope of those lines. Returns the associated value of
-- the leftmost line, and all breakpoints. For every breakpoint we
-- also return the associated values of the line just before the
-- breakpoint and the line just after the breakpoint.
--
-- running time: \(O(n \log n)\)
lowerEnvelope     :: (Ord r, Fractional r, Show r) => NonEmpty (Point 2 r :+ a) -> SP a [r :+ Two a]
lowerEnvelope pts = SP i $ zipWith f (toList h) tl
  where
    f (pa :+ a) (pb :+ b) = let Vector2 x y = pb .-. pa in y / x :+ Two a b
    h@((_ :+ i) :| tl) = GrahamScan.upperHullFromSorted' $ pts
    -- every edge of the upper hull corresponds to some line. In the
    -- primal this line represents a vertex of the lower envelope. The
    -- x-coordinate of this point is the slope of the line.




--------------------------------------------------------------------------------

-- | Computes a lowerbound on the z-value with which to start
-- pre: not all points on a vertical plane
lowerboundT     :: (Ord r, Fractional r) => NonEmpty (Point 3 r) -> r
lowerboundT pts = ((-1)*) . maximum . catMaybes
                $ zipWith slope (toList pts') (NonEmpty.tail pts')
  where
    pts' = NonEmpty.sortBy (comparing (^.yCoord) <> comparing (^.zCoord)) pts

    slope p q = let d = q^.yCoord - p^.yCoord
                in if d == 0 then Nothing else Just $ (abs $ q^.zCoord - p^.zCoord) / d


initialHull' :: (Ord r, Num r) => NonEmpty (Point 3 r :+ p) -> NonEmpty p
initialHull' = fmap (^.extra)
             . GrahamScan.lowerHull
             . fmap (&core %~ \(Point3 x _ z) -> Point2 x z)

initialHull''     :: (Ord r, Num r) => MergeStatus r -> MergeStatus r -> HullM s r (NonEmpty Index)
initialHull'' l r = do pts <- fst <$> dump
                       let pts'  = V.imap (\i p -> p :+ i) pts
                           xMin  = (pts' V.! (hd  l))^.core.xCoord
                           xMax  = (pts' V.! (lst r))^.core.xCoord
                           pts'' = V.filter (\(p :+ _) -> let x = p^.xCoord
                                                          in xMin <= x && x <= xMax
                                            ) pts'
                       pure $ initialHull' . NonEmpty.fromList . V.toList $ pts''

instance (Ord r, Fractional r, Show r, IpeWriteText r)
         => Semigroup (HullM s r (MergeStatus r)) where
  lc <> rc = do l <- lc
                r <- rc
                let esIn = mergeEvents (events l) (events r)
                    t    = (-10000000) -- TODO; at what time value should we start?
                (h,u,v) <- findBridge t l r
                -- (vec,_) <- dump
                -- h' <- initialHull'' l r
                let b = Bridge u v
                    -- b' = traceShow ("hull=hull?", if h /= h' then show (vec,l,r,h,h') else "Same") b
                es <- runKinetic Bottom esIn b
                writeList h
                let !ms = MergeStatus (hd l) (lst r) es
                -- fp <- renderMovieIO ("movie_" <> rangeS l r) ms
                pure ms
                --
                -- pure $ traceShow (drawDebug "combined" ms (Bridge u v) pts) ms
    where
      rangeS l r = show (hd l) <> "-" <> show (lst r)





--------------------------------------------------------------------------------
-- * Producing the Output Hull

-- | Reports all the edges on the CH
output    :: Show r => MergeStatus r -> HullM s r [Three Index]
-- output ms | traceShow ("output: ", events ms) False = undefined
output ms = concat <$> mapM handle (events ms)
  where
    handle e = catMaybes . toList <$> mapM applyAndReport (e^.eventActions)
    applyAndReport a = do mt <- reportTriangle a
                          applyEvent' a
                          pure mt

reportTriangle :: Action -> HullM s r (Maybe (Three Index))
reportTriangle = \case
    InsertAfter i j  -> fmap (\r   -> Three i j r)   <$> getNext i
    InsertBefore i h -> fmap (\l   -> Three l h i)   <$> getPrev i
    Delete j         -> liftA2 (\l r -> Three l j r) <$> getPrev j <*> getNext j

--------------------------------------------------------------------------------
-- * Finding the Bridge

-- | Computes the Bridge of the Hulls (the Hulls currently encoded in
-- the underlying Doublylinkedlist)
--
-- running time: \(O(n)\)
findBridge       :: (Ord r, Fractional r, Show r)
                 => r -> MergeStatus r -> MergeStatus r -> HullM s r (NonEmpty Index, Index, Index)
findBridge t l r = do lh <- toListFromR (lst l)
                      rh <- toListFrom  (hd r)
                      findBridgeFrom t lh rh

findBridgeFrom       :: (Ord r, Fractional r, Show r)
                     => r -> NonEmpty Index -> NonEmpty Index
                     -> HullM s r (NonEmpty Index, Index, Index)
findBridgeFrom t l r = do lh <- mapM (atTime'' t) l
                          rh <- mapM (atTime'' t) r
                          let Two (u :+ ls) (v :+ rs) = findBridge' lh rh
                          pure $ (NonEmpty.fromList $ reverse ls <> [u,v] <> rs, u, v)
  where
    atTime'' t' i = (:+ i) <$> atTime t' i
    findBridge' l0 r0 = f <$> lowerTangent' l0 r0
    f (c :+ es) = c^.extra :+ ((^.extra) <$> es)

--------------------------------------------------------------------------------

mergeEvents       :: (Ord r, Show r)
                  => [Event r] -> [Event r] -> [r :+ NonEmpty (Existing Action)]
mergeEvents ls rs = map combine . groupOn (^.core)
                  $ mergeSortedListsBy (comparing (^.core)) (wrap Left ls) (wrap Right  rs)
  where
    wrap f = map (&extra %~ \k -> f <$> k)
    combine ((t:+as):|es) = t :+ (sconcat $ as :| map (^.extra) es)

--------------------------------------------------------------------------------
-- * Running the simulation

-- | run the kinetic simulation, computing the events at which the
-- hull changes. At any point during the simulation:
--
-- - the multable array in env represents the hulls L and R
-- - we maintain the current bridge u on L and v on R such that
-- - L[1..u] <> R[v..n] is the output hull H
runKinetic        :: (Ord r, Fractional r, Show r, IpeWriteText r )
                  => Bottom r                          -- ^ starting time
                  -> [r :+ NonEmpty (Existing Action)] -- ^ the existing events
                  -> Bridge -- initial bridge
                  -> HullM s r [Event r]
runKinetic t es b = evalStateT (handleEvent t es) b

-- | Given the current time, handling an event means three things:
--
-- 1. figuring out when the first bridge event is
-- 2. figuring out at what time the next event happens, what actions
--    occur at that time, and performing those.
-- 3. handling all remaining events.
handleEvent        :: (Ord r, Fractional r, Show r)
                   => Bottom r                         -- ^ The current time
                   -> [r :+ NonEmpty (Existing Action)] -- ^ the existing events
                   -> Simulation s r [Event r]
handleEvent now es = do mbe <- firstBridgeEvent now
                        case nextEvent mbe es of
                          None             -> pure []
                          Next t eacts es' -> do me  <- handleAllAtTime t eacts
                                                 evs <- handleEvent (ValB t) es'
                                                 pure $ maybeToList me <> evs

--------------------------------------------------------------------------------
-- * Handling all events at a particular time.

-- handles all events at the current time.
handleAllAtTime :: (Ord r, Fractional r, Show r)
                => r
                -- ^ the current time
                -> [Existing Action]
                -- ^ all *existing* events that are happening at the
                -- current time. I.e. events in either the left or right hulls
                -> Simulation s r (Maybe (Event r))
-- handleAllAtTime now ees | traceShow ("handleAllAtTime",now,ees) False = undefined
handleAllAtTime now ees =
    do b <- get
       let Bridge l r = b -- traceShow ("bridge before handling side events: ",b) b
       -- currentHL <- lift $ toListContains l
       -- currentHR <- lift $ toListContains r
       (delL,ls) <- handleOneSide now levs l
       (delR,rs) <- handleOneSide now revs r
       b' <- newBridge now (NonEmpty.reverse ls) rs
       let Bridge l' r' = b'
       louts <- filterM (occursBeforeAt now $ l `max` l') levs
       routs <- filterM (occursAfterAt  now $ r `min` r') revs
       la <- leftBridgeEvent  l l' delL levs
       ra <- rightBridgeEvent r r' delR revs
       put b'        -- put $ traceShow ("bridge after time: ", now, " is ", b') b'
       pure . tr . outputEvent now $ louts <> routs <> catMaybes [la,ra]
         -- the bridge actions should be after louts and routs;
  where
    (levs,revs) = partitionEithers ees
    outputEvent t acts = (t :+) <$> NonEmpty.nonEmpty acts

    tr x = x -- traceShow ("outputting event: ",x) x


occursBeforeAt       :: (Ord r, Num r) =>  r -> Index -> Action -> Simulation s r Bool
occursBeforeAt t l e = lift $ before <$> atTime (t+1) (getRightMost e) <*> atTime (t+1) l
  where
    p `before` pl = p <= pl  -- lexicographic on x,y

occursAfterAt       :: (Ord r, Num r) =>  r -> Index -> Action -> Simulation s r Bool
occursAfterAt t r e = lift $ after <$> atTime (t+1) (getLeftMost e) <*> atTime (t+1) r
  where
    -- p.x > r.x or (p.x == r.x && p.y >= r.y)
    (Point2 x y) `after` (Point2 rx ry) = case x `compare` rx of
                                            LT -> False
                                            GT -> True
                                            EQ -> ry <= y

-- | Computes if we should output a new bridge action for the left endpoint
leftBridgeEvent                         :: Index -> Index -> Bool -> [Action]
                                        -> Simulation s r (Maybe Action)
-- leftBridgeEvent l l' b evs | traceShow ("leftBridgeEvent ",l,l',b,evs) False = undefined
leftBridgeEvent l l' alreadyDeleted evs = lift $ case (l `compare` l') of
    LT | shouldBeInserted l' evs -> (\(Just p) -> Just $ InsertAfter p l') <$> getPrev l'
    -- since l < l', l' has a predecessor, and hence the fromJust is safe.
    GT | not alreadyDeleted      -> pure . Just $ Delete l
    _                            -> pure Nothing

rightBridgeEvent                         :: Index -> Index -> Bool -> [Action]
                                         -> Simulation s r (Maybe Action)
-- rightBridgeEvent r r' b evs | traceShow ("rightBridgeEvent ",r,r',b,evs) False = undefined
rightBridgeEvent r r' alreadyDeleted evs = lift $ case (r' `compare` r) of
    LT | shouldBeInserted r' evs -> (\(Just p) -> Just $ InsertBefore p r') <$> getNext r'
    -- since r' < r, r' has a successor, and hence the fromJust is safe
    GT | not alreadyDeleted      -> pure . Just $ Delete r
    _                            -> pure Nothing

-- | Figure out if the given index has been inserted in one of the actions.
shouldBeInserted   :: Index -> [Action] -> Bool
shouldBeInserted i = null . filter isInsert
  where
    isInsert = \case
      InsertAfter  _ j | j == i -> True
      InsertBefore _ j | j == i -> True
      _                         -> False

-- | Considering that all points in ls and rs are colinear at time t
-- (and contain the bridge at time). Compute the new bridge.
--
-- running time: linear in the number of points in ls and rs.
newBridge         :: (Ord r, Fractional r, Show r)
                  =>  r -> NonEmpty Index -> NonEmpty Index -> Simulation s r Bridge
-- newBridge t ls rs | traceShow ("newBridge ", t,ls,rs) False = undefined
newBridge t ls rs = lift $ (\(_,l,r) -> Bridge l r) <$> findBridgeFrom (t+1) ls rs
  -- claim: all colinear a t time t means we can pick any time t' > t
  -- to compute the new bridge

-- |
--
-- returns wether the current bridge was deleted and the colinears
-- with the current bridge
handleOneSide           :: (Ord r, Num r, Show r)
                        => r -> [Action] -> Index -> Simulation s r (Bool, NonEmpty Index)
-- handleOneSide now evs l | traceShow ("handleOneSide ",now,evs,l) False = undefined
handleOneSide now evs l = do lift $ mapM_ applyEvent' insertions
                             lift $ mapM_ applyEvent' deletions
                             ls <- colinears' now l (length insertions)
                             lift $ mapM_ applyEvent' delBridge
                             pure (isJust delBridge, ls)
  where
    (delBridge, deletions, insertions) = partitionActions evs l

partitionActions       :: [Action] -> Index -> (Maybe Action, [Action], [Action])
partitionActions evs l = (listToMaybe bridgeDels, rest, ins)
  where
    (dels,ins) = List.partition isDelete evs
    (bridgeDels,rest) = List.partition (\(Delete i) -> i == l) dels
    isDelete = \case
      Delete _ -> True
      _        -> False

-- | Given the current time t, a starting index i, and a distance d,
-- finds all points within "d+1" hops from i that are colinear with i
-- at the current time t.
colinears'       :: (Ord r, Num r, Show r) => r -> Index -> Int -> Simulation s r (NonEmpty Index)
colinears' t i d = do b  <- get >>= traverse (lift . atTime t)
                      ls <- lift (toListFromR i) >>= takeColinear b
                      rs <- lift (toListFrom  i) >>= takeColinear b
                      pure . NonEmpty.fromList $ (reverse ls) <> [i] <> rs
  where
    takeColinear b (_ :| is) = filterM (isColinearWith b t) $ take (d+1) is


-- colinears     :: (Ord r, Num r, Show r) => r -> Index -> Simulation s r (NonEmpty Index)
-- colinears t i = do b  <- get >>= traverse (lift . atTime t)
--                    ls' <- lift dump
--                    ls <- lift (toListFromR i) >>= takeColinear b
--                    rs <- lift (toListFrom  i) >>= takeColinear b
--                    pure . NonEmpty.fromList . tr b ls' $ (reverse ls) <> [i] <> rs
--   where
--     takeColinear b (_ :| is) = takeWhileM (isColinearWith b t) is
--     tr b ys xs = traceShow ("colinears",i,b,xs,ys) xs
--     -- FIXME: the toListFrom on rs is the problem. The current bridge is 15, but is being replaced by 14, which has the exact same x-coord. So, we need to walk to the left there as well.


-- | Given two 2d-points (representing the bridge at time t), time t,
-- and index i, test if the point with index i is colinear with the
-- bridge.
isColinearWith               :: (Ord r, Num r)
                             => Two (Point 2 r) -> r -> Index -> Simulation s r Bool
isColinearWith (Two l r) t i = (\p -> ccw l r p == CoLinear) <$> lift (atTime t i)


--------------------------------------------------------------------------------
-- * Computing the Next Event

data NextEvent r = None | Next { nextEventTime   :: !r
                               , existingActions :: ![Existing Action]
                               , remainingEvents :: ![r :+ NonEmpty (Existing Action)]
                               } deriving (Show,Eq)

-- | Figures out what the time of the first event is (if it exists)
-- and collects everything that happens at that time (and which
-- existing events happen later)
nextEvent                                    :: Ord r
                                             => Maybe r -> [r :+ NonEmpty (Existing Action)]
                                             -> NextEvent r
nextEvent Nothing   []                       = None
nextEvent Nothing   ((te :+ eacts) : es')    = Next te (toList eacts) es'
nextEvent (Just tb) []                       = Next tb []             []
nextEvent (Just tb) es@((te :+ eacts) : es') = case tb `compare` te of
                                                 LT -> Next tb []             es
                                                 EQ -> Next tb (toList eacts) es'
                                                 GT -> Next te (toList eacts) es'

-- | Computes the first time a bridge event happens.
firstBridgeEvent     :: (Ord r, Fractional r) => Bottom r -> Simulation s r (Maybe r)
firstBridgeEvent now = do br <- get
                          let Bridge l r = br
                          cands <- sequence [ getPrev l >>~ \a -> colinearTime a l r
                                            , getNext l >>~ \b -> colinearTime l b r
                                            , getPrev r >>~ \c -> colinearTime l c r
                                            , getNext r >>~ \d -> colinearTime l r d
                                            ]
                          pure $ minimum' [t | c@(ValB t) <- cands, now < c]
  where
    c >>~ k = lift c >>= \case
                Nothing -> pure Bottom
                Just i  -> k i

--------------------------------------------------------------------------------


-- | compute the time at which r becomes colinear with the line throuh
-- p and q.
colinearTime       :: (Ord r, Fractional r) => Index -> Index -> Index -> Simulation s r (Bottom r)
colinearTime p q r = colinearTime' <$> pointAt' p <*> pointAt' q <*> pointAt' r

-- | compute the time at which r becomes colinear with the line through
-- p and q.
--
-- pre: x-order is: p,q,r
colinearTime'  :: (Ord r, Fractional r) => Point 3 r -> Point 3 r -> Point 3 r -> Bottom r
colinearTime' (Point3 px py pz) (Point3 qx qy qz) (Point3 rx ry rz) =
    if b == 0 then Bottom else ValB $ a / b
  where        -- by unfolding the def of ccw
    ux = qx - px
    vx = rx - px
    a = ux*(rz - pz)  - vx*(qz - pz)
    b = ux*(ry - py)  - vx*(qy - py)
  -- b == zero means the three points are on a vertical plane. This corresponds
  -- to t = -\infty.



--------------------------------------------------------------------------------

myPts :: NonEmpty (Point 3 (RealNumber 10) :+ Int)
myPts = NonEmpty.fromList $ [ Point3 5  5  0  :+ 2
                            , Point3 1  1  10 :+ 1
                            , Point3 0  10 20 :+ 0
                            , Point3 12 1  1  :+ 3
                            , Point3 22 20  1  :+ 4
                            ]

-- myResult = [1 2 3
--             2 3 4
--             0 1 2
--             0 2 4
--            ]

myPts' :: NonEmpty (Point 3 (RealNumber 10) :+ Int)
myPts' = NonEmpty.fromList $ [ Point3 5  5  0  :+ 2
                             , Point3 1  1  10 :+ 1
                             , Point3 0  10 20 :+ 0
                             , Point3 12 1  1  :+ 3
                             ]

-- 1 2 3
-- 0 1 2
-- 0 2 3


test :: IO ()
test = mapM_ print $ lowerHull' myPts

test' :: IO ()
test' = mapM_ print $ lowerHull' myPts'

buggyPoints :: NonEmpty (Point 3 (RealNumber 10) :+ Int)
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



-- [Triangle (Point3 [0,-70,-20] :+ 2) (Point3 [20,-70,0] :+ 3) (Point3 [70,-50,-60] :+ 8)
-- ,Triangle (Point3 [-70,20,40] :+ 0) (Point3 [-40,70,-50] :+ 1) (Point3 [0,-70,-20] :+ 2)
-- ,Triangle (Point3 [-40,70,-50] :+ 1) (Point3 [0,-70,-20] :+ 2) (Point3 [70,-50,-60] :+ 8)
-- ,Triangle (Point3 [-40,70,-50] :+ 1) (Point3 [60,60,60] :+ 7) (Point3 [70,-50,-60] :+ 8)]



-- [Triangle (Point3 [-70,20,40] :+ 0) (Point3 [-40,70,-50] :+ 1) (Point3 [0,-70,-20] :+ 2)
--   ,Triangle (Point3 [-40,70,-50] :+ 1) (Point3 [0,-70,-20] :+ 2) (Point3 [70,-50,-60] :+ 8)
--   ,Triangle (Point3 [-40,70,-50] :+ 1) (Point3 [60,60,60] :+ 7) (Point3 [70,-50,-60] :+ 8)
--   ,Triangle (Point3 [0,-70,-20] :+ 2) (Point3 [20,-70,0] :+ 3) (Point3 [70,-50,-60] :+ 8)]


subs :: SP Index [Event (RealNumber 10)]
subs = simulateLeaf' . NonEmpty.fromList $   [Point3 2    (-7) 0    :+ 3
                                             ,Point3 2    (-6) (-2) :+ 4
                                             ,Point3 2    5    4    :+ 5
                                             ]

-- SP 5 [0.33333333333~ :+ InsertAfter 5 3 :| [Delete 5]]

type R = RealNumber 10
buggyPoints2 :: NonEmpty (Point 3 R :+ Int)
buggyPoints2 = fmap (bimap (10 *^) id) . NonEmpty.fromList $ [ Point3 (-5) (-3) 4 :+ 0
                                                             , Point3 (-5) (-2) 5 :+ 1
                                                             , Point3 (-5) (-1) 4 :+ 2
                                                             , Point3 (0) (2)   2 :+ 3
                                                             , Point3 (1) (-5)  4 :+ 4
                                                             , Point3 (3) (-3)  2 :+ 5
                                                             , Point3 (3) (-1)  1 :+ 6
                                                             ]


-- [Triangle (Point3 [-50,-30,40] :+ 0) (Point3 [10,-50,40] :+ 4) (Point3 [30,-30,20] :+ 5)
-- ,Triangle (Point3 [-50,-30,40] :+ 0) (Point3 [0,20,20] :+ 3) (Point3 [30,-10,10] :+ 6)
-- ,Triangle (Point3 [-50,-30,40] :+ 0) (Point3 [-50,-10,40] :+ 2) (Point3 [0,20,20] :+ 3)]


-- should be:
--[Triangle (Point3 [-50,-30,40] :+ 0) (Point3 [-50,-10,40] :+ 2) (Point3 [0,20,20] :+ 3)
--,Triangle (Point3 [-50,-30,40] :+ 0) (Point3 [0,20,20] :+ 3) (Point3 [30,-10,10] :+ 6)
--,Triangle (Point3 [-50,-30,40] :+ 0) (Point3 [10,-50,40] :+ 4) (Point3 [30,-30,20] :+ 5)
-- missing:
-- ,Triangle (Point3 [-50,-30,40] :+ 0) (Point3 [30,-30,20] :+ 5) (Point3 [30,-10,10] :+ 6)]




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

buggyPoints4 :: NonEmpty (Point 3 R :+ Int)
buggyPoints4 = fmap (bimap (10 *^) id) . NonEmpty.fromList $
 [Point3 (-3) 1 2 :+ 0
 ,Point3 0 1 1 :+ 1
 ,Point3 3 (-1) 0 :+ 2
 ,Point3 3 0 0 :+ 3
 ]

               -- expected: H

               -- [Triangle (Point3 [-3,1,2] :+ 0) (Point3 [0,1,1] :+ 1) (Point3 [3,-1,0] :+ 2)
               -- ,Triangle (Point3 [-3,1,2] :+ 0) (Point3 [0,1,1] :+ 1) (Point3 [3,0,0] :+ 3)
               -- ,Triangle (Point3 [-3,1,2] :+ 0) (Point3 [3,-1,0] :+ 2) (Point3 [3,0,0] :+ 3)
               -- ,Triangle (Point3 [0,1,1] :+ 1) (Point3 [3,-1,0] :+ 2) (Point3 [3,0,0] :+ 3)]


               -- but got: H
               -- [Triangle (Point3 [-3,1,2] :+ 0) (Point3 [3,-1,0] :+ 2) (Point3 [3,0,0] :+ 3)
               -- ,Triangle (Point3 [-3,1,2] :+ 0) (Point3 [0,1,1] :+ 1) (Point3 [3,0,0] :+ 3)]


point3 :: [r] -> Point 3 r
point3 = fromJust . pointFromList

buggyPoints5 :: NonEmpty (Point 3 R :+ Int)
buggyPoints5 = mkBuggy $ buggyPoints5'

mkBuggy = fmap (bimap (10 *^) id) . NonEmpty.fromList


buggyPoints5' :: [Point 3 R :+ Int]
buggyPoints5' = [point3 [-21,14,-4]   :+ 0
                ,point3 [-16,-15,-14] :+ 1
                ,point3 [-14,12,16]   :+ 4
                ,point3 [-11,-19,-7]  :+ 5
                ,point3 [-9,18,14]    :+ 6
                ,point3 [-7,5,5]      :+ 7
                ,point3 [-6,14,11]    :+ 8
                ,point3 [-3,16,10]    :+ 10
                ,point3 [1,-4,0]      :+ 11
                ,point3 [1,19,14]     :+ 12
                ,point3 [3,4,-7]      :+ 13
                ,point3 [6,-8,22]     :+ 14
                ,point3 [8,6,12]      :+ 15
                ,point3 [12,-2,-17]   :+ 16
                ,point3 [23,-18,14]   :+ 19
                ,point3 [23,-6,-18]   :+ 20
                ]
