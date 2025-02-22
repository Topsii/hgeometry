-- |
-- Module      :  Algorithms.Geometry.PolyLineSimplification.ImaiIri
-- Copyright   :  (C) Frank Staals
-- License     :  see the LICENSE file
-- Maintainer  :  Frank Staals
--------------------------------------------------------------------------------
module Algorithms.Geometry.PolyLineSimplification.ImaiIri
  ( simplify
  , simplifyWith
  ) where

import           Algorithms.Graph.BFS (bfs')
import           Control.Lens
import           Data.Ext
import qualified Data.Foldable as F
import           Geometry.LineSegment
import           Geometry.Point
import           Geometry.PolyLine
import           Geometry.Vector
import qualified Data.LSeq as LSeq
import           Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NonEmpty
import qualified Data.Sequence as Seq
import           Data.Tree
import qualified Data.Vector as V
import           Witherable

-- import Data.RealNumber.Rational
-- type R = RealNumber 5

--------------------------------------------------------------------------------

-- | Line simplification with the Imai-Iri alogrithm. Given a distance
-- value eps and a polyline pl, constructs a simplification of pl
-- (i.e. with vertices from pl) s.t. all other vertices are within
-- dist eps to the original polyline.
--
-- Running time: \( O(n^2) \) time.
simplify     :: (Ord r, Fractional r, Arity d)
             => r -> PolyLine d p r -> PolyLine d p r
simplify eps = simplifyWith $ \shortcut subPoly -> all (closeTo shortcut) (subPoly^.points)
  where
    closeTo seg (p :+ _) = squaredEuclideanDistTo p seg  <= epsSq
    epsSq = eps*eps

-- | Given a function that tests if the shortcut is valid, compute a
-- simplification using the Imai-Iri algorithm.
--
-- Running time: \( O(Tn^2 \) time, where \(T\) is the time to
-- evaluate the predicate.
simplifyWith            :: (LineSegment d p r -> PolyLine  d p r -> Bool)
                        -> PolyLine d p r -> PolyLine d p r
simplifyWith isValid pl = pl&points %~ (LSeq.promise @2 . extract path)
  where
    g    = mkGraph isValid pl
    spt  = bfs' 0 g
    path = case pathsTo (pl^.points.to F.length - 1) spt of
             []      -> error "no path found?"
             (pth:_) -> pth

----------------------------------------

type Graph = V.Vector [Int]

-- | Constructs the shortcut graph
mkGraph         :: (LineSegment d p r -> PolyLine d p r -> Bool) -> PolyLine d p r -> Graph
mkGraph isValid = flip V.snoc [] . V.imap f . V.fromList . F.toList . allPrefixes
  where
    f i subPl = catMaybes
              $ zipWith isValid' [i+1..] . F.toList . allSuffixes $ subPl

    isValid' j subPoly = let shortcut = ClosedLineSegment (subPoly^.start) (subPoly^.end)
                         in if isValid shortcut subPoly then Just j else Nothing

-- | Generates all prefixes of the polyline; i.e. all contiguous
-- polylines all starting at the original starting point.
allPrefixes    :: PolyLine d p r -> Seq.Seq (PolyLine d p r)
allPrefixes pl = mapMaybe mkPolyLine . Seq.tails . LSeq.toSeq $ pl^.points

mkPolyLine :: Seq.Seq (Point d r :+ p) -> Maybe (PolyLine d p r)
mkPolyLine = fmap PolyLine . LSeq.eval @2 . LSeq.fromSeq

-- | Generates all suffixes of the polyline.
allSuffixes :: PolyLine d p r -> Seq.Seq (PolyLine d p r)
allSuffixes pl = mapMaybe mkPolyLine . Seq.drop 2 . Seq.inits . LSeq.toSeq $ pl^.points






-- | Get all paths to the particular element in the tree.
pathsTo   :: Eq a => a -> Tree a -> [NonEmpty a]
pathsTo x = findPaths (== x)

-- | All paths to the nodes satisfying the predicate.
findPaths   :: (a -> Bool) -> Tree a -> [NonEmpty a]
findPaths p = go
  where
    go (Node x chs) = case foldMap go chs of
                        []    | p x       -> [x:|[]]
                              | otherwise -> []
                        paths | p x       -> (x:|[]) : map (x NonEmpty.<|) paths
                              | otherwise ->           map (x NonEmpty.<|) paths




-- | Given a non-empty list of indices, and some LSeq, extract the elemnets
-- on those indices.
--
-- running time: \(O(n)\)
extract    :: NonEmpty Int -> LSeq.LSeq n a -> LSeq.LSeq 0 a
extract is = LSeq.fromList . extract' (F.toList is) 0 . F.toList

extract'                                 :: [Int] -> Int -> [a] -> [a]
extract' []         _ _                  = []
extract' (_:_)      _ []                 = []
extract' is'@(i:is) j (x:xs) | i == j    = x : extract' is (j+1) xs
                             | otherwise = extract' is' (j+1) xs

--------------------------------------------------------------------------------


-- tr :: Tree Int
-- tr = Node 0 [Node 1 [], Node 2 [Node 3 [], Node 2 [], Node 4 [Node 5 []]]]

-- poly :: PolyLine 2 Int R
-- poly = case fromPoints [origin :+ 0, Point2 1 1 :+ 1, Point2 2 2 :+ 2, Point2 3 3 :+ 3] of
--          Just p -> p

-- test = Seq.fromList [0..5]

-- myTree :: Tree Int
-- myTree = Node {rootLabel = 0, subForest = [Node {rootLabel = 1, subForest = []}
--                                        ,Node {rootLabel = 2, subForest = []}
--                                        ,Node {rootLabel = 3, subForest = []}]
--            }
