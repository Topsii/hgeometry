{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Demo.VisibilityPolygon where

import           Algorithms.Geometry.VisibilityPolygon.Lee (visibilityPolygon, StarShapedPolygon, Definer)
import           Control.Lens
import           Data.Data
import           Data.Either (partitionEithers)
import           Data.Ext
import           Data.Geometry
import           Data.Geometry.HalfLine
import           Data.Geometry.Ipe
import           Data.Geometry.Triangulation.Draw
import qualified Data.List.NonEmpty as NonEmpty
import           Data.RealNumber.Rational
import           Data.Semigroup
import           Data.Tree.Draw
import           Options.Applicative

import Debug.Trace

type R = RealNumber 5


data Options = Options { _inPath    :: FilePath
                       , _outFile   :: FilePath
                       }
               deriving Data

options :: ParserInfo Options
options = info (helper <*> parser)
               (  progDesc "Compute the visibility polygon in the input file."
               <> header   "VisibilityPolygon"
               )
  where
    parser = Options
          <$> strOption (help "Input file (in ipe7 xml format)"
                         <> short 'i'
                        )
          <*> strOption (help "Output File (in ipe7 xml format)"
                         <> short 'o'
                        )


compute            :: (p ~ ()) => Polygon t p R :+ e
                   -> (Point 2 R, StarShapedPolygon (Definer p () R) R)
compute (pg :+ _)  = let q = pickPoint pg
                     in traceShow (q,pg) (q, visibilityPolygon q pg)

mainWith                          :: Options -> IO ()
mainWith (Options inFile outFile) =
  do
    Right page <- readSinglePageFile inFile
    let (simples' :: [SimplePolygon () R :+ IpeAttributes Path R]) = readAll page
        simples = map (over core toCounterClockWiseOrder) simples'
        (points' :: [Point 2 R :+ IpeAttributes IpeSymbol R]) = readAll page
        (points, visibilities) = unzip . map compute $ simples
        visibilities2 = [visibilityPolygon q pg
                        | pg :+ _ <- simples, q :+ _ <- points']

        out  = concat [ map iO' points
                      , map (\vis -> iO $ defIO vis ! attr SFill (IpeColor "blue"))
                            visibilities2
                      , map (\(pg :+ ats) -> iO'' pg ats) simples
                      ]
    writeIpeFile outFile . singlePageFromContent $ out
