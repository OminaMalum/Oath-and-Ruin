q(){ python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$1"; }
for t in "$@"; do echo "== STEAM $t"; curl -s --max-time 20 "https://store.steampowered.com/search/suggest?term=$(q "$t")&f=games&cc=US&l=english" | grep -o 'match_name[^>]*>[^<]*' | sed 's/.*>//' | head -6
echo "-- ITCH $t"; curl -s --max-time 20 -A "Mozilla/5.0" "https://itch.io/search?q=$(q "$t")" | grep -o 'class="title game_link"[^>]*>[^<]*' | sed 's/.*>//' | head -6; done
