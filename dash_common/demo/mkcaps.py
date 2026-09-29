#!/usr/bin/env python3
"""
Turn narration.txt into subtitles.

    mkcaps.py srt <narration> <fps> <frames> <offset_s>
    mkcaps.py ass <narration> <fps> <frames> <offset_s> <width> <height> <bar>

SubRip for muxing as a soft track. ASS for burning in, because libass scales
FontSize against the script resolution and a plain SubRip file declares none:
it then assumes 288 lines and a size meant as 26 px comes out nearer 100 on a
1080 line canvas. Declaring PlayResX/PlayResY equal to the real canvas makes
the size and margin plain pixels.

Each caption runs from its own start frame to the next one's, and the last runs
to the end. Times are shifted by the title card, which is concatenated in front.
"""
import sys


def entries(path):
    out = []
    for line in open(path):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        start, _still, _name, text = line.split(':', 3)
        out.append((int(start), text))
    if not out:
        raise SystemExit('%s: no captions' % path)
    return out


def spans(path, fps, total, offset):
    e = entries(path)
    for i, (start, text) in enumerate(e):
        end = e[i + 1][0] if i + 1 < len(e) else total
        yield offset + start / fps, offset + end / fps, text


def srt_time(s):
    ms = int(round(s * 1000))
    h, ms = divmod(ms, 3600000)
    m, ms = divmod(ms, 60000)
    sec, ms = divmod(ms, 1000)
    return '%02d:%02d:%02d,%03d' % (h, m, sec, ms)


def ass_time(s):
    cs = int(round(s * 100))
    h, cs = divmod(cs, 360000)
    m, cs = divmod(cs, 6000)
    sec, cs = divmod(cs, 100)
    return '%d:%02d:%02d.%02d' % (h, m, sec, cs)


def main():
    if len(sys.argv) < 6:
        raise SystemExit(__doc__)

    fmt, path = sys.argv[1], sys.argv[2]
    fps, total, offset = float(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5])
    got = list(spans(path, fps, total, offset))

    if fmt == 'srt':
        for i, (a, b, text) in enumerate(got):
            print('%d\n%s --> %s\n%s\n' % (i + 1, srt_time(a), srt_time(b), text))
        return

    if fmt != 'ass' or len(sys.argv) < 9:
        raise SystemExit(__doc__)

    w, h, bar = int(sys.argv[6]), int(sys.argv[7]), int(sys.argv[8])

    # Sized so two wrapped lines still sit inside the caption bar, and the
    # margin centres them in it.
    size = max(14, min(int(bar * 0.30), int(w / 34)))
    margin = max(4, int((bar - 2 * size * 1.25) / 2))

    print('[Script Info]')
    print('ScriptType: v4.00+')
    print('PlayResX: %d' % w)
    print('PlayResY: %d' % h)
    print('WrapStyle: 0')
    print('ScaledBorderAndShadow: yes')
    print()
    print('[V4+ Styles]')
    print('Format: Name, Fontname, Fontsize, PrimaryColour, OutlineColour, '
          'BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, '
          'Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, '
          'MarginL, MarginR, MarginV, Encoding')
    print('Style: Cap,DejaVu Sans,%d,&H00FBFCFB,&H00171B21,&H00171B21,'
          '0,0,0,0,100,100,0,0,1,2,0,2,%d,%d,%d,1'
          % (size, int(w * 0.04), int(w * 0.04), margin))
    print()
    print('[Events]')
    print('Format: Layer, Start, End, Style, Name, MarginL, MarginR, '
          'MarginV, Effect, Text')
    for a, b, text in got:
        print('Dialogue: 0,%s,%s,Cap,,0,0,0,,%s'
              % (ass_time(a), ass_time(b), text))


if __name__ == '__main__':
    main()
