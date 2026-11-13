#!/usr/bin/env bash
# Part of verify_sprint2.sh (T115, T113), piped to bash on the lab host as bot; workstation mode only.
# Signs in as the sv-dev verify seller through the BFF login form, like a browser (Ticket 2.1
# decision), and checks selling end to end: a renamed .txt and an 11 MB image are refused, a
# draft with two photos publishes and shows in search within SEARCH_WITHIN seconds, then it is
# deleted. The password is read from Secret verify-seller here and never leaves the lab host:
# it is not printed and not put on a command line.
# macOS bash 3.2: nothing newer than that.
set -euo pipefail
export PATH=/opt/homebrew/bin:/usr/local/bin:$PATH
SEARCH_WITHIN="${SEARCH_WITHIN:-5}"
SITE=https://dev.sortedvtg.lan:8443

pass() { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; exit 1; }

W="$(mktemp -d)"
JAR="$W/jar"
LISTING=""
CSRF=""
cleanup() {
  # A failed run still removes its listing, so the verify seller never keeps test items.
  if [[ -n "$LISTING" ]]; then
    curl_ -o /dev/null -D "$W/h" -d "csrf_token=$CSRF" "$SITE/sell/listings/$LISTING/delete" || true
  fi
  rm -rf "$W"
}
trap cleanup EXIT

CA="$(mkcert -CAROOT)/rootCA.pem"
curl_() {
  curl -sS --cacert "$CA" -b "$JAR" -c "$JAR" \
    --connect-to dev.sortedvtg.lan:8443:127.0.0.1:443 \
    --connect-to auth.sortedvtg.lan:8443:127.0.0.1:443 "$@"
}
location() { awk 'tolower($1) == "location:" { print $2 }' "$W/h" | tr -d '\r' | tail -1; }
now() { python3 -c 'import time; print(time.time())'; }
k() { kubectl --context kind-sorted-vintage -n sv-dev "$@"; }

# Credentials into files, so curl reads them with @file and they appear in no process list.
k get secret verify-seller -o jsonpath='{.data.username}' | base64 -d > "$W/user"
k get secret verify-seller -o jsonpath='{.data.password}' | base64 -d > "$W/pw"
chmod 600 "$W/user" "$W/pw"

# Sign in: BFF /login -> Keycloak's form -> POST credentials -> BFF callback -> /sell.
curl_ -o /dev/null -D "$W/h" "$SITE/login?next=/sell"
curl_ -o "$W/form" -D "$W/h" "$(location)"
action="$(grep -o 'action="[^"]*login-actions/authenticate[^"]*"' "$W/form" | head -1 \
  | sed -e 's/^action="//' -e 's/"$//' -e 's/&amp;/\&/g')"
[[ -n "$action" ]] || fail "Keycloak showed no login form"
curl_ -o /dev/null -D "$W/h" --data-urlencode "username@$W/user" --data-urlencode "password@$W/pw" \
  --data "credentialId=" "$action"
callback="$(location)"
[[ "$callback" == "$SITE/auth/callback"* ]] || fail "Keycloak refused the verify seller"
curl_ -o /dev/null -D "$W/h" "$callback"
[[ "$(location)" == /sell ]] || fail "the BFF did not finish the sign-in"
CSRF="$(curl_ "$SITE/sell" | grep -o 'name="csrf_token" value="[^"]*"' | head -1 | sed -e 's/.*value="//' -e 's/"$//')"
[[ -n "$CSRF" ]] || fail "the selling page has no form token"
pass "verify seller signed in through the BFF login form"

# A draft, with a title made to be found in search and nowhere else.
RUN="verifyrun$(python3 -c 'import random, string; print("".join(random.choices(string.ascii_lowercase, k=8)))')"
curl_ -o /dev/null -D "$W/h" -d "csrf_token=$CSRF" -d "title=Sprint 2 check $RUN" -d "brand=Verify" \
  -d "category=tops" -d "size=M" -d "condition=good" -d "price=10.00" \
  -d "description=Created and deleted by verify_sprint2.sh." "$SITE/sell/listings"
created="$(location)"
[[ "$created" == /items/* ]] || fail "the draft was refused: $created"
LISTING="${created#/items/}"
pass "draft created"

upload() {  # file, content type -> the BFF's redirect
  curl_ -o /dev/null -D "$W/h" -F "csrf_token=$CSRF" -F "file=@$1;type=$2" \
    "$SITE/sell/listings/$LISTING/photos"
  location
}
printf 'not an image\n' > "$W/note.png"
[[ "$(upload "$W/note.png" image/png)" == *error=photo_type_rejected* ]] \
  && pass "a renamed .txt is refused (415 photo_type_rejected)" || fail "a renamed .txt was not refused"
{ printf '\x89PNG\r\n\x1a\n'; head -c 11534336 /dev/zero; } > "$W/big.png"
[[ "$(upload "$W/big.png" image/png)" == *error=photo_too_large* ]] \
  && pass "an 11 MB image is refused (413 photo_too_large)" || fail "an 11 MB image was not refused"

python3 - "$W" <<'PY'
import struct, sys, zlib
def png(path, rgb):
    rows = b"".join(b"\x00" + bytes(rgb) * 64 for _ in range(64))
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 64, 64, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))
png(sys.argv[1] + "/one.png", (140, 90, 60))
png(sys.argv[1] + "/two.png", (47, 79, 111))
PY
for f in one two; do
  [[ "$(upload "$W/$f.png" image/png)" == "/items/$LISTING" ]] || fail "photo $f was refused"
done
pass "two photos stored"

curl_ -o /dev/null -D "$W/h" -d "csrf_token=$CSRF" "$SITE/sell/listings/$LISTING/publish"
start="$(now)"
[[ "$(location)" == *published=1* ]] || fail "publishing was refused: $(location)"
found=""
while :; do
  if curl_ "$SITE/search?q=$RUN" | grep -q "/items/$LISTING"; then found="$(now)"; break; fi
  python3 -c "import sys; sys.exit(0 if float('$(now)') - float('$start') < $SEARCH_WITHIN else 1)" || break
  sleep 0.25
done
[[ -n "$found" ]] || fail "not in search within ${SEARCH_WITHIN}s of publishing (T113)"
took="$(python3 -c "print(round(float('$found') - float('$start'), 2))")"
pass "published and in search after ${took}s (limit ${SEARCH_WITHIN}s, T113)"

curl_ -o /dev/null -D "$W/h" -d "csrf_token=$CSRF" "$SITE/sell/listings/$LISTING/delete"
[[ "$(location)" == "/sell?deleted=1" ]] || fail "the delete was refused: $(location)"
LISTING_DELETED="$LISTING"
LISTING=""
code="$(curl_ -o /dev/null -w '%{http_code}' "$SITE/items/$LISTING_DELETED")"
[[ "$code" == 404 ]] && ! curl_ "$SITE/search?q=$RUN" | grep -q "/items/$LISTING_DELETED" \
  && pass "deleted: gone from its page and from search" || fail "the deleted listing is still shown ($code)"
