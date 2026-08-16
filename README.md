# Bachelor Thesis

## Interactive music on a Tonnetz grid

This project is an interactive music system built with Godot 4.5. It combines a Tonnetz with Lindenmayer systems.

Each L-system becomes its own voice with a grammar, color, volume, playback state, and visual turtle trail. You can explore the grid, let voices play, record a walk, and evolve new voices from that recording.

## Godot Version

This project is made for **Godot 4.5**.

The project file also declares the Godot feature tag `4.5` in `project.godot`. Older Godot versions may not open or run the project correctly.

## License

This program is published under a Creative Commons license. It may be used, shared, and modified for non-commercial purposes.

Commercial use is not permitted without separate permission.

## Installation

### Using an Exported Build

Download the exported build for your operating system:

- Linux
- macOS
- Windows

Then start the executable included in the download.

On macOS, depending on Gatekeeper settings, you may need to allow the app manually in the system security settings the first time you open it.

### Running From Source

1. Install **Godot 4.5**
2. Clone or download this repository
3. Open Godot
4. Choose **Import** and select the `project.godot` file in this folder
5. Open the project and press **Run**

The main scene is configured in `project.godot`, so Godot should start `scenes/Game.tscn` automatically.

## What You Can Do

The main screen is split into a Tonnetz view and a control panel for L-system voices.

### L-System Voices

Each voice is one L-system. A voice contains:

- an axiom
- production rules
- an iteration count
- a generated string
- volume and mute controls
- a direction preview for playback

From the voice list you can:

- add a random L-system
- select a voice
- duplicate a voice
- randomize a voice
- delete a voice
- mute or solo voices
- change the axiom, rules, and iteration count
- rotate the initial playback direction
- inspect the generated string

The generated string uses this alphabet:

- `l`: turn left
- `r`: turn right
- `s`: step forward
- `1`: set note length to a full note
- `2`: set note length to a half note
- `4`: set note length to a quarter note
- `8`: set note length to an eighth note

### Playback

When a voice is played, the interpreter turns the generated string into a sequence of Tonnetz steps. The sequencer places those steps in musical time, and the turtle visualization draws the path through the grid.

Global controls let you adjust:

- BPM
- master volume
- mute state for all voices

### Walk Recording

The recording mode lets you draw a walk directly on the Tonnetz and then evolve a voice from it.

1. Press **Start Recording**
2. Click a starting node or triangle in the Tonnetz
3. Continue clicking highlighted neighbours to build the walk
4. Choose the duration for the next step with the selector
5. Use **Undo** to remove the last step if needed
6. Press **Generate** to evolve a voice from the recorded walk

The generated voice is added as a new L-system voice. You can generate again from the same recording if you want to compare different results.

### Import and Export

The program supports:

- exporting active voices as a MIDI file
- exporting a single voice as MIDI
- exporting L-system definitions as JSON
- importing L-system definitions from JSON

## Source Code Overview

The code is split into a few focused parts:

### Main Scene and Coordination

`scenes/Game.tscn` is the main scene. Its script, `scripts/game.gd`, ties the whole app together:

- loads the Tonnetz configuration
- builds the Tonnetz grid
- creates the initial random L-system
- connects UI signals to game logic
- manages the active L-system voices
- starts playback
- handles walk recording and generation
- imports and exports L-systems
- exports MIDI

### Tonnetz

The Tonnetz grid is built by `scripts/tonnetz_builder.gd`.

It creates:

- note nodes
- triangular areas between nodes
- neighbour relationships
- wrapped neighbor lookup at the Tonnetz edges
- visual grid lines

The visual nodes and triangle areas are implemented in:

- `scripts/tonnetz_node.gd`
- `scripts/tonnetz_triangle.gd`

The active Tonnetz layout and visual parameters are stored in:

- `config/tonnetz_config.gd`
- `config/config.tres`

### L-Systems

`scripts/l_system.gd` defines the `LSystem` data model. It stores the axiom, production rules, generated string, iteration count, color, and volume.

`scripts/l_system_factory.gd` creates random L-systems. It uses `LSystem.TERMINALS` as the source of truth for the alphabet.

The string expansion happens in:

```gdscript
LSystem.generate_string(axiom, rules, iterations)
```

### Interpretation and Playback

`scripts/interpreter.gd` converts an L-system string into musical Tonnetz events.

It interprets turns, steps, and note-length symbols, then returns an action list that can be played by the sequencer.

`scripts/sequencer.gd` schedules those events in beats. It manages active voices, loop timing, volume, pausing, stopping, and event signals.

`scripts/lsystem_list.gd` manages the editable L-system list, including selection, colors, mute and solo state, display numbers, fitness values, and preview directions.

`scripts/lsystem_runtime_helper.gd` connects interpretation, sequencing, and turtle visualization. It creates or updates turtles for voices and keeps generated paths extendable during exploration playback.

`scripts/lsystem_export.gd` handles JSON import and export for L-system definitions, colors, mute state, start anchors, initial directions, and normalized start times.

The turtle visualization itself is implemented in:

- `scripts/turtle.gd`
- `scenes/Turtle.tscn`

### Audio and MIDI

`scripts/audio_manager.gd` handles audio playback.

`scripts/midi_exporter.gd` writes active sequencer voices to standard MIDI files. It creates tempo information and one MIDI track per exported voice.

### User Interface

`scripts/ui.gd` builds and updates the user interface. It owns the controls, dialogs, voice list, start screen, Tonnetz viewport interaction, and emits signals for user actions.

`scripts/game.gd` receives those signals and applies the actual state changes.

### Walk Recording and Evolution

`scripts/walk_recorder.gd` records Tonnetz walks and turns them into target scores.

`scripts/recorded_walk_helper.gd` manages the recorded-walk workflow around that recorder.

The evolutionary algorithm lives in `scripts/evolution/`. It is modular, so selection, recombination, mutation, comparison, distance, fitness, and initial population strategies can be swapped independently.

Important files include:

- `scripts/evolution/evolution.gd`
- `scripts/evolution/individual.gd`
- `scripts/evolution/mutation.gd`
- `scripts/evolution/recombination.gd`
- `scripts/evolution/fitness/`
- `scripts/evolution/comparison/`
- `scripts/evolution/distance/`
- `scripts/evolution/initial_population/`

Experiment helpers and analysis scripts are in:

- `scripts/evolution/experiments/`
- `scripts/evaluation/`

`scripts/evolution/experiments/recorded_walk_experiment_helper.gd` handles command-line modes for target generation and recorded-walk experiment runs.
