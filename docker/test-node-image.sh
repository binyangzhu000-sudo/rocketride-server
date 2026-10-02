#!/bin/sh
# Checks a node image as a task gets it: capabilities dropped, no network for
# the installs. Used by `nodes:test-container` and by the release workflow
# before the image is signed.
#
#   docker/test-node-image.sh <image>
set -eu

image=${1:?usage: test-node-image.sh <image>}

run() {
    docker run --rm --cap-drop ALL "$@"
}

# The engine is non-dumpable (it needs the dropped capabilities a task has), and
# depends() accepts the shipped constraints as they are. A hash mismatch means
# every task recompiles them, against whatever PyPI holds that day, and the
# cache stops matching what tasks install.
echo "Probing the engine in $image..."
run "$image" ./engine -c "
import os
from depends import _find_requirement_files, _find_override_files, _compute_hash
assert os.stat('/proc/self/environ').st_uid == 0, 'engine is dumpable'
import tempfile
from ai.constants import CONST_TASK_DATA_PATH
tempfile.NamedTemporaryFile(dir=CONST_TASK_DATA_PATH).close()
stored = open('cache/requirements.hash').read().strip()
now = _compute_hash(_find_requirement_files() + _find_override_files())
assert stored == now, f'shipped constraints are stale in a container: {stored} != {now}'
print('image probe ok')
"

# Nodes whose dependencies must install from the baked cache with no network.
# Between them: opencv pulled in transitively (mediapipe, img2table), the
# onnxruntime-gpu / ctranslate2 / av stack, and an override (crewai's mcp cap).
failed=''
for node in face_detection ocr audio_transcribe agent_crewai; do
    echo "Installing $node offline from the cache..."
    if ! run --network none -e UV_OFFLINE=1 "$image" ./engine -c \
            "from depends import depends; depends('nodes/$node/requirements.txt')"; then
        failed="$failed $node"
    fi
done

if [ -n "$failed" ]; then
    echo "FATAL: did not install offline:$failed"
    exit 1
fi
echo "$image: engine probe and offline installs passed"
