#!/bin/sh
# Glasshouse Home look: tile styles for the Apps row (Lens, Orbit, Tilted
# Tiles, chosen on the dashboard beside Glasshouse Home), clock and weather
# layout, idle hiding, live tiles and own icons.
#   sh lg-tiles.sh          install (or again, after a Glasshouse update)
#   sh lg-tiles.sh lens     the same, with Lens as the style until one is
#                           chosen on the dashboard (also orbit, tilted)
#   sh lg-tiles.sh remove   take it all out
# Keep lg-common.html, lg-dash.html and the lg-style-*.html files beside this script.
F=${GH_HOME_HTML:-/var/lib/tvweb/assets/home.html}
UI=${GH_UI_HTML:-$(dirname "$F")/ui.html}
HERE=$(cd "$(dirname "$0")" && pwd)
VERSION=2026-11-20c

STYLE=$1
if [ "$STYLE" != remove ]; then
  [ -n "$STYLE" ] || STYLE=$(cat "$HERE/.style" 2>/dev/null)
  [ -n "$STYLE" ] || STYLE=lens
  [ -f "$HERE/lg-style-$STYLE.html" ] || { echo "No style called $STYLE (try: lens, orbit, tilted)"; exit 1; }
  for f in lg-common.html lg-dash.html lg-style-lens.html lg-style-orbit.html lg-style-tilted.html; do
    [ -f "$HERE/$f" ] || { echo "Missing $HERE/$f"; exit 1; }
  done
  SNIP=/tmp/lg-tiles.$$.html
  {
    echo '<!-- lg-tiles:start -->'
    echo "<!-- lg-tiles-version:$VERSION -->"
    echo "<script>window.LG_TILES_VER = '$VERSION'; window.LG_TILES_DEFAULT = '$STYLE';</script>"
    cat "$HERE/lg-common.html" "$HERE/lg-style-lens.html" "$HERE/lg-style-orbit.html" "$HERE/lg-style-tilted.html"
    echo '<!-- lg-tiles:end -->'
  } > "$SNIP"
  DSNIP=/tmp/lg-dash.$$.html
  {
    echo '<!-- lg-tiles:start -->'
    echo "<script>window.LG_TILES_DEFAULT = '$STYLE';</script>"
    cat "$HERE/lg-dash.html"
    echo '<!-- lg-tiles:end -->'
  } > "$DSNIP"
fi

# patch FILE SNIPPET: our block taken out, and put back in before </body>
patch() {
  [ -f "$1" ] || return 1
  [ -f "$1.before-lg-tiles" ] || cp "$1" "$1.before-lg-tiles"
  sed '/<!-- lg-tiles:start -->/,/<!-- lg-tiles:end -->/d' "$1" > "$1.tmp" || return 1
  if [ -n "$2" ]; then
    awk -v snip="$2" '/<\/body>/ && !done { while ((getline l < snip) > 0) print l; done = 1 } { print }' "$1.tmp" > "$1.new" || return 1
    grep -q 'lg-tiles:end' "$1.new" || { echo "Could not find </body> in $1; left as it was"; rm -f "$1.tmp" "$1.new"; return 1; }
    mv "$1.new" "$1.tmp"
  fi
  cat "$1.tmp" > "$1" && rm -f "$1.tmp"
}

[ -f "$F" ] || { echo "Glasshouse Home not found at $F"; exit 1; }
if [ "$STYLE" = remove ]; then
  patch "$F" ""; patch "$UI" ""
else
  patch "$F" "$SNIP" || exit 1
  patch "$UI" "$DSNIP" || echo "The dashboard was left as it was: the styles can still be chosen with this script."
  rm -f "$SNIP" "$DSNIP"
  [ -z "$GH_HOME_HTML" ] && echo "$STYLE" > "$HERE/.style"
fi

# Own app icons: PNGs in the icons folder beside this script (youtube.png),
# served to Glasshouse Home from its assets folder.
ASSETS=$(dirname "$F")
rm -rf "$ASSETS/lg-icons"
if [ "$STYLE" != "remove" ] && [ -d "$HERE/icons" ]; then
  mkdir -p "$ASSETS/lg-icons" && cp "$HERE"/icons/*.png "$ASSETS/lg-icons/" 2>/dev/null
fi

# The server keeps home.html in memory, so restart it to serve the new copy.
/var/lib/tvweb/tvwebctl restart >/dev/null 2>&1
# Close Glasshouse Home's page if it is open, so the next Home press loads
# the new copy rather than bringing the old one back to the front.
sleep 2
for app in com.tvweb.home com.webos.app.home; do
  luna-send -n 1 luna://com.palm.webappmanager/killApp "{\"appId\":\"$app\"}" >/dev/null 2>&1
done
echo "Done ($([ "$STYLE" = remove ] && echo removed || echo installed)). Choose Lens, Orbit or Tilted Tiles under Home on the dashboard, then press Home on the remote."
