# TAS Wizard

TAS Wizard is a mod for creating tool-assisted speedruns of Spelunky 2.

TAS Wizard is meant to be used in combination with [Overlunky](https://github.com/spelunky-fyi/overlunky#readme). Many of the tools needed to create a good TAS are part of Overlunky itself, such as frame advancing and camera hacks. TAS Wizard provides the ability to record and play back TASes, and offers supplementary features that are not already available in Overlunky.

This is **not** a simple mod to use. It is a complicated tool with a lot of features. This readme is still a work-in-progress. It covers several concepts about TAS Wizard, but does not yet have a comprehensive tutorial about how to use it.

## What is a TAS?

TAS stands for tool-assisted speedrun (or superplay). A TAS is a set of starting conditions and a sequence of game inputs which can be played back identically every time. The input sequence is created by playing the game with slow-down, frame advance, save states, camera hacks, and other tools to assist the user. You can rerecord any part of the input sequence to fix mistakes, manipulate PRNG, abuse glitches, and optimize the run as much as possible. The final product is a speedrun or superplay with superhuman reaction times and precision. A TAS does not modify the actual mechanics of the game engine, meaning that the input sequence can be played back to show what it would look like if somebody performed that exact run in real-time.

TASes are not meant to compete with real-time speedruns played by humans. The two types of runs are not comparable. Real-time speedrunners are playing the game with human skill, reaction times, and in the case of Spelunky 2, a considerable amount of luck. In a TAS, you are solving the game like a puzzle. You have as much time as you need to apply your game knowledge and problem-solving skills to craft the perfect speedrun. It's a demonstration of what is theoretically possible within the game engine. TASes should only compete with other TASes. A TAS is only cheating if you intentionally misrepresent it as a real-time speedrun played by a human.

Creating a TAS can be a slow and complicated process. Depending on how "perfect" you want your run to be, you may find yourself spending hours working on a single minute of real-time gameplay. Spelunky 2 is a game with tremendous technical complexity, and understanding this tech is crucial to creating an optimal TAS. You are highly encouraged to visit the science and speedrunning channels in the [Spelunky Community Discord](https://discord.gg/spelunky-community) for help. Many of the techniques used in real-time speedruns are applicable to TASes.

## Installation and Loading

### Installing Modlunky and TAS Wizard

You will need to understand how to install mods and run Spelunky 2 via [Modlunky](https://github.com/spelunky-fyi/modlunky2#readme). If you are already familiar with modding Spelunky 2, then just install [TAS Wizard](https://spelunky.fyi/mods/m/tas-wizard/) like any other mod and then skip ahead to the [Nightly Builds](#nightly-builds) section. If Modlunky is new to you, then refer to the [Modlunky documentation](https://github.com/spelunky-fyi/modlunky2/wiki#quick-start) for instructions. The Modlunky instructions also explain how to install individual mods like TAS Wizard. TAS Wizard's mod download page and install code are located [here](https://spelunky.fyi/mods/m/tas-wizard/). [Overlunky](https://github.com/spelunky-fyi/overlunky#readme) and [Playlunky](https://github.com/spelunky-fyi/Playlunky#readme) are included with Modlunky and do not need to be installed separately.

All of this can be confusing if you have never modded Spelunky 2 before. If you are having problems with Modlunky, Overlunky, or Playlunky, or if you don't understand what you need to do, then seek assistance in the Spelunky 2 modding help channel in the [Spelunky Community Discord](https://discord.gg/spelunky-community).

### Nightly Builds

TAS Wizard is using fairly new script API features. TAS Wizard will fail to load with a descriptive error message if it detects that your current version of Overlunky or Playlunky is incompatible with it. If this error message is shown, then you need to update to the latest nightly builds of Overlunky and/or Playlunky, depending on which method you use to load TAS Wizard. The "nightly" build (sometimes called the "WHIP" build for Overlunky) is the most recent release of Overlunky or Playlunky and may include features that are not available yet in the stable build. Note that the nightly builds may be unstable and more likely to have bugs. If you encounter crashes or unusual problems even after TAS Wizard loads properly, then there might be a newer nightly build that fixes it. Be sure to also check whether TAS Wizard has a newer release. If this still doesn't solve the problem and you're not sure what the root cause is, then you can report it as a TAS Wizard issue and I can determine whether it's a problem with TAS Wizard or the nightly build.

### Loading TAS Wizard

Two different ways to load TAS Wizard are listed below.

#### Load via Overlunky

**This is the recommended method for loading TAS Wizard.** It will have clean interactions between TAS Wizard and Overlunky.

1. Use one of the following choices to launch the game.
    * Go to the *Overlunky* tab in Modlunky and use the *Launch vanilla game with Overlunky* button.
    * ... or launch vanilla Spelunky 2, then go to the *Overlunky* tab in Modlunky and attach Overlunky with *Inject to running game process*.
    * ... or launch Playlunky with the *Load Overlunky* option enabled. **Do not** enable TAS Wizard as a Playlunky mod. You don't want two copies of the mod loaded at once.
    * ... or launch Playlunky, then go to the *Overlunky* tab in Modlunky and attach Overlunky with *Inject to running game process*. **Do not** enable TAS Wizard as a Playlunky mod. You don't want two copies of the mod loaded at once.
2. In the game, open the Overlunky *Scripts* menu.
3. Enable the *Load scripts from Mods/Packs* option.
4. Use the *Search* input to find "TAS Wizard" in the list of scripts.
5. Enable the TAS Wizard script.

TAS Wizard is now loaded and active. You can always access its options via the Overlunky *Scripts* menu.

#### Load via Playlunky, then attach Overlunky

**This method is not recommended.** There are some buggy interactions between Playlunky and Overlunky caused by using two instances of the script API at the same time. This is not usually a problem for cosmetic mods such as custom skins, but TAS Wizard is a script mod and you may encounter some issues.

1. Go to the *Playlunky* tab in Modlunky.
2. Enable the "TAS Wizard" mod.
3. Enable the *Load Overlunky* option. Alternately, you can leave this disabled and inject Overlunky separately via the *Overlunky* tab after step 6.
4. Disable the *Speedrun Mode* option.
5. Ensure you are using the correct *Playlunky Version*. You will probably need "nightly".
6. Press the big *Play* button.

TAS Wizard is now loaded and active. You can always access its options via the Playlunky *Mod Options* panel. The default shortcut to open the *Mod Options* at any time is **Ctrl+F4**. Do not also load TAS Wizard as an Overlunky script. You don't want two copies of the mod loaded at once.

## Compatibility

### Other Mods

TAS Wizard is only designed to work on the vanilla game and on pure level generation mods, such as Jawnlunky. It is **not** designed to be used with other script mods. It will probably not work on "kaizo" mods, or script mods such as the Randomizer or HDmod. TAS Wizard cannot detect that it's incompatible with a particular mod, and is likely to fail in a confusing or catastrophic way while trying to record or play back a run. Support for some kaizo mods and script mods might be added at some point in the future.

To use TAS Wizard with a pure level gen mod, just load them both together. The level gen mod must always be loaded when working with its TAS files. TAS files don't inherently know when they are made for modded level gen. They will load no matter what mods are present, but they will immediately desync if the game's level generation doesn't match the generation they were recorded with.

If a level gen mod is non-deterministic for whatever reason, then TAS Wizard is unlikely to work with that particular mod. This should not happen if the level gen mod was designed correctly, but could occur if it uses tilecodes that don't properly poll the game's PRNG.

### Multiplayer

TAS Wizard fully supports **local co-op** with up to 4 players. It does not support local arena, and it does not support online modes.

### Platform

TAS Wizard only supports the Steam release of Spelunky 2. It will never work on another platform unless Playlunky and Overlunky themselves are updated to support that platform.

## Known Issues and Limitations

These are the significant known issues, bugs, and limitations with TAS Wizard. I intend to eventually fix these issues, but a lot of them are quite complicated or require changes to the script API.

### Bug: PRNG Desynchronization In Camp

The first time you load the camp in a game session, it might initialize with the wrong PRNG despite having the correct seed configured. This will affect things like the drop trajectory for the bomb and rope crates. It will work correctly on every subsequent visit during that game session, so just reload the camp by warping to it a second time before working on a TAS there.

### Clunky User Interface

The user interface is clunky, takes up a lot of space, and can be difficult to use. The GUI components available in the script API are limited and do not currently support features like menu bars, tabbed windows, and tooltips. I am working on getting these features added so that I can overhaul the TAS Wizard GUI.

### No Confirmation Prompts or Undos

The GUI does not prompt for confirmation when changing most TAS settings or editing frames. It's easy to accidentally delete TAS data or modify it in unintended ways, and there is no feature to undo these changes. Be careful and make frequent backups of your TAS files so you don't risk losing your hard work.

### Difficult To Record Complex Inputs

Currently, all inputs for all players need to be recorded by pressing all of the desired buttons simultaneously on each frame. This can be difficult if the player needs to press a lot of buttons on the same frame, and becomes nearly impossible if multiple players need to do this at the same time. The current workaround is to edit the inputs in the *Frames* panel after recording an empty frame, and then play back with the new inputs. I have plans to add an on-screen controller feature which will allow you to toggle individual buttons for each player before recording a frame.

### Menu Inputs Not Supported

TAS Wizard can only record and play back player inputs. Menu inputs are handled differently by the game engine and are not currently supported. This means that screens which require menu inputs are also not supported. As a result, TAS Wizard only supports a sequence of camp, level, transition, and spaceship cutscene screens. If any other types of screens are loaded, such as the death screen or the credits, then TAS Wizard will automatically stop recording because it can't interact with the game's UI. This effectively limits a TAS to a single run through the game, optionally starting in the camp.

### Game Progression Not Supported

TAS Wizard cannot save or load the user's game progression, and may not work correctly if told to play back a TAS with locked content. It will get stuck indefinitely if a transition screen has a shortcut progression dialog with Terra Tunnel. The tutorial race will not load correctly if the user hasn't unlocked it yet.

### Pet Choice

The choice of pet is not part of the start settings in a TAS, so playback will always use the game's current pet setting. Although the pet shouldn't have any effect on PRNG, it will affect constellations.

### Save States Not Supported

The script API offers save state functionality, but these save states currently have a lot of technical limitations and are not supported by TAS Wizard. TAS Wizard also can't detect when these save states are loaded and will desynchronize if they are used during recording or playback. TAS Wizard currently only supports [screen snapshots](#screen-snapshot), which are similar to save states, but are limited to screen loads.

### Large Player Paths Cause Lag

TAS screens with very large player paths may cause lag when player paths are enabled. This lag varies between computers, but it can start mildly around 10,000 frames and will worsen as more frames are added to the screen. Runs with multiple players will cause lag sooner due to each player having their own path. The lag only occurs while a TAS screen with large player paths is loaded in the game. Other screens with shorter paths will cause no problems. You can have a TAS with far more than 10,000 frames without any issues if those frames are distributed among multiple screens.

The lag is purely visual and will not affect the actual behavior of the game during TAS recording or playback. It will not occur when player paths are turned off in the options or disabled by presentation mode, so you can capture a video of your TAS without path lag even in very long screens.

### Large TAS File Size

TAS files are quite a bit larger than the amount of raw data they actually store, mostly due to their bulky human-readable JSON format. Saved screen snapshots significantly increase this size, and saved player positions increase it even more. Note that TAS files do compress fairly efficiently, although TAS Wizard itself is not capable of file compression. A two minute singleplayer TAS with snapshots and player positions is about 1MB in size, and standard ZIP compression reduces it to roughly 10% of its original size.

## Basic Terms and Concepts

There are some basic terms and concepts that will be helpful to understand when using TAS Wizard.

### Frame

For the purposes of TAS Wizard, a "TAS frame", often just called a "frame", is a game update in which the game reads inputs and executes one step of entity simulation. It is the smallest increment of time in which things can happen in the game. Spelunky 2's game engine always executes at 60 frames per second, regardless of the user's graphical refresh rate. TAS Wizard records the inputs of individual frames. When TAS Wizard shows the number of its "current frame", such as frame 123, this means that frame 123 was the most recent frame to execute on the current screen. The current game state is the outcome of frame 123, and frame 124 has not been executed yet. A current frame of 0 means that no frames have executed on the current screen. TAS Wizard does not track game updates in which no entities are updated, such as pauses, fade-ins, and fade-outs.

### Screen

A "TAS screen" is a collection of inputs and data separated by loading events. Examples include an instance of level 1-1, or a level transition, or a session in the base camp. Every screen has "screen type", which is controls some aspects of how the game engine and TAS Wizard will handle a particular TAS screen. Both of these terms are typically shortened to "screen" when the context is clear. A TAS contains a sequence of screens, each of which contains a sequence of frames. TAS Wizard only tracks the camp, level, transition, and spaceship cutscene screen types. It does not track any other screen types, such as menus, death, credits, or the arena. It ignores entering and exiting the options screen.

### Screen Snapshot

A "screen snapshot", often just called a "snapshot", is a copy of the game state at the time that a screen is being loaded. It contains all of the necessary information for TAS Wizard to restore the exact state of the game when it first loaded that screen. Snapshots can be loaded to quickly skip to a particular part of the TAS, and a snapshot can also be used as the starting state for a TAS. Screen snapshots are conceptually similar to the "save states" that are available in some games and TAS tools, but are limited to screen loads. Save states are not currently supported by TAS Wizard ([more info](#save-states-not-supported)).

### PRNG and Seed

Every time something "random" needs to to happen in Spelunky 2, the game engine uses something called "PRNG", which stands for pseudorandom number generation. The PRNG is initialized with a "seed", which is a large number that is used as the starting point for the sequence of seemingly random numbers that the game will generate. The algorithm for this is complicated and the numbers are extremely hard to predict, but the important part is that it's deterministic. This means that if a run is initialized with the same PRNG seed and starting conditions, and you play through the run with the same sequence of inputs, then the game will produce the exact same sequence of "random" numbers every time. This means the same level generation, same enemy AI, same item drops, same everything. This mechanic is what allows a TAS to play back the same way every time in a procedurally generated game like Spelunky 2. Every TAS includes a PRNG seed with its starting conditions. Although "PRNG" is not the same thing as true "RNG", the terms are basically interchangable in the context of Spelunky 2.

### Pause and Frame Advance

The term "pause" can have multiple meanings. Spelunky 2 has a pause menu, and a few other situations (such as fades and cutscenes) where only some parts of the game engine are paused. However, when creating a TAS, it's important that the entire game engine can be paused at any specific frame. During a full game engine pause, absolutely nothing in the game state will change. For the rest of this section, the term "pause" refers to full game engine pauses.

A "frame advance" is the act of briefly unpausing the game engine to allow exactly one frame to execute.

Since a frame is the smallest unit of time in the game engine, recording a TAS by frame advancing allows for maximally precise inputs. Recording while frame advancing works the same way as recording in real time. Whenever a game frame is executed, TAS Wizard will record the inputs that were held during that frame, regardless of whether or not a frame advance was used. You can create a TAS without pausing or frame advancing at all, but you will be recording it in real time and it will be much more difficult to perform precise inputs.

Using Overlunky for pausing and frame advancing is highly recommended. Overlunky provides hotkeys and a GUI with pause options that aren't exposed by TAS Wizard. TAS Wizard only has rudimentary buttons in its GUI to pause and frame advance.

Note that Overlunky also exposes some pause options that are not supported by TAS Wizard. In particular, TAS Wizard only supports a specific pause type. The supported pause type is shown in Overlunky as the following "Toggled pause flags": "Freeze updates", "Freeze game loop", and "Freeze input". By default, TAS Wizard has an option enabled that will automatically switch to the supported pause type. Other pause types may fail to pause in certain situations or cause other problems while working on a TAS. The other pause options in Overlunky are generally safe to use, but some of them can still interfere with TAS Wizard pausing. For example, if you enable the pause option to ignore freezing on level screens, then TAS Wizard will be unable to pause on that screen type.

### TAS Wizard Mode

There are three "modes" that TAS Wizard can be in while a TAS is loaded. These affect how TAS Wizard interacts with the game engine.

**Freeplay**: This is the default mode. You can freely play the game, warp around, explore a screen, or do anything else you'd like. TAS Wizard tracks the current screen, but it does not track the current frame, does not modify the loaded TAS, and does not submit inputs to the game.

**Recording**: As you play through the game, TAS Wizard will record player inputs every time a frame is executed, and will record screen changes.

**Playback**: TAS Wizard will play back the run using the currently recorded inputs. This will suppress your own player inputs, but you can still interact with the GUI and use features such as frame advancing.

Recording and playback modes require TAS Wizard to keep track of the current frame from the moment the current screen is loaded. The way this generally works is that you use the playback controls in the GUI to trigger playback to a particular point in the TAS. TAS Wizard will automatically determine how to get to there based on your configured settings. Once the playback target is reached, you can manually or automatically switch to recording mode. Switching to freeplay mode at any point will cause TAS Wizard to stop tracking the current frame, requiring another screen load if you want to switch back to recording or playback again.

When no active TAS is loaded, TAS Wizard is effectively locked to freeplay mode.

If a ghost TAS is loaded, then it is interally locked to freeplay mode. It will draw its player paths if a matching level is loaded, but will otherwise have no effect on the game.

### Desynchronization

TAS Wizard doesn't actually understand how Spelunky 2 is supposed to be played. All it's doing is recording inputs and screen changes, and then playing back those exact same inputs and expecting screen changes to occur at the exact same times. If you mess with the game state in an unexpected way during recording, such as using Overlunky to move the player or warp to a new level, then TAS Wizard is going to record it as though that's what was supposed to happen. If you record a TAS with godmode enabled and it prevents a player from taking damage, then TAS Wizard is expecting the player to also not take that damage during playback. If those events don't happen the same way during playback, then "desynchronization" (or just "desync") has occurred. This means that the game state during recording was different from the game state during playback.

TAS Wizard has some basic systems in place to detect and warn about potential desync, but it doesn't cover every situation. It can currently detect when players deviate from the positions they had during recording, and it can detect if a screen fails to unload on the frame where it was expected to do so. Other desync scenarios will not be automatically detected, although they might eventually trigger one of the detectable desync scenarios as a side effect.

Tips for avoiding desync:

* Ensure that no Overlunky cheats (such as godmode) are enabled during recording unless you also intend to keep them enabled during playback.
* Camera hacks are generally safe, but there are some obscure situations where the camera affects gameplay. Notably, the camera zoom affects how long it takes to play the cutscene after entering the large door in the camp, which can cause desync if the screen doesn't change at the correct time.
* Do not use Overlunky level warps while recording. TAS Wizard cannot tell the difference between an Overlunky warp and exiting a screen normally. Note that TAS Wizard's own warping system is safe to use during recording. A TAS Wizard warp will make it stop recording so that the warp won't get recorded into the TAS.
* Do not modify the level with Overlunky while recording. Spawning, moving, or destroying entities can desync a run even if they aren't directly in the path of the player. These modifications can change the PRNG sequence and cause something else to happen differently later in the level.
