Name: TAS Wizard

Description: A mod for creating tool-assisted speedruns of Spelunky 2.

----------------

## Overview

TAS Wizard is a mod for creating tool-assisted speedruns of Spelunky 2.

TAS Wizard is meant to be used in combination with [Overlunky](https://github.com/spelunky-fyi/overlunky). You will need a reasonable understanding of how to install and use Overlunky. Many of the tools needed to create a good TAS are part of Overlunky itself, such as frame advancing and camera hacks. TAS Wizard provides the ability to record and play back TASes, and offers supplementary features that are not already available in Overlunky.

Be warned, this is **not** a simple mod to use. It is a complicated tool with a lot of features.

## Documentation

Documentation for TAS Wizard is maintained on the [TAS Wizard readme](https://github.com/Cosine256/spelunky-2-tas-wizard#readme) on GitHub. This includes installation steps, terminology, known issues, and more. The documentation is still a work-in-progress, but should cover most basic information about the mod.

## I Need Your Feedback

TAS Wizard is a complicated mod. Although I've tried my best to make it robust and suitable for public use, most of its functionality is based on my own personal needs and preferences, and I can't be sure I've tested every possible edge case. I want to know about any bugs or other issues you encounter while using TAS Wizard. If I don't know that an issue exists, then I can't fix it.

Before submitting an issue, check the [Known Issues and Limitations](https://github.com/Cosine256/spelunky-2-tas-wizard#known-issues-and-limitations) on GitHub to see whether I already know about a particular issue. Please submit your issues and feedback in the `#tas-wizard` channel on [my Discord server](https://discord.gg/ZMBXuGRPt4). If you know how to submit issues on the GitHub project, then that is also acceptable, but is not required. Please do not privately message me about TAS Wizard issues, as this prevents other people from seeing whether a problem has already been reported or is being discussed. The following are examples of things I would like to know about:

- Errors or bugs. Please provide thorough steps on how the reproduce the issue.
- Desync issues. If you have a TAS file that does not play back consistently despite always using the same settings, then I want to look into it.
- Usability issues. If a feature seems particularly confusing or difficult to use, then I want to know about it. Let me know what problems you have with the feature and what would make it easier to use. Just keep in mind that TAS Wizard is a complicated mod by design. I'm not going to simplify things if it requires giving up functionality that might be useful to somebody, and I do not want to develop and maintain a "simple mode" alongside the full feature set.
- Information in the GitHub readme that seems to be incorrect.
- Issues with a display refresh rate greater than 60Hz. I do not own a display that can run faster than 60Hz, so I have not been able to test this at all.
- Issues with a widescreen display. I do not own a widescreen display and have only been able to do testing on a 16:9 display.

## Q&A

Q: *Why is my run desyncing when I didn't change anything?*
A: Check whether you have OL godmode active, or had it active while recording and then turned it off.

Q: *Why is my run timer inconsistent?*
A: The run timer increases while the pause menu is open, even during playback, and tabbing out automatically opens the pause menu.

Q: *Why does my TAS randomly stop recording or playing back?*
A: You might be encountering desync or errors that trigger an automatic switch to freeplay mode. When this happens, an explanatory message should appear somewhere on the screen. Depending on your Overlunky or Playlunky settings, the message can be very small and easy to miss.

Q: *Is this really all of the Q&A?*
A: This mod's documentation is still a work-in-progress. I'll be improving the documentation over time, possibly including a more thorough Q&A section.

Q: *On the Itchy & Scratchy CD-ROM, is there a way to get out of the dungeon without using the Wizard Key?*
A: What the hell are you talking about?

## Changelog

### 1.1.1 (2024-05-05)

- Improved performance when displaying large player paths.
- Fixed Waddler's storage and Tun aggro sometimes desynchronizing when using screen snapshots.

### 1.1.0 (2024-02-28)

- Upgraded to new freeze pause system in the script API. Pausing works on any frame now.
- Removed cutscene skip editor. You can now record cutscene inputs while pausing and frame advancing just like any other part of the TAS.
- Fixed janky fades when warping.

### 1.0.0 (2023-10-31)

- Initial release.

## Special Thanks

- **TAS Tool example script in Overlunky**: For being my inspiration to start working on this mod.
- **Script API team**: For providing such a powerful modding API and adding various things I needed for this mod.
- **My Twitch followers**: For putting up with me teasing this mod for 8 months before finally releasing it.

## Links

- [TAS Wizard GitHub](https://github.com/Cosine256/spelunky-2-tas-wizard)
- [My Discord server](https://discord.gg/ZMBXuGRPt4)
- [My Twitch channel](https://www.twitch.tv/cosine256)
- [My YouTube channel](https://www.youtube.com/channel/UCxqWmMm9iYJXq_92PZVETnQ)
