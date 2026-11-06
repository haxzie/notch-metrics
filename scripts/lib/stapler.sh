#!/usr/bin/env bash
# `xcrun stapler`, retried, because every action it has is a network call.
#
# Notarisation finishing with `status: Accepted` means Apple has minted the
# ticket. Both `stapler staple` and `stapler validate` then talk to
# `api.apple-cloudkit.com` to fetch it, and that fetch fails on its own
# schedule — three times in one afternoon here, with
#
#     NSURLErrorDomain Code=-1005 "The network connection was lost."
#     Error 68.
#
# once stapling the disk image, once stapling the app, and once *validating* a
# staple that had just succeeded. Every time, the submission had already been
# accepted: the only thing lost was a signed build and fifteen minutes of
# macOS runner time.
#
# Retried rather than failed, because there is nothing to diagnose and nothing
# to decide — the ticket exists and this end could not read it. The sleep grows
# because a ticket just minted can take a moment to become readable.
#
# Sourced by both sign-and-notarize.sh and verify-signature.sh. One copy,
# because a retry that exists in only one of them is the one the release trips
# over.
stapler_retry() {
  local action="$1" target="$2" attempt=1 max=5 delay=15
  until xcrun stapler "$action" "$target"; do
    if [ "$attempt" -ge "$max" ]; then
      echo "::error::stapler $action failed $max times on $target."
      echo "If the notarisation was accepted, the artefact is fine and re-running"
      echo "this workflow on the same tag resumes rather than resubmitting."
      return 1
    fi
    echo "==> stapler $action failed (attempt $attempt of $max); retrying in ${delay}s"
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
}
