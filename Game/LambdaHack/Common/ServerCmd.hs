{-# LANGUAGE OverloadedStrings #-}
-- | Abstract syntax of server commands.
-- See
-- <https://github.com/kosmikus/LambdaHack/wiki/Client-server-architecture>.
module Game.LambdaHack.Common.ServerCmd
  ( CmdSer(..), CmdSerTakeTime(..), aidCmdSer, aidCmdSerTakeTime
  , FailureSer(..), showFailureSer
  ) where

import Data.Text (Text)

import Game.LambdaHack.Common.Actor
import Game.LambdaHack.Common.Item
import Game.LambdaHack.Common.Level
import Game.LambdaHack.Common.Msg
import Game.LambdaHack.Common.Point
import Game.LambdaHack.Common.Vector

-- | Abstract syntax of server commands.
data CmdSer =
    TakeTimeSer CmdSerTakeTime
  | GameRestartSer ActorId Text
  | GameExitSer ActorId
  | GameSaveSer ActorId
  | CfgDumpSer ActorId
  deriving (Show)

data CmdSerTakeTime =
    MoveSer ActorId Vector
  | ExploreSer ActorId Vector
  | RunSer ActorId Vector
  | WaitSer ActorId
  | PickupSer ActorId ItemId Int InvChar
  | DropSer ActorId ItemId
  | ProjectSer ActorId Point Int ItemId Container
  | ApplySer ActorId ItemId Container
  | TriggerSer ActorId Point
  | SetPathSer ActorId [Vector]
  deriving (Show)

-- | The actor that start performing the command (may be dead, after
-- the command is performed).
aidCmdSer :: CmdSer -> ActorId
aidCmdSer cmd = case cmd of
  TakeTimeSer cmd2 -> aidCmdSerTakeTime cmd2
  GameRestartSer aid _ -> aid
  GameExitSer aid -> aid
  GameSaveSer aid -> aid
  CfgDumpSer aid -> aid

aidCmdSerTakeTime :: CmdSerTakeTime -> ActorId
aidCmdSerTakeTime cmd = case cmd of
  MoveSer aid _ -> aid
  ExploreSer aid _ -> aid
  RunSer aid _ -> aid
  WaitSer aid -> aid
  PickupSer aid _ _ _ -> aid
  DropSer aid _ -> aid
  ProjectSer aid _ _ _ _ -> aid
  ApplySer aid _ _ -> aid
  TriggerSer aid _ -> aid
  SetPathSer aid _ -> aid

data FailureSer =
    RunDisplaceAccess
  | ProjectAimOnself
  | ProjectBlockTerrain
  | ProjectBlockActor
  | TriggerBlockActor
  | TriggerBlockItem
  | TriggerNothing

showFailureSer :: FailureSer -> Msg
showFailureSer failureSer = case failureSer of
  RunDisplaceAccess -> "changing places without access"
  ProjectAimOnself -> "cannot aim at oneself"
  ProjectBlockTerrain -> "obstructed by terrain"
  ProjectBlockActor -> "blocked by an actor"
  TriggerBlockActor -> "blocked by an actor"
  TriggerBlockItem -> "jammed by an item"
  TriggerNothing -> "wasting time on triggering nothing"
