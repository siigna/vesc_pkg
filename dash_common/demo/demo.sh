#!/usr/bin/env bash
# Render a scripted ride on each dash and stitch it into a video.
#
#   ./demo.sh            render frames, then mp4 and gif for each board
#   ./demo.sh --frames   frames only, no video
#
# Needs the same LispBM repl as ../test/run.sh, and ffmpeg for the video.
# This is a demo, not a test: nothing here is asserted against a golden.
set -uo pipefail
cd "$(dirname "$0")"

REPL=${REPL:-../../../vesc_express/main/lispBM/repl/repl}
FPS=${FPS:-10}
VIDEO=1
[ "${1:-}" = "--frames" ] && VIDEO=0

if [ ! -x "$REPL" ]; then
    echo "no repl at $REPL -- see ../test/README.md, or set REPL=" >&2
    exit 1
fi

# board : package dir : speed : big : mid : small
BOARDS=(
  "s3:../../dash_s3:roboto-bold-108-4c.bin:roboto-bold-40-4c.bin:roboto-bold-24-4c.bin:roboto-bold-16-4c.bin"
  "p4:../../dash_p4:roboto-bold-120-4c.bin:roboto-bold-40-4c.bin:roboto-bold-24-4c.bin:roboto-bold-18-4c.bin"
)

rm -rf build out
mkdir -p build/common/lib build/common/views out

# The repl's const heap is small and write-once, so a whole dash overflows it.
strip_const() { grep -v '^@const-\(start\|end\)' "$1" > "$2"; }

for f in ../lib/*.lisp;  do strip_const "$f" "build/common/lib/$(basename "$f")"; done
for f in ../views/*.lbm; do strip_const "$f" "build/common/views/$(basename "$f")"; done

rc=0

for spec in "${BOARDS[@]}"; do
    IFS=: read -r board pkg fspeed fbig fmid fsmall <<< "$spec"

    mkdir -p "build/$board/lib" "build/$board/font"
    strip_const "$pkg/config.lisp"    "build/$board/config.lisp"
    strip_const "$pkg/lib/input.lisp" "build/$board/lib/input.lisp"
    cp "$pkg"/font/*.bin "build/$board/font/"

    sed -e "s/BOARD/$board/g" \
        -e "s/F_SPEED/$fspeed/" -e "s/F_BIG/$fbig/" \
        -e "s/F_MID/$fmid/"     -e "s/F_SMALL/$fsmall/" \
        demo.lisp > "build/$board/demo.lisp"

    echo "rendering $board ..."
    out=$("$REPL" -H 400000 -M 8000000 --terminate --silent \
            -s "build/$board/demo.lisp" 2>&1)
    echo "$out" | grep -E "^\(|Error" | sed 's/^/  /'
    if echo "$out" | grep -q "Error"; then rc=1; continue; fi

    n=$(ls out/${board}_[0-9]*.png 2>/dev/null | wc -l)
    if [ "$n" -eq 0 ]; then
        echo "  no frames produced" >&2
        rc=1
        continue
    fi
    echo "  $n frames"

    if [ "$VIDEO" = 1 ]; then
        if ! command -v ffmpeg >/dev/null; then
            echo "  ffmpeg not found, skipping video (frames are in out/)" >&2
            continue
        fi
        # yuv420p and the scale filter keep it playable everywhere; the panels
        # are even-sized already but a filter guards against an odd one.
        ffmpeg -y -loglevel error -framerate "$FPS" \
            -i "out/${board}_%04d.png" \
            -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" \
            -c:v libx264 -pix_fmt yuv420p -crf 18 \
            "out/dash_${board}.mp4" || rc=1

        # Two-pass palette, since a flat dark UI banded badly on a single pass.
        ffmpeg -y -loglevel error -framerate "$FPS" -i "out/${board}_%04d.png" \
            -vf "palettegen=stats_mode=diff" "out/${board}_pal.png" || rc=1
        ffmpeg -y -loglevel error -framerate "$FPS" -i "out/${board}_%04d.png" \
            -i "out/${board}_pal.png" \
            -lavfi "paletteuse=dither=bayer:bayer_scale=3" \
            "out/dash_${board}.gif" || rc=1
        rm -f "out/${board}_pal.png"

        echo "  $(ls -la out/dash_${board}.mp4 | awk '{print $5}') bytes mp4," \
             "$(ls -la out/dash_${board}.gif | awk '{print $5}') bytes gif"
    fi
done

# A few stills worth keeping, picked from the phases the script walks through.
if [ "$VIDEO" = 1 ]; then
    mkdir -p stills
    for board in s3 p4; do
        for spec in "0020:pulling-away" "0050:steady-assist" "0072:speed-taper" \
                    "0088:braking" "0102:walk-assist" "0118:regen" \
                    "0130:fan" "0138:kill-switch" "0150:trip" \
                    "0168:session" "0186:battery" "0202:live"; do
            IFS=: read -r frame name <<< "$spec"
            [ -f "out/${board}_${frame}.png" ] && \
                cp "out/${board}_${frame}.png" "stills/${board}_${name}.png"
        done
    done
    echo "stills in stills/, video and frames in out/"
fi

exit $rc
