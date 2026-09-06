# GitHub transport smoke

Applicable to any clean committed source branch selected by the profile. CPU only;
no model, CUDA allocation, service ports or fault injection.

One bounded run: verify the checked-out source HEAD equals the invocation's expected
commit, write a deterministic binary payload and two structured assertions, then exit.
The caller must verify result exit 0, both assertions, exact Git input hashes and the
retrieved payload SHA256. Keep invocation, preparation log, result, assertions,
source/container provenance and control state. A summary omits the payload; fetch the
full output separately to validate archive transport. Never infer pass from exit alone.
