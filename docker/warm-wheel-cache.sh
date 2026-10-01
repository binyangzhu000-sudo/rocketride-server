#!/bin/sh
# Warms $UV_CACHE_DIR with the wheels a task run installs. Run inside the node
# image build, from /opt/rocketride.
#
# The resolution is the engine's own: depends() compiles every requirement file
# into cache/constraints.txt and installs each file against it, with the
# overrides and excludes it computes. This script installs each file the same
# way, into a throwaway --target instead of site-packages, so the cache holds
# exactly what a run asks for. The image ships cache/constraints.txt, so a run
# reuses that resolution instead of recompiling against a newer PyPI.
#
# - The engine is the interpreter: cp312 / manylinux wheels for this glibc.
# - No torch: the run never installs it (the model server does inference), and
#   its CUDA build alone is gigabytes. Excluded transitively too.
# - Best effort: a file that does not resolve here does not install at run time
#   either. Each one is listed at the end.
set -eu

# The engine resolves: cache/constraints.txt and cache/overrides-combined.txt,
# from every requirement file. In the node image engine-base already did it
# while installing the baseline, so this finds the hash unchanged and returns.
./engine -c "from depends import ensure_constraints; ensure_constraints()"

# The excludes file depends() passes to every install (uv; onnxruntime on Linux).
engine_excludes=$(./engine -c "from depends import _write_excludes_file; print(_write_excludes_file())" | tail -n 1)

constraints=cache/constraints.txt
overrides=cache/overrides-combined.txt
if [ ! -s "$constraints" ]; then
    echo "FATAL: the engine produced no $constraints."
    exit 1
fi
set -- -c "$constraints"
if [ -s "$overrides" ]; then
    set -- "$@" --override "$overrides"
fi

excludes=$(mktemp)
cat "$engine_excludes" > "$excludes"
printf 'torch\ntorchvision\ntorchaudio\n' >> "$excludes"

total=0
failed=''
for req in $(find nodes ai -name 'requirement*.txt' | sort); do
    case "$req" in
        ai/common/torch/*) continue ;;
    esac
    total=$((total + 1))
    target=$(mktemp -d)
    if ! ./bin/uv pip install --quiet \
            -r "$req" \
            "$@" \
            --python ./engine \
            --target "$target" \
            --index-strategy unsafe-best-match \
            --no-build-isolation \
            --excludes "$excludes"; then
        failed="$failed $req"
    fi
    rm -rf "$target"
done
rm -f "$excludes"

echo "Warmed from $total requirement files."
if [ -n "$failed" ]; then
    echo "Did not resolve (fails at run time too):"
    for req in $failed; do echo "  $req"; done
fi

# Fail closed on torch: a declaration change must not bring gigabytes back
# unnoticed. Top level of each unpacked wheel only: other packages carry
# subpackages named torch (google-cloud-aiplatform does).
torch=$(find "$UV_CACHE_DIR/archive-v0" -mindepth 2 -maxdepth 2 -type d \( -name torch -o -name nvidia -o -name triton \) -print)
if [ -n "$torch" ]; then
    echo "FATAL: torch reached the wheel cache:"
    echo "$torch" | head -20
    exit 1
fi

du -sh "$UV_CACHE_DIR"
