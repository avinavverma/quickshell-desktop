#!/usr/bin/env bash
# Print synced (LRC) lyrics for a song, or nothing.
#   lyrics-fetch.sh <artist> <title> <album> <duration-seconds or 0> <cache-file>
#
# Every way of looking the song up is started AT THE SAME TIME, then the answers are taken in
# priority order as soon as the higher ones are known:
#   1. LyricsPlus server, with the player's full artist/title  (the server tries apple, lyricsplus,
#      musixmatch, spotify, musixmatch-word, in that order)
#   2. LyricsPlus server, with the main artist + title without brackets (only if that differs)
#   3. LRCLIB exact lookup with the album
#   4. LRCLIB exact lookup without the album (the player's album often isn't LRCLIB's edition name)
#   5. LRCLIB searches (four different queries, merged; synced + about the right length; exact title
#      match first, then matching main artist)
# Times are used exactly as the sources give them.
# Cache: lyrics are kept for good; "NONE" (every request clearly said "not found") for 6 hours.
# Exit code 3 = a request failed (timeout / server error): nothing cached, the caller may retry.
artist=$1 title=$2 album=$3 dur=${4:-0} cache=$5
UA="taskbar-lyrics (personal desktop widget)"
mkdir -p "$(dirname "$cache")"
if [[ -s "$cache" ]]; then
  if [[ "$(head -c4 "$cache")" != "NONE" ]]; then cat "$cache"; exit 0; fi
  [[ -n "$(find "$cache" -mmin -360 2>/dev/null)" ]] && exit 0       # recent "not found"
fi
tmp=$(mktemp -d); trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$tmp"' EXIT
main=$(sed -E 's/\s*(,|;|\sand\s|\s&\s|\sx\s|\sfeat\.?\s|\sft\.?\s|\sfeaturing\s|\swith\s).*$//I' <<< "$artist")
ttl=$(sed -E 's/\s*[\(\[\{].*$//' <<< "$title")
[[ -n "$ttl" ]] || ttl=$title

# http <outfile> <url> [curl args...]  -> prints the HTTP status (000 on timeout / no connection)
http() { local out=$1 url=$2; shift 2; curl -sS --max-time "${HTTP_TIMEOUT:-12}" -A "$UA" -G -o "$out" -w '%{http_code}' "$@" "$url" 2>/dev/null || true; }

# lyricsplus <name> <artist> <title>  -> $tmp/<name>.lrc (empty if none), $tmp/<name>.st
lyricsplus() {
  local n=$1 st
  st=$(HTTP_TIMEOUT=6 http "$tmp/$n.json" "https://lyricsplus.binimum.org/v2/lyrics/get" \
       --data-urlencode "title=$3" --data-urlencode "artist=$2" --data-urlencode "duration=$dur" \
       --data-urlencode "source=apple,lyricsplus,musixmatch,spotify,musixmatch-word")
  echo "$st" > "$tmp/$n.st"
  [[ "$st" == 200 ]] && jq -r '.lyrics[]? | select(.text != null)
         | ((.time // (.syllabus[0]?.time) // ((.syllabus[0]?.startTime // null) | if . == null then null else . * 1000 end))) as $t
         | select($t != null) | "\($t | floor)\t\(.text | gsub("[\\t\\n]"; " "))"' "$tmp/$n.json" 2>/dev/null |
  sort -n -s -t$'\t' -k1,1 |
  awk -F'\t' '{ ms=$1; m=int(ms/60000); s=(ms-m*60000)/1000; printf "[%02d:%05.2f] %s\n", m, s, $2 }' > "$tmp/$n.lrc"
}
# lrget <name> <with-album 0|1>
lrget() {
  local n=$1 st a=(--data-urlencode "artist_name=$artist" --data-urlencode "track_name=$title")
  (( dur > 0 )) && a+=(--data-urlencode "duration=$dur")
  if [[ "$2" == 1 ]]; then
    [[ -n "$album" ]] || { echo 404 > "$tmp/$n.st"; return; }
    a+=(--data-urlencode "album_name=$album")
  fi
  st=$(http "$tmp/$n.json" "https://lrclib.net/api/get" "${a[@]}")
  echo "$st" > "$tmp/$n.st"
  [[ "$st" == 200 ]] && jq -r '.syncedLyrics // empty' "$tmp/$n.json" > "$tmp/$n.lrc" 2>/dev/null
}
# lrsearch: four queries at once, merged and ranked
lrsearch() {
  local i
  http "$tmp/s1.json" "https://lrclib.net/api/search" --data-urlencode "q=$artist $title" > "$tmp/s1.st" &
  http "$tmp/s2.json" "https://lrclib.net/api/search" --data-urlencode "q=$main $title" > "$tmp/s2.st" &
  http "$tmp/s3.json" "https://lrclib.net/api/search" --data-urlencode "track_name=$title" --data-urlencode "artist_name=$main" > "$tmp/s3.st" &
  http "$tmp/s4.json" "https://lrclib.net/api/search" --data-urlencode "q=$main $ttl" > "$tmp/s4.st" &
  wait
  local bad=200
  for i in 1 2 3 4; do local c; c=$(cat "$tmp/s$i.st" 2>/dev/null); [[ "$c" == 200 || "$c" == 404 ]] || bad=$c; done
  echo "$bad" > "$tmp/search.st"
  for i in 1 2 3 4; do [[ "$(cat "$tmp/s$i.st")" == 200 ]] && cat "$tmp/s$i.json"; done | jq -rs --argjson d "$dur" --arg t "$title" --arg m "$main" '
      add // [] | map(select(.syncedLyrics != null and .syncedLyrics != ""))
      | map(select($d == 0 or ((.duration - $d) | fabs) <= 4))
      | map(. + {score: ((if (.trackName | ascii_downcase) == ($t | ascii_downcase) then 2 else 0 end)
                       + (if ($m != "" and ((.artistName // "") | ascii_downcase | contains($m | ascii_downcase))) then 1 else 0 end))})
      | sort_by(-.score) | .[0].syncedLyrics // empty' > "$tmp/search.lrc" 2>/dev/null
}

lyricsplus lp1 "$artist" "$title" & pid_lp1=$!
if [[ "$main" != "$artist" || "$ttl" != "$title" ]]; then lyricsplus lp2 "$main" "$ttl" & pid_lp2=$!; fi
lrget get1 1 & pid_g1=$!
lrget get0 0 & pid_g0=$!
lrsearch & pid_s=$!

found() { grep -q '^\[' "$tmp/$1.lrc" 2>/dev/null; }
emit() { { echo "# source: $2"; cat "$tmp/$1.lrc"; } | tee "$cache"; exit 0; }

wait $pid_lp1;           found lp1 && emit lp1 lyricsplus
[[ -n "$pid_lp2" ]] && { wait $pid_lp2; found lp2 && emit lp2 "lyricsplus (main artist)"; }
wait $pid_g1;            found get1 && emit get1 "lrclib (with album)"
wait $pid_g0;            found get0 && emit get0 lrclib
wait $pid_s;             found search && emit search "lrclib (search)"

# Nothing found. Only remember that if every request got a clear answer (200 / 404).
definitive=1
for s in $(cat "$tmp"/lp1.st "$tmp"/lp2.st "$tmp"/get1.st "$tmp"/get0.st "$tmp"/search.st 2>/dev/null); do
  [[ "$s" == 200 || "$s" == 404 ]] || definitive=0
done
if (( definitive )); then printf 'NONE' > "$cache"; exit 0; fi
exit 3
