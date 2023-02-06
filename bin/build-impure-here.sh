set -eu

cube="$1"
pkg="$(basename -- "$2")"
pkg_dirname="$(dirname -- "$2")"
if [[ "$pkg_dirname" == "." ]]; then
    out_prefix=""
else
    out_prefix="$pkg_dirname/"
fi

# Files and directories:
#
# ./$pkg.rec
# ./$pkg-build/
# ./$pkg-stage/
# $cube/$out_prefix$pkg/

here="$PWD"
mkdir -- "$pkg-build"
pushd -- "$pkg-build"
# rec cube stage out config
bash -- "$here/$pkg/build" \
    "$here/$pkg.rec" "$cube" "$here/$pkg-stage" "$out_prefix$pkg" "$here/config"
popd
mv -T -- "$pkg-stage" "$cube/$out_prefix$pkg"
cp -- "$pkg.rec" "$cube/rec/"
cp -r -- "$pkg" "$cube/rec/"
