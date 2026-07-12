BRIDGECUT CLEAN v0.4

This is the recovered clean, full-length BridgeCut project.
It is NOT the 60-second Preview build.

OPEN AND RUN
1. Unzip the folder.
2. Double-click BridgeCut.xcodeproj.
3. At the top of Xcode choose: BridgeCut > My Mac.
4. Press Command-R.

SUPPORTED INPUT
- Legacy .fcpxml files
- Final Cut Pro 12+ .fcpxmld bundles

OUTPUT
- <OriginalName>_BridgeCut.fcpxml in the same folder as the input.

WHAT IT CHANGES
- Active multicam audio angle names, using the custom FCP audio role/subrole.

WHAT IT DOES NOT CHANGE
- cuts
- offsets
- durations
- lanes
- srcCh
- audioChannels
- audioLayout
- mono/stereo/polyphonic channel structure
- multicam nesting

The original file is never modified.
Always test the output on a duplicate Resolve timeline before production use.
