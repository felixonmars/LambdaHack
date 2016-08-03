-- | Generation of caves (not yet inhabited dungeon levels) from cave kinds.
module Game.LambdaHack.Server.DungeonGen.Cave
  ( Cave(..), buildCave
  ) where

import Prelude ()

import Game.LambdaHack.Common.Prelude

import Control.Arrow ((&&&))
import qualified Data.EnumMap.Strict as EM
import Data.Key (mapWithKeyM)
import qualified Data.Map.Strict as M

import qualified Game.LambdaHack.Common.Kind as Kind
import Game.LambdaHack.Common.Level
import Game.LambdaHack.Common.Point
import Game.LambdaHack.Common.Random
import qualified Game.LambdaHack.Common.Tile as Tile
import Game.LambdaHack.Common.Vector
import Game.LambdaHack.Content.CaveKind
import Game.LambdaHack.Content.PlaceKind
import Game.LambdaHack.Content.TileKind (TileKind)
import Game.LambdaHack.Server.DungeonGen.Area
import Game.LambdaHack.Server.DungeonGen.AreaRnd
import Game.LambdaHack.Server.DungeonGen.Place

-- | The type of caves (not yet inhabited dungeon levels).
data Cave = Cave
  { dkind   :: !(Kind.Id CaveKind)  -- ^ the kind of the cave
  , dmap    :: !TileMapEM           -- ^ tile kinds in the cave
  , dplaces :: ![Place]             -- ^ places generated in the cave
  , dnight  :: !Bool                -- ^ whether the cave is dark
  }
  deriving Show

{-
Rogue cave is generated by an algorithm inspired by the original Rogue,
as follows:

  * The available area is divided into a grid, e.g, 3 by 3,
    where each of the 9 grid cells has approximately the same size.

  * In each of the 9 grid cells one room is placed at a random position
    and with a random size, but larger than The minimum size,
    e.g, 2 by 2 floor tiles.

  * Rooms that are on horizontally or vertically adjacent grid cells
    may be connected by a corridor. Corridors consist of 3 segments of straight
    lines (either "horizontal, vertical, horizontal" or "vertical, horizontal,
    vertical"). They end in openings in the walls of the room they connect.
    It is possible that one or two of the 3 segments have length 0, such that
    the resulting corridor is L-shaped or even a single straight line.

  * Corridors are generated randomly in such a way that at least every room
    on the grid is connected, and a few more might be. It is not sufficient
    to always connect all adjacent rooms.
-}
-- TODO: fix identifier naming and split, after the code grows some more
-- | Cave generation by an algorithm inspired by the original Rogue,
buildCave :: Kind.COps         -- ^ content definitions
          -> AbsDepth          -- ^ depth of the level to generate
          -> AbsDepth          -- ^ absolute depth
          -> Kind.Id CaveKind  -- ^ cave kind to use for generation
          -> Rnd Cave
buildCave cops@Kind.COps{ cotile=cotile@Kind.Ops{opick}
                        , cocave=Kind.Ops{okind}
                        , coplace=Kind.Ops{okind=pokind}
                        , coTileSpeedup }
          ldepth totalDepth dkind = do
  let kc@CaveKind{..} = okind dkind
  lgrid@(gx, gy) <- castDiceXY ldepth totalDepth cgrid
  -- Make sure that in caves not filled with rock, there is a passage
  -- across the cave, even if a single room blocks most of the cave.
  -- Also, ensure fancy outer fences are not obstructed by room walls.
  let fullArea = fromMaybe (assert `failure` kc)
                 $ toArea (0, 0, cxsize - 1, cysize - 1)
      subFullArea = fromMaybe (assert `failure` kc)
                    $ toArea (1, 1, cxsize - 2, cysize - 2)
      area | gx * gy == 1
             || couterFenceTile /= "basic outer fence" = subFullArea
           | otherwise = fullArea
      gs = grid lgrid area
  (addedConnects, voidPlaces) <-
    if gx * gy > 1 then do
       let fractionOfPlaces r = round $ r * fromIntegral (gx * gy)
           cauxNum = fractionOfPlaces cauxConnects
       addedC <- replicateM cauxNum (randomConnection lgrid)
       let gridArea = fromMaybe (assert `failure` lgrid)
                      $ toArea (0, 0, gx - 1, gy - 1)
           voidNum = fractionOfPlaces cmaxVoid
       voidPl <- replicateM voidNum $ xyInArea gridArea  -- repetitions are OK
       return (addedC, voidPl)
    else return ([], [])
  minPlaceSize <- castDiceXY ldepth totalDepth cminPlaceSize
  maxPlaceSize <- castDiceXY ldepth totalDepth cmaxPlaceSize
  places0 <- mapM (\ (i, r) -> do
                     -- Reserved for corridors and the global fence.
                     let innerArea = fromMaybe (assert `failure` (i, r))
                                     $ shrink r
                     r' <- if i `elem` voidPlaces
                           then Left <$> mkVoidRoom innerArea
                           else Right <$> mkRoom minPlaceSize
                                                    maxPlaceSize innerArea
                     return (i, r')) gs
  fence <- buildFenceRnd cops couterFenceTile subFullArea
  dnight <- chanceDice ldepth totalDepth cnightChance
  darkCorTile <- fromMaybe (assert `failure` cdarkCorTile)
                 <$> opick cdarkCorTile (const True)
  litCorTile <- fromMaybe (assert `failure` clitCorTile)
                <$> opick clitCorTile (const True)
  let pickedCorTile = if dnight then darkCorTile else litCorTile
      addPl (m, pls, qls) (i, Left r) = return (m, pls, (i, Left r) : qls)
      addPl (m, pls, qls) (i, Right r) = do
        (tmap, place) <-
          buildPlace cops kc dnight darkCorTile litCorTile ldepth totalDepth r
        return (EM.union tmap m, place : pls, (i, Right (r, place)) : qls)
  (lplaces, dplaces, qplaces0) <- foldM addPl (fence, [], []) places0
  connects <- connectGrid lgrid
  let allConnects = connects `union` addedConnects  -- no duplicates
      qplaces = M.fromList qplaces0
  cs <- mapM (\(p0, p1) -> do
                let shrinkPlace (r, Place{qkind}) =
                      case shrink r of
                        Nothing -> (r, r)  -- FNone place of x and/or y size 1
                        Just sr ->
                          if pfence (pokind qkind) `elem` [FFloor, FGround]
                          then
                            -- Avoid corridors touching the floor fence,
                            -- but let them merge with the fence.
                            case shrink sr of
                              Nothing -> (sr, r)
                              Just mergeArea -> (mergeArea, r)
                          else (sr, sr)
                    shrinkForFence = either (id &&& id) shrinkPlace
                    rr0 = shrinkForFence $ qplaces M.! p0
                    rr1 = shrinkForFence $ qplaces M.! p1
                connectPlaces rr0 rr1) allConnects
  let lcorridors = EM.unions (map (digCorridors pickedCorTile) cs)
      lm = EM.union lplaces lcorridors
      -- Convert wall openings into doors, possibly.
      f pos (hidden, cor) = do
        -- Openings have a certain chance to be doors
        -- and doors have a certain chance to be open.
        rd <- chance cdoorChance
        if rd then do  -- door created
          ro <- chance copenChance
          doorClosedId <- Tile.revealAs cotile hidden
          if ro then Tile.openTo cotile doorClosedId
                else return $! doorClosedId
        else do  -- opening kept
          if Tile.isLit coTileSpeedup cor then return cor
          else do
            -- If any cardinally adjacent room tile lit, make the opening lit.
            let roomTileLit p =
                  case EM.lookup p lplaces of
                    Nothing -> False
                    Just tile -> Tile.isLit coTileSpeedup tile
                vic = vicinityCardinal cxsize cysize pos
            if any roomTileLit vic
            then return litCorTile
            else return cor
      -- The hacks below are instead of unionWithKeyM, which is costly.
      mergeCor _ pl cor =
        let hidden = Tile.hideAs cotile pl
        in if hidden == pl then Nothing  -- boring tile, can't hide doors
                           else Just (hidden, cor)
      intersectionWithKeyMaybe combine =
        EM.mergeWithKey combine (const EM.empty) (const EM.empty)
      interCor = intersectionWithKeyMaybe mergeCor lplaces lcorridors  -- fast
  doorMap <- mapWithKeyM f interCor  -- very small
  let dmap = EM.union doorMap lm
      cave = Cave
        { dkind
        , dmap
        , dplaces
        , dnight
        }
  return $! cave

digCorridors :: Kind.Id TileKind -> Corridor -> TileMapEM
digCorridors tile (p1:p2:ps) =
  EM.union corPos (digCorridors tile (p2:ps))
 where
  cor  = fromTo p1 p2
  corPos = EM.fromList $ zip cor (repeat tile)
digCorridors _ _ = EM.empty
