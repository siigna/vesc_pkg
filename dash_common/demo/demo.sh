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
TITLE_SECS=${TITLE_SECS:-2}
TITLE=${TITLE:-VESC Pedal Assist}
SUBTITLE=${SUBTITLE:-torque sensing PAS, shown on the touch dash}
VIDEO=1
[ "${1:-}" = "--frames" ] && VIDEO=0

# libass resolves fonts through fontconfig; drawtext needs a file. Both come
# from whatever the shell provides, so fail early rather than silently
# rendering a video with no text on it.
FONT=${FONT:-$(fc-match -f '%{file}' 'DejaVu Sans' 2>/dev/null)}

if [ ! -x "$REPL" ]; then
    echo "no repl at $REPL -- see ../test/README.md, or set REPL=" >&2
    exit 1
fi

if [ "$VIDEO" = 1 ] && [ ! -f "${FONT:-}" ]; then
    echo "no usable font: install DejaVu Sans or set FONT= to a .ttf" >&2
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

        # Panel geometry, so the caption bar and the title card match whatever
        # the board profile rendered.
        # Queried one at a time: the csv writer's separator option is not
        # accepted by every ffprobe build, and when it is rejected the sizes
        # come back empty and the canvas silently becomes 0 wide.
        pw=$(ffprobe -v error -select_streams v:0 -show_entries stream=width \
             -of default=nw=1:nk=1 "out/${board}_0000.png")
        ph=$(ffprobe -v error -select_streams v:0 -show_entries stream=height \
             -of default=nw=1:nk=1 "out/${board}_0000.png")
        case "$pw$ph" in
            ''|*[!0-9]*)
                echo "  could not read the panel size from the frames" >&2
                rc=1
                continue
                ;;
        esac
        cw=$((pw * 2))
        ch=$((ph * 2))
        bar=120
        th=$((ch + bar))

        # SubRip for the soft track, ASS for burning in. See mkcaps.py for
        # why the burned-in one cannot be the SubRip file.
        srt="out/${board}.srt"
        ass="out/${board}.ass"
        python3 mkcaps.py srt narration.txt "$FPS" "$n" "$TITLE_SECS" > "$srt"
        python3 mkcaps.py ass narration.txt "$FPS" "$n" "$TITLE_SECS" \
            "$cw" "$th" "$bar" > "$ass"

        # Plain panel, with the narration as a soft subtitle track. Nothing is
        # burned in, so it embeds cleanly and the text can be turned off.
        ffmpeg -y -loglevel error -framerate "$FPS" -i "out/${board}_%04d.png" \
            -i "$srt" -c:v libx264 -pix_fmt yuv420p -crf 18 \
            -c:s mov_text -metadata:s:s:0 language=eng \
            "out/dash_${board}.mp4" || rc=1

        # A title card at the panel's aspect, concatenated in front.
        #
        # The text goes through textfile= rather than text=, because a caption
        # containing a comma or a colon is otherwise parsed as filtergraph
        # punctuation and the whole command fails.
        printf '%s' "$TITLE"    > "out/${board}_t1.txt"
        printf '%s' "$SUBTITLE" > "out/${board}_t2.txt"

        # Sized to fit rather than to a fixed fraction of the canvas: the
        # default subtitle at one twenty-second of the height ran off both ends
        # of a 960 px card. DejaVu Sans averages about 0.55 em per character,
        # which is close enough to keep a line inside 90% of the width.
        fitsize() {
            awk -v n="${#1}" -v w="$2" -v cap="$3" \
                'BEGIN { s = (w * 0.9) / (n * 0.55); if (s > cap) s = cap;
                         printf "%d", (s < 8 ? 8 : s) }'
        }
        t1s=$(fitsize "$TITLE" "$cw" $((ch / 12)))
        t2s=$(fitsize "$SUBTITLE" "$cw" $((ch / 22)))
        ffmpeg -y -loglevel error -f lavfi \
            -i "color=c=0x0d1117:s=${cw}x${th}:d=${TITLE_SECS}:r=${FPS}" \
            -vf "drawtext=fontfile=${FONT}:textfile=out/${board}_t1.txt:fontcolor=0xfbfcfc:fontsize=${t1s}:x=(w-tw)/2:y=(h-th)/2-$((ch / 14)),drawtext=fontfile=${FONT}:textfile=out/${board}_t2.txt:fontcolor=0x58a6ff:fontsize=${t2s}:x=(w-tw)/2:y=(h-th)/2+$((ch / 14))" \
            -c:v libx264 -pix_fmt yuv420p -crf 18 "out/${board}_title.mp4" || rc=1
        rm -f "out/${board}_t1.txt" "out/${board}_t2.txt"

        # The demo cut: panel scaled up on a canvas with a bar underneath, so
        # the narration sits below the dash instead of over it.
        ffmpeg -y -loglevel error -framerate "$FPS" -i "out/${board}_%04d.png" \
            -vf "scale=${cw}:${ch}:flags=neighbor,\
pad=${cw}:${th}:0:0:0x0d1117,ass=${ass}" \
            -c:v libx264 -pix_fmt yuv420p -crf 18 "out/${board}_body.mp4" || rc=1

        printf "file '%s'\nfile '%s'\n" "${board}_title.mp4" "${board}_body.mp4" \
            > "out/${board}_cat.txt"
        ffmpeg -y -loglevel error -f concat -safe 0 -i "out/${board}_cat.txt" \
            -c copy "out/dash_${board}_demo.mp4" || rc=1

        # The gif carries the captions burned in, since a gif has no subtitle
        # track. Half scale to keep it a sane size.
        ffmpeg -y -loglevel error -i "out/dash_${board}_demo.mp4" \
            -vf "fps=${FPS},scale=${cw}/2:-1:flags=lanczos,palettegen=stats_mode=diff" \
            "out/${board}_pal.png" || rc=1
        ffmpeg -y -loglevel error -i "out/dash_${board}_demo.mp4" \
            -i "out/${board}_pal.png" \
            -lavfi "fps=${FPS},scale=${cw}/2:-1:flags=lanczos[v];[v][1:v]paletteuse=dither=bayer:bayer_scale=3" \
            "out/dash_${board}.gif" || rc=1

        rm -f "out/${board}_pal.png" "out/${board}_title.mp4" \
              "out/${board}_body.mp4" "out/${board}_cat.txt"

        echo "  plain $(stat -c%s out/dash_${board}.mp4) B," \
             "demo $(stat -c%s out/dash_${board}_demo.mp4) B," \
             "gif $(stat -c%s out/dash_${board}.gif) B"
    fi
done

# Stills, named from narration.txt so the two cannot drift apart.
if [ "$VIDEO" = 1 ]; then
    mkdir -p stills
    while IFS=: read -r start still name text; do
        case "$start" in ''|\#*) continue;; esac
        for board in s3 p4; do
            f=$(printf '%04d' "$still")
            [ -f "out/${board}_${f}.png" ] && \
                cp "out/${board}_${f}.png" "stills/${board}_${name}.png"
        done
    done < narration.txt
    echo "stills in stills/, video and frames in out/"
fi

exit $rc
