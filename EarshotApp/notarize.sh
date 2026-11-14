#!/usr/bin/env bash
# Notarizes and staples a signed Earshot disk image, then checks that Gatekeeper accepts it
# (ADR-2611141600). After this, the DMG and the app inside it open with a double-click.
#
#   bash EarshotApp/notarize.sh Earshot-<version>.dmg
#
# The DMG must come from make-dmg.sh with EARSHOT_SIGN_IDENTITY set (a Developer ID-signed app,
# hardened runtime, in a signed DMG). Credentials, either one:
#   EARSHOT_NOTARY_PROFILE  a keychain profile, made once with
#                           xcrun notarytool store-credentials earshot-notary --apple-id <id> --team-id <team>
#   NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER_ID
#                           an App Store Connect API key (.p8), as CI uses
# It fails loudly on any missing piece; it never "succeeds" without a stapled, accepted DMG.
set -euo pipefail

die() { echo "notarize: $*" >&2; exit 1; }

DMG="${1:-}"
[[ -n $DMG && -f $DMG ]] || die "usage: notarize.sh <path to .dmg>"

if [[ -n ${EARSHOT_NOTARY_PROFILE:-} ]]; then
  auth=(--keychain-profile "$EARSHOT_NOTARY_PROFILE")
elif [[ -n ${NOTARY_KEY_PATH:-} && -n ${NOTARY_KEY_ID:-} && -n ${NOTARY_ISSUER_ID:-} ]]; then
  [[ -f $NOTARY_KEY_PATH ]] || die "NOTARY_KEY_PATH does not exist: $NOTARY_KEY_PATH"
  auth=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
else
  die "no credentials: set EARSHOT_NOTARY_PROFILE, or NOTARY_KEY_PATH, NOTARY_KEY_ID and NOTARY_ISSUER_ID"
fi

# Catch an unsigned or ad-hoc build here, with a clear message, instead of a rejection 5 minutes later.
codesign --verify --strict "$DMG" 2>/dev/null || die "$DMG is not signed (run make-dmg.sh with EARSHOT_SIGN_IDENTITY set)"
mnt=$(mktemp -d)
hdiutil attach -nobrowse -readonly -mountpoint "$mnt" "$DMG" >/dev/null
trap 'hdiutil detach "$mnt" -quiet >/dev/null 2>&1 || true; rmdir "$mnt" 2>/dev/null || true' EXIT
app="$mnt/Earshot.app"
[[ -d $app ]] || die "no Earshot.app inside $DMG"
info=$(codesign -dvv "$app" 2>&1)
grep -q '^Authority=Developer ID Application' <<<"$info" || die "Earshot.app is not signed with a Developer ID Application certificate"
grep -q 'flags=.*runtime' <<<"$info" || die "Earshot.app is not signed with the hardened runtime"
grep -q '^Timestamp=' <<<"$info" || die "Earshot.app has no secure timestamp"
hdiutil detach "$mnt" -quiet; rmdir "$mnt"; trap - EXIT

echo "notarize: submitting $DMG (this usually takes a few minutes)"
out=$(xcrun notarytool submit "$DMG" "${auth[@]}" --wait --output-format json) || true
id=$(python3 -I -c 'import json,sys; print(json.loads(sys.stdin.read() or "{}").get("id",""))' <<<"$out" 2>/dev/null || true)
status=$(python3 -I -c 'import json,sys; print(json.loads(sys.stdin.read() or "{}").get("status",""))' <<<"$out" 2>/dev/null || true)
if [[ $status != Accepted ]]; then
  echo "$out" >&2
  [[ -n $id ]] && xcrun notarytool log "$id" "${auth[@]}" >&2 || true
  die "notarization ${status:-failed}${id:+ (submission $id)}"
fi
echo "notarize: accepted (submission $id)"

xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
echo "notarize: $DMG is notarized, stapled and accepted by Gatekeeper"
