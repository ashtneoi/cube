#!/usr/bin/env bash
set -eu

# build-impure.sh recipe build_dir stage threads

recipe="${1:?Error: no recipe}"
recipe="$(realpath -- "$recipe")"
[[ "$recipe" == */ ]] && { echo >&2 "Error: recipe ends in a slash"; exit 100; }
[[ "$recipe" == -* ]] && { echo >&2 "Error: recipe looks like an option"; exit 100; }

build_dir="${2:?Error: no build_dir}"
[[ -e "$build_dir" ]] && { echo >&2 "Error: build_dir exists"; exit 100; }

stage="${3:?Error: no stage}"
stage="$(realpath -- "$stage")"
[[ -e "$stage" ]] && { echo >&2 "Error: stage exists"; exit 100; }
if [[ "$stage" != */ ]]; then
    stage="$stage/"
fi

threads="${4:?Error: no threads}"

cube="$(sed -En -- 's:^c (.+):\1:p' "$recipe.rec")"
: ${cube:?Error: no cube}
[[ "$cube" != */ ]] && { echo >&2 "Error: cube doesn't end in a slash"; exit 100; }

package_id="$(cat -- "$recipe.rec" <(nar "$recipe") | sha3-256sum | base24 -p)"
: ${package_id:?Error: no package_id}

output_dir="${cube}_impure/$package_id"

interpreter_alias="$(sed -En -- 's:^b ([^ ]+) .*:\1:p' "$recipe.rec")"
: ${interpreter_alias:?Error: no interpreter_alias}

interpreter_rel_path="$(sed -En -- 's:^b [^ ]+ (.*):\1:p' "$recipe.rec")"
: ${interpreter_rel_path:?Error: no interpreter_rel_path}

if [[ "$interpreter_alias" == - ]]; then
    interpreter="$interpreter_rel_path"
else
    interpreter=
    while IFS=' ' read -r alias id; do
        if [[ "$alias" == "$interpreter_alias" ]]; then
            interpreter="$cube$id/$interpreter_rel_path"
            break
        fi
    done < <(sed -En -- 's:^i ([^ ]+ .+):\1:p' "$recipe.rec")
    : ${interpreter:?Error: no interpreter}
fi

config="$PWD/config"
cat <<END >"$config"
staging-dir $stage
output-dir $output_dir
threads 2
END

mkdir -p -- "$build_dir"
pushd -- "$build_dir"
"$interpreter" "$recipe/build" "$config" "$recipe.rec"
popd
