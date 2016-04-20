-- | The default game key-command mapping to be used for UI. Can be overridden
-- via macros in the config file.
module Client.UI.Content.KeyKind ( standardKeys ) where

import Control.Arrow (first)

import qualified Game.LambdaHack.Client.Key as K
import Game.LambdaHack.Client.UI.Content.KeyKind
import Game.LambdaHack.Client.UI.HumanCmd
import Game.LambdaHack.Common.Misc
import qualified Game.LambdaHack.Content.ItemKind as IK
import qualified Game.LambdaHack.Content.TileKind as TK

-- | Description of default key-command bindings.
--
-- In addition to these commands, mouse and keys have a standard meaning
-- when navigating various menus.
standardKeys :: KeyKind
standardKeys = KeyKind
  { rhumanCommands = map (first K.mkKM) $
      -- All commands are defined here, except some movement and leader picking
      -- commands. All commands are shown on help screens except debug commands
      -- and macros with empty descriptions.
      -- The order below determines the order on the help screens.
      -- Remember to put commands that show information (e.g., enter targeting
      -- mode) first.

      -- Main Menu
      [ ("Escape", ([CmdMainMenu], Alias "back to playing" Clear))
      , ("?", ([CmdMainMenu], Alias "see command help" (Help Nothing) ))
      , ("S", ([CmdMainMenu], Alias "enter settings menu" SettingsMenu))
      , ("X", ([CmdMainMenu], GameExit))
      , ("r", ([CmdMainMenu], GameRestart "raid"))
      , ("s", ([CmdMainMenu], GameRestart "skirmish"))
      , ("a", ([CmdMainMenu], GameRestart "ambush"))
      , ("b", ([CmdMainMenu], GameRestart "battle"))
      , ("c", ([CmdMainMenu], GameRestart "campaign"))
      , ("i", ([CmdMainMenu, CmdDebug], GameRestart "battle survival"))
      , ("f", ([CmdMainMenu, CmdDebug], GameRestart "safari"))
      , ("u", ([CmdMainMenu, CmdDebug], GameRestart "safari survival"))
      , ("d", ([CmdMainMenu, CmdDebug], GameRestart "defense"))
      , ("g", ([CmdMainMenu, CmdDebug], GameRestart "boardgame"))
      , ("D", ([CmdMainMenu], GameDifficultyIncr))
      , ("A", ([CmdMainMenu], Automate))

      -- Settings Menu  -- TODO: add some from ClientOptions
      , ("Escape", ([CmdSettingsMenu], Alias "back to Main Menu" MainMenu))
      , ("T", ([CmdSettingsMenu], Tactic))
      , ("S", ([CmdSettingsMenu], MarkSuspect))
      , ("V", ([CmdSettingsMenu], MarkVision))
      , ("C", ([CmdSettingsMenu], MarkSmell))

      -- Movement and terrain alteration
      , ("<", ([CmdMove, CmdItem, CmdMinimal], getAscend))
      , ("g", ([CmdMove, CmdItem], Alias "" getAscend))
      , ("comma", ([CmdInternal], Alias "" getAscend))
      , ("CTRL-<", ([CmdInternal], TriggerTile  -- with lifts, not interal
           [TriggerFeature { verb = "ascend"
                           , object = "10 levels"
                           , feature = TK.Cause (IK.Ascend 10) }]))
      , (">", ([CmdMove, CmdItem, CmdMinimal], descendDrop))
      , ("d", ([CmdMove, CmdItem], Alias "" descendDrop))
      , ("period", ([CmdInternal], Alias "" descendDrop))
      , ("CTRL->", ([CmdInternal], TriggerTile
           [TriggerFeature { verb = "descend"
                           , object = "10 levels"
                           , feature = TK.Cause (IK.Ascend (-10)) }]))
      , ("semicolon", ( [CmdMove]
                      , Alias "go to crosshair for 100 steps"
                        $ Macro ["CTRL-semicolon", "CTRL-period", "V"] ))
      , ("colon", ( [CmdMove]
                  , Alias "run selected to crosshair for 100 steps"
                    $ Macro ["CTRL-colon", "CTRL-period", "V"] ))
      , ("x", ( [CmdMove]
              , Alias "explore the closest unknown spot"
                $ Macro [ "CTRL-?"  -- no semicolon
                      , "CTRL-period", "V" ] ))
      , ("X", ( [CmdMove]
              , Alias "autoexplore 100 times"
                $ Macro  ["'", "CTRL-?", "CTRL-period", "'", "V"] ))
      , ("R", ([CmdMove], Alias"rest (wait 100 times)" $ Macro ["KP_5", "V"]))
      , ("c", ([CmdMove, CmdMinimal], AlterDir
           [ AlterFeature { verb = "close"
                          , object = "door"
                          , feature = TK.CloseTo "vertical closed door Lit" }
           , AlterFeature { verb = "close"
                          , object = "door"
                          , feature = TK.CloseTo "horizontal closed door Lit" }
           , AlterFeature { verb = "close"
                          , object = "door"
                          , feature = TK.CloseTo "vertical closed door Dark" }
           , AlterFeature { verb = "close"
                          , object = "door"
                          , feature = TK.CloseTo "horizontal closed door Dark" }
           ]))

      -- Item use
      , ("f", ([CmdItem], Project
           [ApplyItem { verb = "fling"
                      , object = "projectile"
                      , symbol = ' ' }]))
      , ("a", ([CmdItem], Apply
           [ApplyItem { verb = "apply"
                      , object = "consumable"
                      , symbol = ' ' }]))
      , ("e", ( [CmdItem], MoveItem [CGround, CInv, CSha] CEqp Nothing
                                    "item" False))
      , ("p", ([CmdItem], MoveItem [CGround, CEqp, CSha] CInv Nothing
                                   "item into inventory" False))
      , ("s", ( [CmdItem], MoveItem [CGround, CInv, CEqp] CSha Nothing
                                    "and share item" False))
      , ("E", ([CmdItem], chooseAndHelp $ MStore CEqp))
      , ("P", ([CmdItem, CmdMinimal], chooseAndHelp $ MStore CInv))
      , ("S", ([CmdItem], chooseAndHelp $ MStore CSha))
      , ("A", ([CmdItem], chooseAndHelp MOwned))
      , ("G", ([CmdItem], chooseAndHelp $ MStore CGround))
      , ("@", ([CmdItem], chooseAndHelp $ MStore COrgan))
      , ("!", ([CmdItem], chooseAndHelp MStats))
      , ("q", ([CmdItem], Apply [ApplyItem { verb = "quaff"
                                           , object = "potion"
                                           , symbol = '!' }]))
      , ("r", ([CmdItem], Apply [ApplyItem { verb = "read"
                                           , object = "scroll"
                                           , symbol = '?' }]))
      , ("t", ([CmdItem], Project [ApplyItem { verb = "throw"
                                             , object = "missile"
                                             , symbol = '|' }]))
--      , ("z", ([CmdItem], Project [ApplyItem { verb = "zap"
--                                             , object = "wand"
--                                             , symbol = '/' }]))

      -- Targeting
      , ("KP_Multiply", ([CmdTgt], TgtEnemy))
      , ("\\", ([CmdTgt], Alias "" TgtEnemy))
      , ("KP_Divide", ([CmdTgt], TgtFloor))
      , ("|", ([CmdTgt], Alias "" TgtFloor))
      , ("+", ([CmdTgt, CmdMinimal], EpsIncr True))
      , ("-", ([CmdTgt], EpsIncr False))
      , ("CTRL-?", ([CmdTgt], CursorUnknown))
      , ("CTRL-I", ([CmdTgt], CursorItem))
      , ("CTRL-{", ([CmdTgt], CursorStair True))
      , ("CTRL-}", ([CmdTgt], CursorStair False))
      , ("BackSpace", ([CmdTgt], TgtClear))
      , ("Escape", ( [CmdTgt, CmdMinimal]
                   , Alias "cancel target/action or open Main Menu"
                     $ ByMode MainMenu Cancel ))
      , ("Return", ( [CmdTgt, CmdMinimal]
                   , Alias "accept target/choice or open Help"
                     $ ByMode (Help $ Just "") Accept ))

      -- Assorted
      , ("space", ([CmdMeta], Clear))
      , ("?", ([CmdMeta], Help Nothing))
      , ("D", ([CmdMeta, CmdMinimal], History))
      , ("Tab", ([CmdMeta], MemberCycle))
      , ("ISO_Left_Tab", ([CmdMeta, CmdMinimal], MemberBack))
      , ("=", ([CmdMeta], SelectActor))
      , ("_", ([CmdMeta], SelectNone))
      , ("v", ([CmdMeta], Repeat 1))
      , ("V", ([CmdMeta], Repeat 100))
      , ("CTRL-v", ([CmdMeta], Repeat 1000))
      , ("CTRL-V", ([CmdMeta], Repeat 25))
      , ("'", ([CmdMeta], Record))

      -- Mouse
      -- Doubleclick acts as RMB and modifiers as MMB, which is optional.
      , ("LeftButtonPress", ([CmdMouse], defaultCmdLMB))
      , ("SHIFT-LeftButtonPress", ([CmdInternal], defaultCmdMMB))
      , ("CTRL-LeftButtonPress", ([CmdInternal], defaultCmdMMB))
      , ("MiddleButtonPress", ([CmdMouse], defaultCmdMMB))
      , ("RightButtonPress", ([CmdMouse], defaultCmdRMB))

      -- Debug and others not to display in help screens
      , ("CTRL-S", ([CmdDebug], GameSave))
      , ("CTRL-semicolon", ([CmdInternal], MoveOnceToCursor))
      , ("CTRL-colon", ([CmdInternal], RunOnceToCursor))
      , ("CTRL-period", ([CmdInternal], ContinueToCursor))
      , ("CTRL-comma", ([CmdInternal], RunOnceAhead))
      ]
      ++ map defaultHeroSelect [0..6]
  }
