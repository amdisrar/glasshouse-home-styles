#!/bin/sh
# Bing's photo of the day into Glasshouse Home's shuffled wallpapers.
#
#   sh bing-wall.sh          fetch once now (up to the last 16 days on a first run)
#   sh bing-wall.sh loop     keep fetching: every 6 hours, or 10 minutes after a failure
#   sh bing-wall.sh install  start at every boot (Homebrew Channel boot hook) and now
#   sh bing-wall.sh remove   stop, drop the boot hook and delete the Bing pictures
#
# Only files named bing<date>.jpg are touched; pictures uploaded on the
# dashboard are left alone. The newest KEEP are kept.

DIR=/var/lib/tvweb/home-wallpaper-shuffle
KEEP=30
MKT=en-US
HOOK=/var/lib/webosbrew/init.d/60-bingwall
PIDF=/tmp/bingwall.pid
LOG=/tmp/bingwall.log
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
export PATH="/bin:/sbin:/usr/bin:/usr/sbin:$PATH"

CURL=
for c in /media/developer/bin/curl /usr/local/bin/curl /opt/bin/curl /usr/bin/curl /bin/curl; do
  [ -x "$c" ] && { CURL=$c; break; }
done

get() {   # url file: certificate checks stay on
  "$CURL" -fsSL --max-time 60 -o "$2" "$1"
}

fetch() {
  [ -n "$CURL" ] || { echo "no curl on this TV"; return 1; }
  mkdir -p "$DIR" || return 1
  got=0 fail=0
  for idx in 0 8; do
    json=/tmp/bingwall.$$.json
    if ! get "https://www.bing.com/HPImageArchive.aspx?format=js&idx=$idx&n=8&mkt=$MKT" "$json"; then
      fail=1; rm -f "$json"; continue
    fi
    # One picture a line: its date and its address without the size.
    tr '{' '\n' < "$json" | sed -n 's/.*"startdate":"\([0-9]\{8\}\)".*"urlbase":"\(\/th?id=[A-Za-z0-9._-]*\)".*/\1 \2/p' > "$json.list"
    while read -r day base; do
      f="$DIR/bing$day.jpg"
      [ -s "$f" ] && continue
      if get "https://www.bing.com${base}_1920x1080.jpg" "$f.part" && [ "$(wc -c < "$f.part")" -gt 40000 ]; then
        mv -f "$f.part" "$f"; got=$((got + 1))
      else
        rm -f "$f.part"; fail=1
      fi
    done < "$json.list"
    rm -f "$json" "$json.list"
    # The second page only matters on a first run.
    [ "$(ls "$DIR"/bing*.jpg 2>/dev/null | wc -l)" -ge 9 ] && break
  done
  # Keep the newest KEEP.
  ls "$DIR"/bing*.jpg 2>/dev/null | sort -r | tail -n +$((KEEP + 1)) | while read -r old; do rm -f "$old"; done
  echo "$(date) added $got, now $(ls "$DIR"/bing*.jpg 2>/dev/null | wc -l) Bing pictures"
  [ "$fail" = 0 ] || [ "$got" -gt 0 ]
}

running() { [ -f "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; }

case "$1" in
  loop)
    running && exit 0
    echo $$ > "$PIDF"
    while :; do
      if fetch >> "$LOG" 2>&1; then sleep 21600; else sleep 600; fi
      [ "$(wc -c < "$LOG")" -gt 20000 ] && : > "$LOG"
    done ;;
  install)
    mkdir -p "$(dirname "$HOOK")"
    printf '#!/bin/sh\n# Bing wallpapers for Glasshouse Home\n[ -f "%s" ] && (sleep 60; sh "%s" loop) >/dev/null 2>&1 &\nexit 0\n' "$SELF" "$SELF" > "$HOOK"
    chmod +x "$HOOK"
    fetch
    running || { nohup sh "$SELF" loop >/dev/null 2>&1 & }
    echo "Installed: Bing pictures are fetched now, every 6 hours, and after every restart." ;;
  remove)
    running && kill "$(cat "$PIDF")" 2>/dev/null
    rm -f "$HOOK" "$PIDF" "$DIR"/bing*.jpg
    echo "Removed." ;;
  *)
    fetch ;;
esac
