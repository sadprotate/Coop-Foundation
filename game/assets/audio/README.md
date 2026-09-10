These music and sound assets were composed and synthesized for Co-op Foundation.
They contain no external samples or recordings. They are covered by this project's
MIT license. `build_audio.py` reproduces every WAV using Python's standard library.

- `menu.wav`: a gentle original eight-bar plucked melody and warm chords, 96 BPM.
- `arena.wav`: a related eight-bar melody with bass, kick, snare and hi-hats, 120 BPM.
- Effects: menu click/confirmation, jump, landing, swing, impact, guard, defeat and respawn.

Music wraps note tails across each loop boundary for uninterrupted looping. The
game crossfades between menu and arena tracks, preserves arena music when opening
settings, and uses independent voices for overlapping sound effects. Master, Music
and Effects buses respect the player's saved levels, including complete mute.
