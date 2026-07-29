# Test evidence requirements

Every `TEST.md` must name the applicable source branch, ordered phases, causal barriers,
pass/fail gates, repetition mode and required artifacts. Every `run.sh` must append one JSON
record per gate to `assertions.jsonl`.

## Minimum provenance

Keep these fields for every run:

- selected source branch and exact commit derived from clean local HEAD;
- input command, committed script paths and SHA-256 values;
- container name and ID, image tag and digest, and base image;
- selected dependency roots plus actual package versions and imported module paths;
- model path, GPU IDs, port range, start/finish time and exit code.

Do not automatically collect image-internal SGLang commit, CUDA/PyTorch/driver inventory,
mounts, shm, or a comparison of system packages with task packages. Add such diagnostics only
when a concrete failure makes them relevant.

## Minimum behavioral evidence

The contract must select the applicable items and state exact expected values:

- initial, fault, recovery and final service state;
- HTTP status and saved response body for each meaningful request;
- owned PID/PGID and process-count assertions around fault and cleanup;
- exact output oracle or another explicit correctness criterion;
- source cleanliness and absence of task-owned processes after cleanup.

Save every parallel response separately before aggregation. A successful run requires exit
zero, at least one structured assertion, and all assertions passing.

## Repetition

Declare whether a case needs a single run, warm repetition or cold repetition. Cold repetitions
must use distinct run names and artifact directories. Preserve every failed and successful
attempt; never move a previous result aside implicitly or overwrite it.
