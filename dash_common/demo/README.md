# Dash demo renders

Renders a scripted ride on the s3 and p4 dashes to a frame sequence, then
stitches it into an mp4 and a gif. For screenshots and demo video, off target.

    ./demo.sh              frames, mp4 and gif for both boards, plus stills
    ./demo.sh --frames     frames only
    FPS=15 ./demo.sh       different frame rate

Needs the same LispBM repl as `../test/run.sh` — see `../test/README.md` — and
ffmpeg for the video. Set `REPL=` if it is not at the default path.

**This is not a test.** Nothing here is compared against a golden and nothing
is asserted. `../test/` is the regression suite; this is for showing the thing
working. It does share the const-stripping and font substitution, because the
repl needs both either way.

## What the ride does

The frame index drives a set of phases, and the numbers are computed from each
other rather than being independent, so the screen stays self-consistent: rider
power comes from torque times cadence, assist from rider power times a gain,
battery current from assist power and pack voltage.

| frames | what |
|---|---|
| 0–30 | pulling away from a standstill, cadence then torque then assist |
| 30–60 | up to speed, steady, assist about twice the rider's effort |
| 60–80 | into the speed taper: the rider keeps working, assist is pulled back, `splim` |
| 80–95 | brake, assist cut at once, speed falling, `brake` |
| 95–110 | stopped, walk assist nudging along at walking pace, `walk` |
| 110–180 | the other pages: trip, session, battery, live |

Stills are copied out of the sequence into `stills/`, one per phase, which is
what to use for screenshots.

## What it is good for beyond looking nice

A still cannot show a transition, and the PAS page is mostly about transitions —
assist tracking the rider, then being taken away by the taper or the brake. It
also catches layout problems the golden tests do not, because the goldens only
ever render one state: the first run of this showed the speed limited status
reading `sp lim` on the p4, because the four column layout gives the value
column less room than the two column one and the string was cut mid-word. The
status words are five characters for that reason.
