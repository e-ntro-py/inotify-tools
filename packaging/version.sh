#!/bin/sh
# Prints the release version, e.g. 4.26.261:
#
#   packaging/version.sh            # as below, or <series>.0 without git history
#   packaging/version.sh --strict   # fail instead of guessing (releases)
#
# Every commit on master that passes CI is released, so the version is
#
#     <series from VERSION>.<number of commits reachable from HEAD>
#
# Bump the series in VERSION (MAJOR.MINOR) to start a new one; the count
# only grows, so versions stay increasing. `make dist` writes the full
# version into the tarball's VERSION, which is then printed as is.

set -eu

die() {
	printf 'version.sh: %s\n' "$*" >&2
	exit 1
}

strict=0
case "${1:-}" in
"") ;;
--strict) strict=1 ;;
*) die "unknown argument: $1" ;;
esac

root="$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)"
series="$(tr -d '[:space:]' < "$root/VERSION")"
case "$series" in
*[!0-9.]* | '' | .* | *.) die "VERSION \"$series\" is not MAJOR.MINOR" ;;
*.*.*) printf '%s\n' "$series"; exit 0 ;; # stamped by make dist
*.*) ;;
*) die "VERSION \"$series\" is not MAJOR.MINOR" ;;
esac

# Only count commits if $root is itself the top of a full clone.
top="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null || true)"
shallow="$(git -C "$root" rev-parse --is-shallow-repository 2>/dev/null || true)"
if [ -n "$top" ] && [ "$(cd "$top" && pwd)" = "$root" ] && [ "$shallow" = false ]; then
	printf '%s.%s\n' "$series" "$(git -C "$root" rev-list --count HEAD)"
elif [ "$strict" -eq 1 ]; then
	die "needs a full (non-shallow) git clone to count commits"
else
	printf '%s.0\n' "$series"
fi
