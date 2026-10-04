#!/bin/sh
#
# Per-device environment header test.
#
# When a device has environment variables, the THiNX API writes them to
# environment.json and cmd.sh turns them into a C header of
#   #define ENVIRONMENT_<KEY> <json value>
# lines. The header goes to thinx.yml's `environment: target:` when it is set,
# else to an environment.h already in the workspace. cmd.sh used to overwrite
# the target with `find ... environment.h | head -n 1` and then `touch` it
# unquoted, so a repository with neither (thinx-autoflood) failed every build
# with `touch: missing file operand` under set -e (build 0a812dc0,
# 2026-10-04).
#
# This test runs cmd.sh's own functions and its env-header call line on
# crafted workspaces in a temp dir and checks that:
#  - neither target nor environment.h: the header is skipped with one log
#    line and the step returns 0;
#  - environment: target: wins, resolved under the workspace; else the first
#    environment.h (build/ and .pio/ excluded) is rewritten;
#  - an absolute target, a '..' target, a target whose directory resolves
#    outside the workspace, a symlink or a directory is refused (skipped);
#  - the header holds exactly the expected defines (sorted keys, JSON values,
#    keys that are not C identifiers and SKIP_KEYS left out);
#  - no environment.json value ever reaches stdout/stderr.
#
# Plain POSIX sh: runs under bash, dash or busybox sh. Needs jq (cmd.sh does).
#   sh tests/env-header.sh
# In the image: /opt/tests/env-header.sh (cmd.sh is /opt/cmd.sh).
# CMD_SH=/path/to/cmd.sh tests another copy.

# Keys cmd.sh leaves out of the header (they go into thinx.yml as devsec).
SKIP_KEYS="CPASS CSSID"
# The header every "written" case expects for $WORK/environment.json below.
EXPECTED='/* This file is auto-generated. */
#define ENVIRONMENT_CFLAGS "-DVALUE_MARKER_CFLAG=1"
#define ENVIRONMENT_COUNT 3
#define ENVIRONMENT_LOWER_CASE "VALUE-MARKER lower \"quoted\""
#define ENVIRONMENT_SSID "VALUE-MARKER-ssid"'
# A thinx.yml of this image with no environment: target: (thinx-autoflood).
YML_NO_TARGET='platformio:
  arch: esp8266
  environment: d1_mini'
# The same, with the target thinx-firmware-esp8266-pio uses.
YML_TARGET='platformio:
  environment: d1_mini

# Per-device env-var injection
environment:
  target: src/environment.h'

HERE=$(cd "$(dirname "$0")" && pwd)
CMD_SH=${CMD_SH:-$HERE/../cmd.sh}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/env-header-test.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
trap 'exit 1' INT TERM

n=0
failed=0
ok() { n=$((n + 1)); echo "ok $n - $1"; }
not_ok() {
	n=$((n + 1)); failed=$((failed + 1))
	echo "not ok $n - $1"
	[ -z "${2-}" ] || echo "#   $2"
}

[ -f "$CMD_SH" ] || { echo "Bail out! no cmd.sh at $CMD_SH"; exit 1; }
command -v jq > /dev/null 2>&1 || { echo "Bail out! jq not found (cmd.sh needs it too)"; exit 1; }

# cmd.sh's top-level functions, its thinx.yml load line and its env-header
# call line.
FUNCS=$WORK/functions.sh
awk '/^[A-Za-z_][A-Za-z0-9_]*[ \t]*\(\)/ { f = 1 } f { print } f && /^}/ { f = 0 }' \
	"$CMD_SH" > "$FUNCS"
LOAD_LINE=$(grep -E '^[[:space:]]*thinx_yml_load[[:space:]]' "$CMD_SH" | head -n 1)
GEN_LINE=$(grep -E '^[[:space:]]*env_header_generate[[:space:]]' "$CMD_SH" | head -n 1)

# environment.json as the API writes it (JSON.stringify of device.environment),
# every value a marker that must never be printed.
cat > "$WORK/environment.json" <<'EOF'
{"ssid":"VALUE-MARKER-ssid","count":3,"lower_case":"VALUE-MARKER lower \"quoted\"","CPASS":"VALUE-MARKER-cpass","CSSID":"VALUE-MARKER-cssid","cflags":"-DVALUE_MARKER_CFLAG=1","bad-key":"VALUE-MARKER-bad","x y":"VALUE-MARKER-space"}
EOF

# newcase NAME: a fresh case dir with a workspace ($WS, with environment.json
# and src/) and a sibling dir outside it ($OUT).
newcase() {
	CASE=$WORK/$1
	WS=$CASE/ws
	OUT=$CASE/outside
	mkdir -p "$WS/src" "$OUT"
	cp "$WORK/environment.json" "$WS/environment.json"
	ENVFILE_ARG=$WS/environment.json
}

# run TARGET [YML]: runs the env-header call line in $WS with set -e on, as
# cmd.sh does. With YML, writes it to $WS/thinx.yml and runs the load line
# first, so environment_target comes from thinx.yml; else environment_target
# is TARGET. Output goes to $CASE/output, the exit status to $CASE/status.
run() {
	if [ $# -gt 1 ]; then printf '%s\n' "$2" > "$WS/thinx.yml"; fi
	(
		cd "$WS" || exit 1
		unset ENVOUT environment_target platformio_environment platformio_target
		YMLFILE=$WS/thinx.yml
		WORKSPACE=$WS
		WORKDIR=$WS
		ENVFILE=$ENVFILE_ARG
		. "$FUNCS"
		set -e
		if [ $# -gt 1 ]; then eval "$LOAD_LINE"; else environment_target=$1; fi
		eval "$GEN_LINE"
	) > "$CASE/output" 2>&1
	echo $? > "$CASE/status"
}

# check DESC [written PATH | skipped | refused | nojson]: the step returned 0,
# printed no environment.json value, and
#  - written PATH: PATH holds exactly $EXPECTED;
#  - skipped/refused: one "skipped" line (refused: a "Refusing" line too);
#  - nojson: "No environment.json found".
# No environment.h / env.h was created or changed anywhere else: callers list
# the files they expect untouched with keep FILE CONTENT beforehand.
check() {
	desc=$1; what=$2; path=${3-}
	why=""
	st=$(cat "$CASE/status")
	[ "$st" = 0 ] || why="$why [exit status $st: $(head -c 300 "$CASE/output")]"
	grep -q 'VALUE-MARKER\|VALUE_MARKER' "$CASE/output" &&
		why="$why [an environment.json value was printed]"
	case "$what" in
	written)
		if [ ! -f "$path" ]; then
			why="$why [no header at $path]"
		elif [ "$(cat "$path")" != "$EXPECTED" ]; then
			why="$why [header differs: $(tr '\n' '|' < "$path")]"
		fi
		grep -q 'skipped' "$CASE/output" && why="$why [logged skipped]"
		;;
	skipped|refused)
		c=$(grep -c 'skipped' "$CASE/output")
		[ "$c" = 1 ] || why="$why [$c skipped lines, want 1]"
		if [ "$what" = refused ]; then
			grep -q 'Refusing' "$CASE/output" || why="$why [no Refusing line]"
		fi
		;;
	nojson)
		grep -q 'No environment.json found' "$CASE/output" ||
			why="$why [no 'No environment.json found' line]"
		;;
	esac
	# Every header-like file in the case must be one we expect.
	for f in $(find "$CASE" \( -name environment.h -o -name '*.h' \) -print 2>/dev/null); do
		[ "$what" = written ] && [ "$f" = "$path" ] && continue
		# A symlink the case planted; check its target (a keep file) instead.
		[ -L "$f" ] && continue
		if [ -f "$CASE/keep.list" ] && grep -Fqx -- "$f" "$CASE/keep.list"; then
			[ "$(cat "$f")" = "kept $f" ] || why="$why [$f was changed]"
		else
			why="$why [unexpected file $f]"
		fi
	done
	if [ -z "$why" ]; then ok "$desc"; else not_ok "$desc" "$why"; fi
}

# keep FILE: creates FILE with a known content that check() requires intact.
keep() {
	mkdir -p "$(dirname "$1")"
	printf 'kept %s' "$1" > "$1"
	echo "$1" >> "$CASE/keep.list"
}

echo "# cmd.sh: $CMD_SH"

# --- wiring -------------------------------------------------------------------

code=$(grep -v '^[[:space:]]*#' "$CMD_SH")
if grep -q '^env_header_target[[:space:]]*()' "$FUNCS" &&
	grep -q '^env_header_generate[[:space:]]*()' "$FUNCS"; then
	ok "cmd.sh defines env_header_target and env_header_generate"
else
	not_ok "cmd.sh defines env_header_target and env_header_generate"
fi
if printf '%s\n' "$GEN_LINE" | grep -q '"\$ENVFILE"' &&
	printf '%s\n' "$GEN_LINE" | grep -Eq '"\$\{?environment_target\}?"'; then
	ok "cmd.sh generates the header from \$ENVFILE and environment_target"
else
	not_ok "cmd.sh generates the header from \$ENVFILE and environment_target" \
		"call line: ${GEN_LINE:-none}"
fi
if printf '%s\n' "$code" | grep -Eq 'ENVOUT=\$\(find|touch[[:space:]]+\$'; then
	not_ok "cmd.sh never takes ENVOUT from a bare find and never touches an unquoted path" \
		"$(printf '%s\n' "$code" | grep -En 'ENVOUT=\$\(find|touch[[:space:]]+\$' | head -n 3)"
else
	ok "cmd.sh never takes ENVOUT from a bare find and never touches an unquoted path"
fi
if printf '%s\n' "$code" | grep -Eq '(^|[^"])\$\{?ENVOUT'; then
	not_ok "ENVOUT is quoted everywhere" \
		"$(printf '%s\n' "$code" | grep -En '(^|[^"])\$\{?ENVOUT' | head -n 3)"
else
	ok "ENVOUT is quoted everywhere"
fi

# --- (a) neither target nor environment.h: skipped, build goes on -------------

newcase none
run ""
check "no target, no environment.h: header skipped, exit 0" skipped

newcase none-yml
run "" "$YML_NO_TARGET"
check "thinx-autoflood layout (build 0a812dc0): header skipped, exit 0" skipped

newcase only-in-output-dirs
keep "$WS/build/environment.h"
keep "$WS/.pio/build/d1_mini/environment.h"
run ""
check "environment.h only under build/ and .pio/: ignored, header skipped" skipped

newcase symlink-found
keep "$OUT/environment.h"
ln -s ../outside/environment.h "$WS/environment.h"
run ""
check "an environment.h symlink is not followed: header skipped" skipped

# --- (b) environment: target: wins ----------------------------------------------

newcase target
keep "$WS/environment.h"
run "src/env.h"
check "target src/env.h: header written there, environment.h left alone" written "$WS/src/env.h"

newcase target-yml
keep "$WS/environment.h"
run "" "$YML_TARGET"
check "thinx-firmware-esp8266-pio layout: target from thinx.yml" written "$WS/src/environment.h"

newcase target-existing
printf '#define OLD 1\n' > "$WS/src/environment.h"
run "src/environment.h"
check "an existing target is rewritten, old defines dropped" written "$WS/src/environment.h"

newcase target-root
run "env.h"
check "target in the workspace root" written "$WS/env.h"

newcase target-nodir
run "nodir/env.h"
check "target directory missing: refused, nothing created" refused
[ -e "$WS/nodir" ] && not_ok "missing target directory is not created" || ok "missing target directory is not created"

# --- (c) environment.h in the workspace -----------------------------------------

newcase found
printf '#define OLD 1\n' > "$WS/src/environment.h"
keep "$WS/build/environment.h"
keep "$WS/.pio/build/d1_mini/environment.h"
run ""
check "no target: the environment.h in the workspace is rewritten" written "$WS/src/environment.h"

# --- (d) refused targets: skipped, nothing written outside --------------------

for t in "../outside/env.h" "src/../../outside/env.h" "src/.." ".." "src/" "src/." "/etc/x"; do
	newcase "refuse-$(printf '%s' "$t" | tr -c 'A-Za-z0-9' '_')"
	run "$t"
	check "target '$t' refused" refused
done

newcase refuse-abs
run "$OUT/env.h"
check "absolute target into an existing dir refused" refused

newcase refuse-link-dir
ln -s ../outside "$WS/link"
run "link/env.h"
check "target through a symlinked directory leaving the workspace refused" refused

newcase refuse-link-file
keep "$OUT/real.h"
ln -s ../outside/real.h "$WS/env.h"
run "env.h"
check "target that is a symlink refused" refused

newcase refuse-dir
run "src"
check "target that is a directory refused" refused

# --- environment.json handling --------------------------------------------------

newcase no-json
ENVFILE_ARG=""
run "src/env.h"
check "no environment.json: nothing written, even with a target" nojson

# jq quotes the offending input in some errors (`string ("...") has no keys`),
# so its stderr must not reach the build log either.
for j in '{"ssid": VALUE-MARKER-broken' '"VALUE-MARKER-string"' '["VALUE-MARKER-array"]'; do
	newcase "bad-json-$(printf '%s' "$j" | cksum | cut -d ' ' -f 1)"
	printf '%s' "$j" > "$WS/environment.json"
	run "src/env.h"
	st=$(cat "$CASE/status")
	if [ "$st" = 0 ] && [ "$(cat "$WS/src/env.h" 2>/dev/null)" = '/* This file is auto-generated. */' ] &&
		! grep -q 'VALUE-MARKER' "$CASE/output"; then
		ok "environment.json $j: header with no defines, exit 0, nothing printed"
	else
		not_ok "environment.json $j: header with no defines, exit 0, nothing printed" \
			"status $st, output: $(head -c 300 "$CASE/output")"
	fi
done

newcase key-names
run "src/env.h"
if grep -q '"bad-key"' "$CASE/output" && grep -q '"x y"' "$CASE/output"; then
	ok "keys that are not C identifiers are named in the log (values are not)"
else
	not_ok "keys that are not C identifiers are named in the log (values are not)" \
		"output: $(head -c 300 "$CASE/output")"
fi

echo "1..$n"
if [ "$failed" -gt 0 ]; then
	echo "# $failed of $n failed"
	exit 1
fi
echo "# all $n passed"
