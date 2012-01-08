-- | Generation of caves (not yet inhabited dungeon levels) from cave kinds.
module Game.LambdaHack.Cave
  ( Cave(..), SecretMapXY, ItemMapXY, TileMapXY, buildCave
  ) where

import Control.Monad
import qualified Data.Map as M
import qualified Data.Set as S
import qualified Data.List as L

import Game.LambdaHack.Utils.Assert
import Game.LambdaHack.Geometry
import Game.LambdaHack.Area
import Game.LambdaHack.AreaRnd
import Game.LambdaHack.Item
import Game.LambdaHack.Random
import qualified Game.LambdaHack.Tile as Tile
import qualified Game.LambdaHack.Kind as Kind
import Game.LambdaHack.Content.CaveKind
import Game.LambdaHack.Content.TileKind
import qualified Game.LambdaHack.Feature as F
import Game.LambdaHack.WorldLoc
import Game.LambdaHack.Place

-- All maps used here are sparse. In case of the tile map, the default tile
-- is specified in the cave kind specification.

type SecretMapXY = M.Map (X, Y) SecretStrength

type ItemMapXY = M.Map (X, Y) Item

data Cave = Cave
  { dkind     :: !(Kind.Id CaveKind)  -- ^ the kind of the cave
  , dsecret   :: SecretMapXY
  , ditem     :: ItemMapXY
  , dmap      :: TileMapXY
  , dmeta     :: String
  }
  deriving Show

{-
Rogue cave is generated by an algorithm inspired by the original Rogue,
as follows:

  * The available area is divided into a grid, e.g, 3 by 3,
    where each of the 9 grid cells has approximately the same size.

  * In each of the 9 grid cells one room is placed at a random location
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
-- | Cave generated by an algorithm inspired by the original Rogue,
buildCave :: Kind.COps -> LevelId -> Int -> Kind.Id CaveKind -> Rnd Cave
buildCave Kind.COps{ cotile=cotile@Kind.Ops{okind=tokind, opick, ofoldrWithKey}
                   , cocave=Kind.Ops{okind}
                   , coplace=Kind.Ops{okind=pokind, opick=popick}}
          lvl depth ci = do
  let CaveKind{..} = okind ci
  lgrid@(gx, gy) <- rollDiceXY cgrid
  lminplace <- rollDiceXY $ cminPlaceSize
  let gs = grid lgrid (0, 0, cxsize - 1, cysize - 1)
  mandatory1 <- replicateM (cnonVoidMin `div` 2) $
                  xyInArea (0, 0, gx `div` 3, gy - 1)
  mandatory2 <- replicateM (cnonVoidMin `divUp` 2) $
                  xyInArea (gx - 1 - (gx `div` 3), 0, gx - 1, gy - 1)
  places0 <- mapM (\ (i, r) -> do
                     rv <- chance $ cvoidChance
                     r' <- if rv && i `notElem` (mandatory1 ++ mandatory2)
                           then mkVoidPlace r
                           else mkPlace lminplace r
                     return (i, r')) gs
  dlplaces <- mapM (\ (_, r) -> do
                      c <- chanceQuad lvl depth cdarkChance
                      return (r, not c)) places0
  connects <- connectGrid lgrid
  addedConnects <-
    if gx * gy > 1
    then let caux = round $ cauxConnects * fromIntegral (gx * gy)
         in replicateM caux (randomConnection lgrid)
    else return []
  let allConnects = L.nub (addedConnects ++ connects)
      places = M.fromList places0
  cs <- mapM (\ (p0, p1) -> do
                 let r0 = places M.! p0
                     r1 = places M.! p1
                 connectPlaces r0 r1) allConnects
  wallId <- opick "fillerWall" (const True)
  let fenceBounds = (1, 1, cxsize - 2, cysize - 2)
      fence = buildFence wallId fenceBounds
  pickedCorTile <- opick ccorTile (const True)
  lplaces <- foldM (\ m (r@(x0, _, x1, _), dl) ->
                    if x0 == x1
                    then return m
                    else do
                      placeId <- popick "rogue" (placeValid r)
                      let kr = pokind placeId
                      floorId <- if dl
                                 then opick "floorRoomLit" (const True)
                                 else opick "floorRoomDark" (const True)
                      legend <- olegend cotile
                      let (tmap, _place) =  -- TODO: store and use place
                            digPlace placeId kr
                              legend floorId wallId pickedCorTile r
                      return $ M.union tmap m
                  ) fence dlplaces
  let lcorridors = M.unions (L.map (digCorridors pickedCorTile) cs)
      getHidden ti tk acc =
        if Tile.canBeHidden cotile tk
        then do
          ti2 <- opick "hidden" $ \ k -> Tile.kindHasFeature F.Hidden k
                                         && Tile.similar k tk
          m <- acc
          return $ M.insert ti ti2 m
        else acc
  hidden <- ofoldrWithKey getHidden (return M.empty)
  let lm = M.unionWith (mergeCorridor cotile hidden) lcorridors lplaces
  -- Convert openings into doors, possibly.
  (dmap, secretMap) <-
    let f (l, le) ((x, y), t) =
          if Tile.hasFeature cotile F.Hidden t
          then do
            -- Openings have a certain chance to be doors;
            -- doors have a certain chance to be open; and
            -- closed doors have a certain chance to be hidden
            rd <- chance cdoorChance
            if not rd
              then return (M.insert (x, y) pickedCorTile l, le)
              else do
                doorClosedId <- trigger cotile t
                doorOpenId   <- trigger cotile doorClosedId
                ro <- chance copenChance
                if ro
                  then do
                    return (M.insert (x, y) doorOpenId l, le)
                  else do
                    rs <- chance chiddenChance
                    if not rs
                      then do
                        return (M.insert (x, y) doorClosedId l, le)
                      else do
                        let getDice (F.Secret dice) _ = dice
                            getDice _ acc = acc
                            d = foldr getDice (RollDice 5 2)
                                  (tfeature (tokind t))
                        rs1 <- rollDice d
                        return (l, M.insert (x, y) (SecretStrength rs1) le)
          else return (l, le)
    in foldM f (lm, M.empty) (M.toList lm)
  let cave = Cave
        { dkind = ci
        , dsecret = secretMap
        , ditem = M.empty
        , dmap
        , dmeta = show allConnects
        }
  return cave

olegend :: Kind.Ops TileKind -> Rnd (M.Map Char (Kind.Id TileKind))
olegend Kind.Ops{ofoldrWithKey, opick} =
  let getSymbols _ tk acc =
        maybe acc (const $ S.insert (tsymbol tk) acc)
          (L.lookup "legend" $ tfreq tk)
      symbols = ofoldrWithKey getSymbols S.empty
      getLegend s acc = do
        m <- acc
        tk <- opick "legend" $ (== s) . tsymbol
        return $ M.insert s tk m
      legend = S.fold getLegend (return M.empty) symbols
  in legend

trigger :: Kind.Ops TileKind -> Kind.Id TileKind -> Rnd (Kind.Id TileKind)
trigger Kind.Ops{okind, opick} t =
  let getTo (F.ChangeTo group) _ = Just group
      getTo _ acc = acc
  in case foldr getTo Nothing (tfeature (okind t)) of
       Nothing    -> return t
       Just group -> opick group (const True)

type Corridor = [(X, Y)]

-- | Create a random place according to given parameters.
mkPlace :: (X, Y)    -- ^ minimum size
        -> Area      -- ^ this is the area, not the place itself
        -> Rnd Area  -- ^ upper-left and lower-right corner of the place
mkPlace (xm, ym) (x0, y0, x1, y1) =
  let area0 = (x0, y0, x1 - xm + 1, y1 - ym + 1)
  in assert (validArea area0 `blame` area0) $ do
    (rx0, ry0) <- xyInArea area0
    let area1 = (rx0 + xm - 1, ry0 + ym - 1, x1, y1)
      in assert (validArea area1 `blame` area1) $ do
      (rx1, ry1) <- xyInArea area1
      return (rx0, ry0, rx1, ry1)

-- | Create a void place, i.e., a single corridor field.
mkVoidPlace :: Area     -- ^ this is the area, not the place itself
            -> Rnd Area -- ^ upper-left and lower-right corner of the place
mkVoidPlace area = assert (validArea area `blame` area) $ do
  (ry, rx) <- xyInArea area
  return (ry, rx, ry, rx)

digCorridors :: Kind.Id TileKind -> Corridor -> TileMapXY
digCorridors tile (p1:p2:ps) =
  M.union corPos (digCorridors tile (p2:ps))
 where
  corXY  = fromTo p1 p2
  corPos = M.fromList $ L.zip corXY (repeat tile)
digCorridors _ _ = M.empty

passable :: [F.Feature]
passable = [F.Walkable, F.Openable, F.Hidden]

mergeCorridor :: Kind.Ops TileKind
              -> (M.Map (Kind.Id TileKind) (Kind.Id TileKind))
              -> Kind.Id TileKind -> Kind.Id TileKind -> Kind.Id TileKind
mergeCorridor cotile _    _ t
  | L.any (\ f -> Tile.hasFeature cotile f t) passable = t
mergeCorridor _ secretMap _ t = secretMap M.! t
