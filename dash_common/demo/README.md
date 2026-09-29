# Dash demo renders

Renders a scripted ride on the s3 and p4 dashes to a frame sequence, then
stitches it into an mp4 and a gif. For screenshots and demo video, off target.

    ./demo.sh              frames, video and stills for both boards
    ./demo.sh --frames     frames only, no video
    FPS=15 ./demo.sh       different frame rate
    TITLE="..." SUBTITLE="..." ./demo.sh    retitle the card

Needs the same LispBM repl as `../test/run.sh` — see `../test/README.md` — plus
ffmpeg built with libass and libfreetype, and a DejaVu Sans to render with.
`nix-shell -p ffmpeg dejavu_fonts fontconfig` covers it. Set `REPL=` if the repl
is not at the default path, or `FONT=` to point at another `.ttf`.

## What comes out

| file | what |
|---|---|
| `out/dash_<board>.mp4` | the panel alone, narration as a **soft subtitle track** |
| `out/dash_<board>_demo.mp4` | title card, panel at 2x, narration burned into a bar below it |
| `out/dash_<board>.gif` | the demo cut at half size, captions burned in |
| `stills/<board>_<phase>.png` | one still per phase |

The plain mp4 is the one to embed somewhere that has its own captions or where
the text would be in the way; the subtitle track can simply be turned off. The
demo cut is the one to hand someone.

**`out/` is not in git** -- only `stills/` is. The videos are a few megabytes
of fully reproducible binary, so they are built rather than stored. Two things
follow: `demo.sh` starts with `rm -rf build out`, and `--frames` stops before
the video step, so **a `--frames` run deletes whatever videos were there and
does not put them back**. Run it without arguments when you want the video.

Captions never overlay the dash. The panel is scaled up and a bar is padded on
underneath, and the narration sits in the bar.

## Narration

`narration.txt` is the single source for the captions **and** the still names,
so the two cannot drift apart:

    start_frame : still_frame : still_name : text

A caption runs until the next entry starts. The frame numbers are the phase
boundaries in `demo.lisp`, so changing a phase there means changing it here.

`mkcaps.py` renders that to SubRip for the soft track and to ASS for burning in.
It has to be ASS for the burn: libass scales `FontSize` against the script
resolution, and a SubRip file declares none, so it assumes 288 lines and a size
meant as 26 px comes out nearer 100 on a 1080 line canvas. The ASS file declares
`PlayResX`/`PlayResY` equal to the real canvas, which makes the size and margin
plain pixels.

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
| 110–125 | rolling again, coasting, regen into the pack |
| 125–142 | the cooling fan, then the kill switch, which outranks everything |
| 142–178 | the rolling chart, then the controller settings page |
| 178–246 | trip, session, battery, live |
| 246–266 | the cells page, with one cell 0.3 V down |
| 266–286 | the quick shade, with the mode and cruise changing under it |
| 286–296 | hazard and high beam taken from the request rather than a report |
| 296–316 | holding a live cell, then the chart it opens on that cell |
| 316–340 | the Night and Light themes |
| 340–356 | a colour rule per live cell |

Stills are copied out of the sequence into `stills/`, one per phase, which is
what to use for screenshots.

The signal beat is on a page rather than under the shade on purpose: the shade
covers the status strip, so the arrows it is demonstrating would not be on
screen. And `sig-reported` is pinned true for the ride and flipped false only
for that beat, because the strip shows what a bike-controls node reports when
there is one and falls back to the request when there is not -- both halves are
worth seeing.

## What it is good for beyond looking nice

A still cannot show a transition, and the PAS page is mostly about transitions —
assist tracking the rider, then being taken away by the taper or the brake. It
also catches layout problems the golden tests do not, because the goldens only
ever render one state: the first run of this showed the speed limited status
reading `sp lim` on the p4, because the four column layout gives the value
column less room than the two column one and the string was cut mid-word. The
status words are five characters for that reason.

It has now caught two more, both of which the goldens could not:

- The signal request change made the strip fall back to the request when
  nothing reports, and **the demo's indicator beat silently went blank** --
  `indicate-l-on` was still being set, but nothing read it any more. The
  goldens did not catch it because the test harness pins `sig-reported`; the
  demo did not pin it and so showed the truth.
- The frame loop did not honour `view-force-pages`, which `view-static-frame`
  raises after wiping the screen. Leaving the quick shade or changing theme
  therefore left the page with its labels erased and only its changed values
  redrawn. The real `view-pages-thread` has always honoured that flag, so this
  was the demo drifting from the shipping path rather than a dash bug -- but it
  is exactly the kind of drift that makes a demo lie.
