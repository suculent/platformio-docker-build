#!/bin/sh
#
# thinx.yml loader test: cmd.sh must read thinx.yml without eval.
#
# thinx.yml is repository content, and the THiNX API writes decrypted devsec
# credentials into it before a build. cmd.sh used to run
#   eval $(parse_yaml "$YMLFILE" "")
# which ran any $(...), backtick or quote break-out in a value as shell inside
# the build container. This test runs cmd.sh's own thinx.yml load step (its
# top-level functions, then the line that loads thinx.yml) on crafted files in
# a temp dir and checks that:
#  - a marker command in a value never runs ($(...), backticks, a quote
#    break-out with ;, list items, names cmd.sh does not read, multi-line);
#  - values reach the variables literally, and only the names cmd.sh reads;
#  - legit thinx.yml layouts give the same values as the old parse_yaml + eval;
#  - loading prints nothing (devsec values are Wi-Fi credentials and keys).
#
# Plain POSIX sh: runs under bash, dash or busybox sh, with any awk. No Docker.
#   sh tests/thinx-yml-loader.sh
# In the image: /opt/tests/thinx-yml-loader.sh (cmd.sh is /opt/cmd.sh).
# The worker reads platformio.environment on its own (builder-lib.sh
# pio_yml_environment: quotes dropped, last one wins); this image must agree.
# CMD_SH=/path/to/cmd.sh tests another copy.

# Names cmd.sh reads after loading thinx.yml.
NAMES="platformio_environment platformio_target environment_target"
# Names thinx.yml carries that cmd.sh does not read; they must stay unset.
UNREAD="devsec_ssid devsec_pass devsec_ckey platformio platformio_arch
platformio_libs arduino_board"

HERE=$(cd "$(dirname "$0")" && pwd)
CMD_SH=${CMD_SH:-$HERE/../cmd.sh}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/thinx-yml-test.XXXXXX") || exit 1
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

# cmd.sh's top-level functions, and the line that loads thinx.yml.
FUNCS=$WORK/functions.sh
awk '/^[A-Za-z_][A-Za-z0-9_]*[ \t]*\(\)/ { f = 1 } f { print } f && /^}/ { f = 0 }' \
	"$CMD_SH" > "$FUNCS"
LOAD_LINE=$(grep -E '^[[:space:]]*(eval[[:space:]].*parse_yaml|thinx_yml_load[[:space:]])' \
	"$CMD_SH" | head -n 1)

# load DIR: runs the load step on DIR/thinx.yml with DIR as the working
# directory and set -e on. Writes "name=value" or "name unset" for every name
# in NAMES and UNREAD to DIR/vars, and whatever the load step printed to
# DIR/output. The names are this test's own, never read from a yml file.
load() {
	(
		cd "$1" || exit 1
		for name in $NAMES $UNREAD; do unset "$name"; done
		YMLFILE=$1/thinx.yml
		WORKDIR=$1
		. "$FUNCS"
		set -e
		eval "$LOAD_LINE"
		set +e
		for name in $NAMES $UNREAD; do
			if eval "[ -n \"\${$name+set}\" ]"; then
				eval "printf '%s=%s\n' \"\$name\" \"\$$name\""
			else
				printf '%s unset\n' "$name"
			fi
		done > "$1/vars"
	) > "$1/output" 2>&1
}

# newcase NAME: a case directory; thinx.yml comes from stdin. Feed it with a
# here-document or a file, never a pipe: a piped function runs in a subshell
# and CASE would not change.
newcase() {
	CASE=$WORK/$1
	mkdir -p "$CASE"
	cat > "$CASE/thinx.yml"
}

has() { grep -Fqx -- "$1" "$CASE/vars" 2>/dev/null; }

# expect DESC LINE...: after load, every LINE ("name=value" / "name unset")
# is in vars, every other name in NAMES and UNREAD is unset, and nothing was
# printed.
expect() {
	desc=$1; shift
	load "$CASE"
	why=""
	if [ ! -f "$CASE/vars" ]; then
		not_ok "$desc" "the load step failed: $(head -c 300 "$CASE/output")"
		return
	fi
	for line in "$@"; do
		has "$line" || why="$why [missing: $line]"
	done
	for name in $NAMES $UNREAD; do
		listed=no
		for line in "$@"; do
			case "$line" in "$name="*|"$name unset") listed=yes ;; esac
		done
		[ $listed = yes ] || has "$name unset" || why="$why [$name should be unset]"
	done
	[ -s "$CASE/output" ] && why="$why [load printed output]"
	[ -e "$CASE/PWNED" ] && why="$why [MARKER CREATED: thinx.yml content ran as shell]"
	if [ -z "$why" ]; then ok "$desc"; else not_ok "$desc" "$why"; fi
}

# no_marker DESC: after load, no PWNED file exists in the case dir.
no_marker() {
	load "$CASE"
	if [ -e "$CASE/PWNED" ]; then
		not_ok "$1" "marker file created: thinx.yml content ran as shell"
	else
		ok "$1"
	fi
}

echo "# cmd.sh: $CMD_SH"

# --- wiring -------------------------------------------------------------------

code=$(grep -v '^[[:space:]]*#' "$CMD_SH")
if printf '%s\n' "$code" | grep -Eq '(^|[^A-Za-z0-9_])eval([^A-Za-z0-9_]|$)'; then
	not_ok "cmd.sh has no eval" "$(printf '%s\n' "$code" | grep -En '(^|[^A-Za-z0-9_])eval([^A-Za-z0-9_]|$)' | head -n 3)"
else
	ok "cmd.sh has no eval"
fi
if printf '%s\n' "$code" | grep -q 'parse_yaml'; then
	not_ok "cmd.sh has no parse_yaml"
else
	ok "cmd.sh has no parse_yaml"
fi
if printf '%s\n' "$code" | grep -Eq '(^|[;&|[:space:]])(source|\.)[[:space:]][^;&|]*(yml|YML)'; then
	not_ok "cmd.sh does not source thinx.yml"
else
	ok "cmd.sh does not source thinx.yml"
fi
if grep -q '^thinx_yml_load[[:space:]]*()' "$FUNCS" &&
	printf '%s\n' "$LOAD_LINE" | grep -Eq '^[[:space:]]*thinx_yml_load[[:space:]]'; then
	ok "cmd.sh loads thinx.yml with thinx_yml_load"
else
	not_ok "cmd.sh loads thinx.yml with thinx_yml_load" "load line: ${LOAD_LINE:-none}"
fi

# --- nothing in thinx.yml runs --------------------------------------------------

newcase marker-plain-subst <<'EOF'
platformio:
  environment: $(touch PWNED)
EOF
no_marker 'plain $(...) value does not run'
has 'platformio_environment=$(touch PWNED)' && ok 'plain $(...) value is kept literally' ||
	not_ok 'plain $(...) value is kept literally'

newcase marker-plain-backtick <<'EOF'
platformio:
  target: `touch PWNED`
EOF
no_marker 'plain backtick value does not run'
has 'platformio_target=`touch PWNED`' && ok 'plain backtick value is kept literally' ||
	not_ok 'plain backtick value is kept literally'

newcase marker-breakout <<'EOF'
environment:
  target: x"); touch PWNED; #
EOF
no_marker 'quote break-out with ; does not run'
has 'environment_target=x"); touch PWNED; #' && ok 'quote break-out is kept literally' ||
	not_ok 'quote break-out is kept literally'

newcase marker-dq <<'EOF'
platformio:
  environment: "$(touch PWNED)"
  target: "`touch PWNED`"
environment:
  target: "x"); touch PWNED; #"
EOF
no_marker 'double-quoted $(...), backtick and break-out values do not run'
has 'platformio_environment=$(touch PWNED)' && has 'platformio_target=`touch PWNED`' &&
	has 'environment_target=x"); touch PWNED; #' &&
	ok 'double-quoted values are kept literally' ||
	not_ok 'double-quoted values are kept literally'

newcase marker-list <<'EOF'
platformio:
  target:
    - $(touch PWNED)
    - x"); touch PWNED; #
EOF
no_marker 'list items do not run'
has 'platformio_target=$(touch PWNED)' && ok 'list item is kept literally' ||
	not_ok 'list item is kept literally'

newcase marker-unread <<'EOF'
devsec:
  ssid: "$(touch PWNED)"
  pass: `touch PWNED`
  ckey: x"); touch PWNED; #
platformio:
  arch: $(touch PWNED)
  libs:
    - `touch PWNED`
EOF
expect 'names cmd.sh does not read neither run nor get set'

newcase marker-multiline <<'EOF'
platformio:
  environment: "x
$(touch PWNED)"
  target: |
    $(touch PWNED)
environment:
  target: first
    $(touch PWNED)
EOF
expect 'multi-line values do not run and are rejected'

newcase marker-control < /dev/null
printf 'platformio:\n  environment: a\001$(touch PWNED)\n  target: a\000b\nenvironment:\n  target: "a\033b"\n' \
	> "$CASE/thinx.yml"
expect 'values with control characters (NUL, ESC, ^A) are rejected'

# --- legit layouts: same values as the old parse_yaml + eval --------------------

# thinx-autoflood
newcase autoflood <<'EOF'
platformio:
  arch: esp8266
  environment: d1_mini
EOF
expect 'thinx-autoflood layout' platformio_environment=d1_mini

# README.md example (devsec placeholders as in the README)
newcase readme <<'EOF'

# Builder Selection and Options
platformio:
  environment: esp8266-release
  target: env
  
# DevSec Built-in Credentials Encryption
devsec:
  ckey: <my-devsec-cryptokey>
  ssid: <my-ssid>
  pass: <my-password>
EOF
expect 'README.md example' platformio_environment=esp8266-release platformio_target=env

# Layout of thinx-firmware-esp8266-pio (devsec values replaced): a commented
# arduino block, devsec, environment target.
newcase esp8266-pio <<'EOF'
# for Platformio-based ESP8266 CI builds

platformio:
  environment: d1_mini

# arduino:
#   platform: espressif
#   board: d1_mini_pro

# Those lines MUST be masked out in ENV prints!
devsec:
  ckey: "fake-ckey-0123456789abcdef"
  ssid: "fake ssid"
  pass: "fake \"pass\" \\ word"

# Per-device env-var injection
environment:
  target: src/environment.h
EOF
expect 'thinx-firmware-esp8266-pio layout' \
	platformio_environment=d1_mini environment_target=src/environment.h

# Layout of thinx-firmware-esp32-pio: none of the names cmd.sh reads, no
# final newline.
newcase esp32-pio < /dev/null
printf 'platformio:\n  platform: espressif\n  arch: esp32\n  board: esp32\n  libs:\n    - ArduinoJSON' \
	> "$CASE/thinx.yml"
expect 'thinx-firmware-esp32-pio layout (file without final newline)'

# A list used to append to a bash array, and cmd.sh reads ${platformio_target},
# the first element. Kept as it was.
newcase target-list <<'EOF'
platformio:
  target:
    - upload
    - monitor
EOF
expect 'target list: the first item, as before' platformio_target=upload

newcase quoted <<'EOF'
platformio:
  environment: "d1_mini"
  target:   'env'
environment:
  target: "src/a\"b\\c\d.h"
EOF
expect 'double quotes dropped, single quotes kept, \" and \\ escapes' \
	platformio_environment=d1_mini "platformio_target='env'" 'environment_target=src/a"b\c\d.h'

newcase last-wins <<'EOF'
platformio:
  environment: first
  environment: "second"
EOF
expect 'a repeated key: the last one wins (as the worker reads it)' platformio_environment=second

newcase crlf < /dev/null
printf 'platformio:\r\n  environment: "d1_mini"\r\n  target: env\r\nenvironment:\r\n  target: "src/a\tb.h"\r\n' \
	> "$CASE/thinx.yml"
expect 'CRLF line ends are dropped, tab is kept' \
	platformio_environment=d1_mini platformio_target=env "$(printf 'environment_target=src/a\tb.h')"

newcase missing-file < /dev/null
rm -f "$CASE/thinx.yml"
expect 'a missing thinx.yml sets nothing'

echo "1..$n"
if [ "$failed" -gt 0 ]; then
	echo "# $failed of $n failed"
	exit 1
fi
echo "# all $n passed"
