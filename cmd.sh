#!/usr/bin/env bash

set -e

echo "platformio-docker-build-${BUILD_VERSION:-unknown}"
echo $GIT_TAG

# --- thinx.yml ----------------------------------------------------------------
#
# thinx.yml is repository content, and the THiNX API writes decrypted devsec
# credentials into it before a build. It is read here and never eval'd or
# sourced: the old `eval $(parse_yaml ...)` ran any $(...), backtick or quote
# break-out in a value as shell, in a container that may hold docker.sock.
#
# thinx_yml_load FILE assigns, with plain `name=$value` assignments, only the
# names this script reads:
#   platformio_environment platformio_target environment_target
# Any other name is ignored. Nothing is exported and nothing is printed.
#
# Names follow the old parse_yaml: the parent keys joined with "_" (two spaces
# of indent per level), e.g. platformio: / environment: ->
# platformio_environment. Values:
#  - key: "..."  quotes dropped; \" and \\ decoded (the escapes eval used to
#    decode the same way); any other backslash stays as it is;
#  - - "..."     a double-quoted list item: the same;
#  - key: ...    taken as written: $, `, ;, \ and quotes stay literal;
#  - a trailing CR (CRLF files) is dropped;
#  - a value that continues on the next line (block scalar |/>, folded plain
#    or multi-line quoted scalar) or holds a control character other than
#    tab (NUL included) is rejected; its variable is left as it was.
# A list item (`- item` under a key) used to append to a bash array, and this
# script reads ${name}, the array's first element. So a list item only sets a
# name that has no value yet: target: with the items "- A" and "- B" still
# gives platformio_target=A.
# The worker reads platformio: / environment: on its own to pick the image it
# deploys (builder-lib.sh pio_yml_environment: quotes dropped, last one wins);
# for that entry the two agree.
#
# Same awk as thinx_yml_load in the THiNX worker (services/worker/builder-lib.sh)
# and the arduino, nodemcu and micropython builder images; keep them in step.
# A missing FILE sets nothing. Returns 0.
thinx_yml_load()
{
	[ -f "$1" ] || return 0

	thinx_yml_pairs=$(tr '\000' '\001' < "$1" | awk '
		function unescape_dq(s,    out, i, n, c, d) {
			out = ""
			n = length(s)
			for (i = 1; i <= n; i++) {
				c = substr(s, i, 1)
				if (c == "\\" && i < n) {
					d = substr(s, i + 1, 1)
					if (d == "\\" || d == "\"") {
						out = out d
						i++
						continue
					}
				}
				out = out c
			}
			return out
		}
		function flush() {
			if (pending != "") print pending
			pending = ""
		}
		{
			line = $0
			sub(/\r$/, "", line)
			match(line, /^[ \t]*/)
			ind = substr(line, 1, RLENGTH)
			rest = substr(line, RLENGTH + 1)
			match(rest, /^[A-Za-z0-9_]*/)
			key = substr(rest, 1, RLENGTH)
			rest = substr(rest, RLENGTH + 1)

			if (rest ~ /^[ \t]*:[ \t]*".*"[ \t]*$/) {
				style = "dq"
			} else if (rest ~ /^[ \t]*[:-]/) {
				style = "plain"
			} else {
				# Not a key line. Blank lines and comments are skipped;
				# anything else continues the previous value, which is
				# then multi-line and rejected.
				if (line !~ /^[ \t]*(#.*)?$/) pending = ""
				next
			}

			flush()

			indent = length(ind) / 2
			vname[indent] = key
			for (i in vname) { if (i > indent) { delete vname[i] } }

			value = rest
			if (style == "dq") {
				sub(/^[ \t]*:[ \t]*"/, "", value)
				sub(/"[ \t]*$/, "", value)
				value = unescape_dq(value)
			} else {
				sub(/^[ \t]*[:-][ \t]*/, "", value)
				if (value ~ /^".*"[ \t]*$/) {
					# - "item": eval dropped these quotes too.
					sub(/[ \t]*$/, "", value)
					value = unescape_dq(substr(value, 2, length(value) - 2))
				}
			}

			if (length(value) == 0) next
			if (style == "plain" && value ~ /^[|>][-+0-9]*[ \t]*$/) next

			tabless = value
			gsub(/\t/, "", tabless)
			if (tabless ~ /[[:cntrl:]]/) next

			vn = ""
			for (i = 0; i < indent; i++) { vn = (vn)(vname[i])("_") }
			name = vn key
			# A trailing "_" is a list item: the old parse_yaml made it "+=".
			op = "="
			if (sub(/_$/, "", name)) op = "+="
			if (name !~ /^[A-Za-z_][A-Za-z0-9_]*$/) next

			pending = name op value
		}
		END { flush() }
	')

	# The here-document expands $thinx_yml_pairs once; its text is not
	# expanded again, and each value is assigned, never evaluated.
	# `[ append ] && [ already set ] || name=value` skips a list item when the
	# name already has a value (see above); everything else assigns.
	while IFS= read -r thinx_yml_line
	do
		thinx_yml_name=${thinx_yml_line%%=*}
		thinx_yml_value=${thinx_yml_line#*=}
		thinx_yml_append=
		case "$thinx_yml_name" in
			*+) thinx_yml_append=1; thinx_yml_name=${thinx_yml_name%+} ;;
		esac
		case "$thinx_yml_name" in
			platformio_environment) [ -n "$thinx_yml_append" ] && [ -n "${platformio_environment+set}" ] || platformio_environment=$thinx_yml_value ;;
			platformio_target) [ -n "$thinx_yml_append" ] && [ -n "${platformio_target+set}" ] || platformio_target=$thinx_yml_value ;;
			environment_target) [ -n "$thinx_yml_append" ] && [ -n "${environment_target+set}" ] || environment_target=$thinx_yml_value ;;
		esac
	done <<THINX_YML_PAIRS
$thinx_yml_pairs
THINX_YML_PAIRS

	unset thinx_yml_pairs thinx_yml_line thinx_yml_name thinx_yml_value thinx_yml_append
	return 0
}

# --- per-device environment header --------------------------------------------
#
# When the device has environment variables, the THiNX API writes them to
# environment.json, and they become a C header of
#   #define ENVIRONMENT_<KEY> <JSON value>
# lines (keys sorted, upper-cased). The values may be credentials: nothing
# here prints them.

# env_header_target WORKSPACE TARGET: sets ENVOUT to the header to write, or
# to "" when there is none (the header is then skipped and the build goes on).
#  - TARGET set (thinx.yml environment: target:, e.g. src/environment.h): the
#    file WORKSPACE/TARGET. Refused when TARGET is absolute, has a ".."
#    component or no file name, when its directory is missing or resolves
#    (symlinks followed) outside WORKSPACE, or when it is a symlink or not a
#    regular file. A refused TARGET is not replaced by environment.h.
#  - TARGET empty: the first regular file named environment.h under
#    WORKSPACE, the build/ and .pio/ output directories excluded.
# Prints one line when there is no header. Plain POSIX sh. Returns 0.
env_header_target()
{
	ENVOUT=
	env_header_why=
	env_header_ws=$(cd "$1" 2>/dev/null && pwd -P) || env_header_ws=
	if [ -z "$env_header_ws" ]; then
		echo "Per-device environment header skipped: no workspace $1."
	elif [ -n "$2" ]; then
		case "$2" in
			/*) env_header_why="an absolute path" ;;
			..|../*|*/..|*/../*) env_header_why="a '..' path" ;;
			.|*/|*/.) env_header_why="no file name" ;;
		esac
		if [ -z "$env_header_why" ]; then
			case "$2" in
				*/*) env_header_dir=${2%/*} ;;
				*) env_header_dir=. ;;
			esac
			env_header_dir=$(cd "$env_header_ws" && cd -P "./$env_header_dir" 2>/dev/null && pwd -P) ||
				env_header_dir=
			case "$env_header_dir" in
				"") env_header_why="its directory does not exist" ;;
				"$env_header_ws"|"$env_header_ws"/*) ;;
				*) env_header_why="its directory is outside the workspace" ;;
			esac
		fi
		if [ -z "$env_header_why" ]; then
			env_header_path=$env_header_dir/${2##*/}
			if [ -L "$env_header_path" ]; then
				env_header_why="a symlink"
			elif [ -e "$env_header_path" ] && [ ! -f "$env_header_path" ]; then
				env_header_why="not a regular file"
			else
				ENVOUT=$env_header_path
			fi
		fi
		[ -z "$env_header_why" ] ||
			echo "Refusing environment target '$2' ($env_header_why); per-device environment header skipped."
	else
		env_header_path=$(find "$env_header_ws" \( -path "$env_header_ws/build" -o -path "$env_header_ws/.pio" \) -prune \
			-o -name environment.h -type f -print 2>/dev/null | head -n 1)
		ENVOUT=$env_header_path
		[ -n "$ENVOUT" ] ||
			echo "No environment target in thinx.yml and no environment.h in the workspace; per-device environment header skipped."
	fi
	unset env_header_why env_header_ws env_header_dir env_header_path
	return 0
}

# env_header_generate WORKSPACE ENVFILE TARGET [SKIPKEY...]: writes the header
# for ENVFILE (environment.json) to the file env_header_target picks. Keys
# SKIPKEY... are left out, and so are keys that are not made of letters,
# digits and _ (those are named in the log; values never are). Without
# ENVFILE nothing is written. An ENVFILE that is not a JSON object gives a
# header with no defines; jq's own errors are dropped, as they can quote the
# input. Returns 0.
env_header_generate()
{
	if [ ! -f "$2" ]; then
		echo "No environment.json found"
		return 0
	fi
	env_header_target "$1" "$3"
	[ -n "$ENVOUT" ] || return 0
	env_header_file=$2
	shift 3
	echo "Generating per-device environment headers to:" "$ENVOUT"
	if ! printf '%s\n' '/* This file is auto-generated. */' > "$ENVOUT"; then
		echo "Per-device environment header not written."
		unset env_header_file
		return 0
	fi
	if ! jq -r --arg skip "$*" '
		if type != "object" then error("not an object") else . end
		| ($skip | split(" ")) as $skipped
		| keys[] as $k
		| select(any($skipped[]; . == $k) | not)
		| select($k | test("^[A-Za-z0-9_]+$"))
		| "#define ENVIRONMENT_\($k | ascii_upcase) \(.[$k] | tojson)"
	' "$env_header_file" >> "$ENVOUT" 2>/dev/null; then
		echo "environment.json is not a JSON object; the per-device environment header has no defines."
	fi
	env_header_bad=$(jq -r '[keys[] | select(test("^[A-Za-z0-9_]+$") | not) | @json] | join(", ")' \
		"$env_header_file" 2>/dev/null) || env_header_bad=
	[ -z "$env_header_bad" ] ||
		echo "Skipping environment variables whose names are not letters, digits and _: $env_header_bad"
	unset env_header_file env_header_bad
	return 0
}

# Config options you may pass via Docker like so 'docker run -e "<option>=<value>"':
# - KEY=<value>

export IDF_PATH=/root/esp/esp-idf
export PATH=$PATH:/root/esp/xtensa-esp32-elf/bin

echo "export PATH=$PATH:/root/esp/xtensa-esp32-elf/bin" > ~/.profile
echo "export IDF_PATH=/root/esp/esp-idf" > ~/.profile

if [[ -z "$WORKDIR" ]]; then
  cd $WORKDIR
else
  echo "No working directory given."
  true
fi

WORKSPACE=/opt/workspace
cd "$WORKSPACE"

#
# Build
#

# Parse thinx.yml config

YMLFILE=$(find /opt/workspace -name "thinx.yml" | head -n 1)

if [[ ! -f $YMLFILE ]]; then
  echo "No thinx.yml found"
  exit 1
else
  thinx_yml_load "$YMLFILE"

  # selected build environment
  if [ ! -z "${platformio_environment}" ]; then
    PIO_ENVIRONMENT="--environment ${platformio_environment}"
  fi

  # selected build target
  if [ ! -z "${platformio_target}" ]; then
    PIO_TARGET="--target ${platformio_target}"
  fi
fi

# Per-device environment header (see env_header_target): thinx.yml's
# environment: target:, else an environment.h in the workspace, else skipped.
# CPASS and CSSID are left out: they go into thinx.yml as devsec instead.

ENVFILE=$(find "$WORKSPACE" -name "environment.json" | head -n 1)
env_header_generate "$WORKSPACE" "$ENVFILE" "${environment_target}" CPASS CSSID

BUILD_TYPE='platformio'

if [[ -f "./sdkconfig" || -f "./sdkconfig.defaults" ]]; then
  echo "Found sdkconfig in workspace root, switching to ESP-IDF build."
  BUILD_TYPE='espidf'
elif [[ -f "./CMakeLists.txt" ]] && grep -q "tools/cmake/project.cmake" ./CMakeLists.txt; then
  echo "Found ESP-IDF CMakeLists.txt in workspace root, switching to ESP-IDF build."
  BUILD_TYPE='espidf'
fi

if [[ $BUILD_TYPE == "platformio" ]]; then
  if [[ ! -f "./platformio.ini" ]]; then
    echo "Incorrect workdir $(pwd)"
  else
    if [[ ! -z $(cat ./platformio.ini | grep -v "^;" | grep "framework" | grep "espidf") ]]; then
      echo "Found 'framework = espidf' in platformio.ini, switching to ESP-IDF build."
      BUILD_TYPE='espidf'
    fi
  fi
fi

if [[ $BUILD_TYPE != "platformio" ]]; then

  # ESP-IDF (CMake / idf.py) build — replaces the removed legacy GNU-Make system.
  export IDF_PATH="${IDF_PATH:-/root/esp/esp-idf}"
  # shellcheck source=/dev/null
  . "$IDF_PATH/export.sh"

  idf.py build

  mkdir -p /opt/workspace/build
  # idf.py emits the app image + elf at the build root; the bootloader and
  # partition-table binaries live in subdirectories and are excluded by the
  # non-recursive globs below.
  cp -vf build/*.bin /opt/workspace/build/firmware.bin
  cp -vf build/*.elf /opt/workspace/build/firmware.elf
  chmod 775 /opt/workspace/build/firmware.*

else

  platformio run $PIO_ENVIRONMENT $PIO_TARGET # --silent # suppressed progress reporting

  if [[ -d build ]]; then
    rm -rf build
  fi

  mkdir build

  cd ./.pio/build/

  # WARNING! Currently supports only one simultaneous
  # build-environment and overwrites OUTFILE(s) with recents.

  for dir in $(ls -d */); do
    if [[ -d $dir ]]; then
      pushd $dir
      if [[ -f firmware.bin ]]; then
        if [[ ! -d /opt/workspace/build ]]; then
          mkdir -p /opt/workspace/build
        fi
        cp -vf firmware.bin /opt/workspace/build/firmware.bin
        if [[ -f firmware.elf ]]; then
          cp -vf firmware.elf /opt/workspace/build/firmware.elf
        fi
        chmod 775 /opt/workspace/build/firmware.*
      fi
      popd
    fi
  done

fi

RESULT=$?

echo ""

# Report build status using logfile
if [[ $RESULT == 0 ]]; then
  echo "THiNX BUILD SUCCESSFUL."
else
  echo "THiNX BUILD FAILED: $?"
fi
