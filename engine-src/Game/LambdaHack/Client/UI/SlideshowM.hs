-- | Monadic operations on slideshows and related data.
module Game.LambdaHack.Client.UI.SlideshowM
  ( overlayToSlideshow, reportToSlideshow, reportToSlideshowKeepHalt
  , displaySpaceEsc, displayMore, displayMoreKeep, displayYesNo, getConfirms
  , displayChoiceScreen
  ) where

import Prelude ()

import Game.LambdaHack.Core.Prelude

import           Data.Either
import qualified Data.EnumMap.Strict as EM
import qualified Data.Map.Strict as M
import qualified Data.Text as T

import           Game.LambdaHack.Client.UI.Content.Screen
import           Game.LambdaHack.Client.UI.ContentClientUI
import           Game.LambdaHack.Client.UI.Frame
import           Game.LambdaHack.Client.UI.FrameM
import qualified Game.LambdaHack.Client.UI.Key as K
import           Game.LambdaHack.Client.UI.MonadClientUI
import           Game.LambdaHack.Client.UI.Msg
import           Game.LambdaHack.Client.UI.MsgM
import           Game.LambdaHack.Client.UI.Overlay
import           Game.LambdaHack.Client.UI.PointUI
import           Game.LambdaHack.Client.UI.SessionUI
import           Game.LambdaHack.Client.UI.Slideshow
import           Game.LambdaHack.Client.UI.UIOptions
import qualified Game.LambdaHack.Definition.Color as Color

-- | Add current report to the overlay, split the result and produce,
-- possibly, many slides.
overlayToSlideshow :: MonadClientUI m
                   => Int -> [K.KM] -> OKX -> m Slideshow
overlayToSlideshow y keys okx = do
  CCUI{coscreen=ScreenContent{rwidth}} <- getsSession sccui
  UIOptions{uMsgWrapColumn} <- getsSession sUIOptions
  report <- getReportUI True
  recordHistory  -- report will be shown soon, remove it to history
  fontSetup <- getFontSetup
  return $! splitOverlay fontSetup rwidth y uMsgWrapColumn report keys okx

-- | Split current report into a slideshow.
reportToSlideshow :: MonadClientUI m => [K.KM] -> m Slideshow
reportToSlideshow keys = do
  CCUI{coscreen=ScreenContent{rheight}} <- getsSession sccui
  overlayToSlideshow (rheight - 2) keys (EM.empty, [])

-- | Split current report into a slideshow. Keep report unchanged.
-- Assume the game either halts waiting for a key after this is shown,
-- or many slides are produced, all but the last are displayed
-- with player promts between and the last is either shown
-- in full or ignored if inside macro (can be recovered from history,
-- if important). Unless the prompts interrupt the macro, which is as well.
reportToSlideshowKeepHalt :: MonadClientUI m => Bool -> [K.KM] -> m Slideshow
reportToSlideshowKeepHalt insideMenu keys = do
  CCUI{coscreen=ScreenContent{rwidth, rheight}} <- getsSession sccui
  UIOptions{uMsgWrapColumn} <- getsSession sUIOptions
  report <- getReportUI insideMenu
  -- Don't do @recordHistory@; the message is important, but related
  -- to the messages that come after, so should be shown together.
  fontSetup <- getFontSetup
  return $! splitOverlay fontSetup rwidth (rheight - 2) uMsgWrapColumn
                         report keys (EM.empty, [])

-- | Display a message. Return value indicates if the player wants to continue.
-- Feature: if many pages, only the last SPACE exits (but first ESC).
displaySpaceEsc :: MonadClientUI m => ColorMode -> Text -> m Bool
displaySpaceEsc dm prompt = do
  unless (T.null prompt) $ msgLnAdd MsgPromptGeneric prompt
  -- Two frames drawn total (unless @prompt@ very long).
  slides <- reportToSlideshow [K.spaceKM, K.escKM]
  km <- getConfirms dm [K.spaceKM, K.escKM] slides
  return $! km == K.spaceKM

-- | Display a message. Ignore keypresses.
-- Feature: if many pages, only the last SPACE exits (but first ESC).
displayMore :: MonadClientUI m => ColorMode -> Text -> m ()
displayMore dm prompt = do
  unless (T.null prompt) $ msgLnAdd MsgPromptGeneric prompt
  slides <- reportToSlideshow [K.spaceKM]
  void $ getConfirms dm [K.spaceKM, K.escKM] slides

displayMoreKeep :: MonadClientUI m => ColorMode -> Text -> m ()
displayMoreKeep dm prompt = do
  unless (T.null prompt) $ msgLnAdd MsgPromptGeneric prompt
  slides <- reportToSlideshowKeepHalt True [K.spaceKM]
  void $ getConfirms dm [K.spaceKM, K.escKM] slides

-- | Print a yes/no question and return the player's answer. Use black
-- and white colours to turn player's attention to the choice.
displayYesNo :: MonadClientUI m => ColorMode -> Text -> m Bool
displayYesNo dm prompt = do
  unless (T.null prompt) $ msgLnAdd MsgPromptGeneric prompt
  let yn = map K.mkChar ['y', 'n']
  slides <- reportToSlideshow yn
  km <- getConfirms dm (K.escKM : yn) slides
  return $! km == K.mkChar 'y'

getConfirms :: MonadClientUI m
            => ColorMode -> [K.KM] -> Slideshow -> m K.KM
getConfirms dm extraKeys slides = do
  ekm <- displayChoiceScreen "" dm False slides extraKeys
  return $! either id (error $ "" `showFailure` ekm) ekm

-- | Display a, potentially, multi-screen menu and return the chosen
-- key or item slot label (and the index in the whole menu so that the cursor
-- can again be placed at that spot next time menu is displayed).
--
-- This function is the only source of menus and so, effectively, UI modes.
displayChoiceScreen :: forall m . MonadClientUI m
                    => String -> ColorMode -> Bool -> Slideshow -> [K.KM]
                    -> m KeyOrSlot
displayChoiceScreen menuName dm sfBlank frsX extraKeys = do
  (maxIx, initIx, clearIx, m) <-
    stepChoiceScreen menuName dm sfBlank frsX extraKeys
  let loop :: Int -> m (KeyOrSlot, Int)
      loop pointer = do
        (final, km, pointer1) <- m pointer
        if final
        then return (km, pointer1)
        else loop pointer1
  wrapInMenuIx menuName maxIx initIx clearIx loop

wrapInMenuIx :: MonadClientUI m
             => String -> Int -> Int -> Int
             -> (Int -> m (KeyOrSlot, Int))
             -> m KeyOrSlot
wrapInMenuIx menuName maxIx initIx clearIx m = do
  menuIxMap <- getsSession smenuIxMap
  -- Beware, values in @menuIxMap@ may be negative (meaning: a key, not slot).
  let menuIx = if menuName == ""
               then clearIx
               else maybe clearIx (+ initIx) (M.lookup menuName menuIxMap)
  (km, pointer) <- m $ max clearIx $ min maxIx menuIx
                     -- clamping needed, because the saved menu index could be
                     -- from different context
  let !_A = assert (clearIx <= pointer && pointer <= maxIx) ()
  unless (menuName == "") $
    modifySession $ \sess ->
      sess {smenuIxMap = M.insert menuName (pointer - initIx) menuIxMap}
  return km

-- | This is one step of UI menu management user session.
--
-- There is limited looping involved to return a changed position
-- in the menu each time so that the surrounding code has anything
-- interesting to do. The exception is when finally confirming a selection,
-- in which case it's usually not changed compared to last step,
-- but it's presented differently to indicate it was confirmed.
stepChoiceScreen :: forall m . MonadClientUI m
                 => String -> ColorMode -> Bool -> Slideshow -> [K.KM]
                 -> m ( Int, Int, Int
                      , Int -> m (Bool, KeyOrSlot, Int) )
stepChoiceScreen menuName dm sfBlank frsX extraKeys = do
  let !_A = assert (K.escKM `elem` extraKeys) ()
      frs = slideshow frsX
      keys = concatMap (lefts . map fst . snd) frs ++ extraKeys
      legalKeys = keys
                  ++ navigationKeys
                  ++ [K.mkChar '?' | menuName == "help"]  -- a hack
      maxIx = length (concatMap snd frs) - 1
      allOKX = concatMap snd frs
      initIx = case findIndex (isRight . fst) allOKX of
        Just p -> p
        _ -> 0  -- can't be @length allOKX@ or a multi-page item menu
                -- mangles saved index of other item munus
      clearIx = if initIx > maxIx then 0 else initIx
      page :: Int -> m (Bool, KeyOrSlot, Int)
      page pointer = assert (pointer >= 0) $ case findKYX pointer frs of
        Nothing -> error $ "no menu keys" `showFailure` frs
        Just ( (ovs, kyxs)
             , (ekm, (PointUI x1 y, buttonWidth))
             , ixOnPage ) -> do
          let ovs1 = EM.map (updateLine y $ drawHighlight x1 buttonWidth) ovs
              tmpResult pointer1 = return (False, ekm, pointer1)
              ignoreKey = tmpResult pointer
              pageLen = length kyxs
              xix :: KYX -> Bool
              xix (_, (PointUI x1' _, _)) = x1' <= x1 + 2 && x1' >= x1 - 2
              firstRowOfNextPage = pointer + pageLen - ixOnPage
              restOKX = drop firstRowOfNextPage allOKX
              firstItemOfNextPage = case findIndex (isRight . fst) restOKX of
                Just p -> p + firstRowOfNextPage
                _ -> firstRowOfNextPage
              interpretKey :: K.KM -> m (Bool, KeyOrSlot, Int)
              interpretKey ikm =
                case K.key ikm of
                  _ | ikm == K.controlP -> do
                    -- Silent, because any prompt would be shown too late.
                    printScreen
                    ignoreKey
                  K.Return -> case ekm of
                    Left km ->
                      if K.key km == K.Return && km `elem` keys
                      then return (True, Left km, pointer)
                      else interpretKey km
                    Right c -> return (True, Right c, pointer)
                  K.LeftButtonRelease -> do
                    PointUI mx my <- getsSession spointer
                    let onChoice (_, (PointUI cx cy, ButtonWidth font clen)) =
                          let blen | isSquareFont font = 2 * clen
                                   | otherwise = clen
                          in my == cy && mx >= cx && mx < cx + blen
                    case find onChoice kyxs of
                      Nothing | ikm `elem` keys ->
                        return (True, Left ikm, pointer)
                      Nothing -> if K.spaceKM `elem` keys
                                 then return (True, Left K.spaceKM, pointer)
                                 else ignoreKey
                      Just (ckm, _) -> case ckm of
                        Left km ->
                          if K.key km == K.Return && km `elem` keys
                          then return (True, Left km, pointer)
                          else interpretKey km
                        Right c  -> return (True, Right c, pointer)
                  K.RightButtonRelease ->
                    if | ikm `elem` keys -> return (True, Left ikm, pointer)
                       | K.escKM `elem` keys ->
                           return (True, Left K.escKM, pointer)
                       | otherwise -> ignoreKey
                  K.Space | firstItemOfNextPage <= maxIx ->
                    tmpResult firstItemOfNextPage
                  K.Char '?' | firstItemOfNextPage <= maxIx
                               && menuName == "help" ->  -- a hack
                    tmpResult firstItemOfNextPage
                  K.Unknown "SAFE_SPACE" ->
                    if firstItemOfNextPage <= maxIx
                    then tmpResult firstItemOfNextPage
                    else tmpResult clearIx
                  _ | ikm `elem` keys ->
                    return (True, Left ikm, pointer)
                  K.Up -> case findIndex xix $ reverse $ take ixOnPage kyxs of
                    Nothing -> interpretKey ikm{K.key=K.Left}
                    Just ix -> tmpResult (max 0 (pointer - ix - 1))
                  K.Left -> if pointer == 0 then tmpResult maxIx
                            else tmpResult (max 0 (pointer - 1))
                  K.Down -> case findIndex xix $ drop (ixOnPage + 1) kyxs of
                    Nothing -> interpretKey ikm{K.key=K.Right}
                    Just ix -> tmpResult (pointer + ix + 1)
                  K.Right -> if pointer == maxIx then tmpResult 0
                             else tmpResult (min maxIx (pointer + 1))
                  K.Home -> tmpResult clearIx
                  K.End -> tmpResult maxIx
                  _ | K.key ikm `elem` [K.PgUp, K.WheelNorth] ->
                    tmpResult (max 0 (pointer - ixOnPage - 1))
                  _ | K.key ikm `elem` [K.PgDn, K.WheelSouth] ->
                    -- This doesn't scroll by screenful when header very long
                    -- and menu non-empty, but that scenario is rare, so OK,
                    -- arrow keys may be used instead.
                    tmpResult (min maxIx firstItemOfNextPage)
                  K.Space -> if pointer == maxIx
                             then tmpResult clearIx
                             else tmpResult maxIx
                  _ -> error $ "unknown key" `showFailure` ikm
          pkm <- promptGetKey dm ovs1 sfBlank legalKeys
          interpretKey pkm
      m pointer =
        if null frs
        then return (True, Left K.escKM, pointer)
        else do
          (final, km, pointer1) <- page pointer
          let !_A1 = assert (either (`elem` keys) (const True) km) ()
          let !_A2 = assert (clearIx <= pointer1 && pointer1 <= maxIx) ()
          return (final, km, pointer1)
  return (maxIx, initIx, clearIx, m)

navigationKeys :: [K.KM]
navigationKeys = [ K.leftButtonReleaseKM, K.rightButtonReleaseKM
                 , K.returnKM, K.spaceKM
                 , K.upKM, K.leftKM, K.downKM, K.rightKM
                 , K.pgupKM, K.pgdnKM, K.wheelNorthKM, K.wheelSouthKM
                 , K.homeKM, K.endKM, K.controlP ]

-- | Find a position in a menu.
-- The arguments go from first menu line and menu page to the last,
-- in order. Their indexing is from 0. We select the nearest item
-- with the index equal or less to the pointer.
findKYX :: Int -> [OKX] -> Maybe (OKX, KYX, Int)
findKYX _ [] = Nothing
findKYX pointer (okx@(_, kyxs) : frs2) =
  case drop pointer kyxs of
    [] ->  -- not enough menu items on this page
      case findKYX (pointer - length kyxs) frs2 of
        Nothing ->  -- no more menu items in later pages
          case reverse kyxs of
            [] -> Nothing
            kyx : _ -> Just (okx, kyx, length kyxs - 1)
        res -> res
    kyx : _ -> Just (okx, kyx, pointer)

drawHighlight :: Int -> ButtonWidth -> Int -> AttrString -> AttrString
drawHighlight x1 (ButtonWidth font len) xstart as =
  let highableAttrs = [Color.defAttr, Color.defAttr {Color.fg = Color.BrBlack}]
      highAttr c | Color.acAttr c `notElem` highableAttrs
                   || Color.acChar c == ' ' = c
      highAttr c = c {Color.acAttr =
                        (Color.acAttr c) {Color.fg = Color.BrWhite}}
      cursorAttr c = c {Color.acAttr =
                          (Color.acAttr c)
                            {Color.bg = Color.HighlightNoneCursor}}
      -- This also highlights dull white item symbols, but who cares.
      lenUI = if isSquareFont font then len * 2 else len
      x1MinusXStartChars = if isSquareFont font
                           then (x1 - xstart) `div` 2
                           else x1 - xstart
      (as1, asRest) = splitAt x1MinusXStartChars as
      (as2, as3) = splitAt len asRest
      highW32 = Color.attrCharToW32
                . highAttr
                . Color.attrCharFromW32
      cursorW32 = Color.attrCharToW32
                  . cursorAttr
                  . Color.attrCharFromW32
      as2High = case map highW32 as2 of
        [] -> []
        ch : chrest -> cursorW32 ch : chrest
  in if x1 + lenUI < xstart
     then as
     else as1 ++ as2High ++ as3
