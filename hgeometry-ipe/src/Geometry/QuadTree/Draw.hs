{-# LANGUAGE UnicodeSyntax #-}
{-# LANGUAGE OverloadedStrings #-}
--------------------------------------------------------------------------------
-- |
-- Module      :  Geometry.QuadTree.Draw
-- Copyright   :  (C) Frank Staals
-- License     :  see the LICENSE file
-- Maintainer  :  Frank Staals
--
-- Machinery for drawing cells.
--
--------------------------------------------------------------------------------
module Geometry.QuadTree.Draw where

import           Data.Ext
import qualified Data.Foldable as F
import           Ipe.Attributes
import           Ipe.IpeOut
import           Ipe.Types
import           Geometry.QuadTree
import           Geometry.QuadTree.Cell
import qualified Data.Text as T
import           Data.Tree.Util (TreeNode(..))
--------------------------------------------------------------------------------

-- | Draw a quadTree cell as a Path
drawCell :: Fractional r => IpeOut (Cell r) Path r
drawCell = ipeRectangle . toBox

-- | Draws an entire quadtree.
drawQuadTree :: (Fractional r, Ord r) => IpeOut (QuadTree v p r) Group r
drawQuadTree = drawQuadTreeWith (\(_ :+ c) -> drawCell c)

-- | Draw a quadtree with a given method for drawing the cells.
drawQuadTreeWith           :: (ToObject i, Fractional r, Ord r)
                           => IpeOut (p :+ Cell r) i r -> IpeOut (QuadTree v p r) Group r
drawQuadTreeWith drawCell' = ipeGroup . fmap (iO . drawCell') . leaves . withCells

-- | Draw every cell of a level of the quadtree.
quadTreeLevels           :: forall i r v p. (ToObject i, Fractional r, Ord r
                                            )
                         => IpeOut (TreeNode v p :+ Cell r) i r -> IpeOut (QuadTree v p r) Group r
quadTreeLevels drawCell' = \qt -> let lvls = fmap (fmap flip') . perLevel . withCells $ qt
                                  in ipeGroup . fmap iO . zipWith drawLevel [1..] . F.toList $ lvls
  where
    flip' = \case
      InternalNode (v :+ c) -> InternalNode v :+ c
      LeafNode (l :+ c)     -> LeafNode l     :+ c

    -- drawLevel   :: Int -> IpeOut (NonEmpty (TreeNode v p :+ Cell r)) Group r
    drawLevel i = ipeGroup . fmap (\n -> iO $ ipeGroup [iO $ drawCell' n] ! attr SLayer (layer i))

    layer   :: Int -> LayerName
    layer i = LayerName $ "level_" <> T.pack (show i)
