#!/bin/sh
#
# Regenerate this opam repository from the forks.
#
# Each fork's opam files are copied in as <name>.<upstream version>+hvf.<N>,
# with a url pointing at the fork's current commit. Run it after committing
# to any fork, then `opam update hvf-mac`.
#
# FORKS_DIR    directory holding the fork checkouts (default: ..)
# FORKS_URL    base URL the sources are fetched from, ending in '/'; the fork
#              directory name is appended (default: git+file://$FORKS_DIR/)
#
set -eu

cd "$(dirname "$0")"
FORKS_DIR="$(cd "${FORKS_DIR:-..}" && pwd)"
FORKS_URL="${FORKS_URL:-git+file://${FORKS_DIR}/}"
HVF_REV=1

# fork directory | upstream version | opam files (relative to the fork)
FORKS="
solo5|0.13.0|opam/solo5.opam
ocaml-solo5|1.3.4|ocaml-solo5.opam
mirage|4.11.2|mirage.opam mirage-runtime.opam
ocaml-gmp|6.3.0-1|gmp.opam
mirage-crypto|2.4.1|mirage-crypto.opam mirage-crypto-rng.opam mirage-crypto-rng-mirage.opam mirage-crypto-rng-mkernel.opam mirage-crypto-pk.opam mirage-crypto-ec.opam
"

rm -rf packages
printf 'opam-version: "2.0"\n' > repo

echo "${FORKS}" | while IFS='|' read -r fork version files; do
    [ -n "${fork}" ] || continue
    commit="$(git -C "${FORKS_DIR}/${fork}" rev-parse HEAD)"
    if [ -n "$(git -C "${FORKS_DIR}/${fork}" status --porcelain \
            --untracked-files=no)" ]; then
        echo "warning: ${fork} has uncommitted changes, using ${commit}" >&2
    fi
    for f in ${files}; do
        name="$(basename "${f}" .opam)"
        dir="packages/${name}/${name}.${version}+hvf.${HVF_REV}"
        mkdir -p "${dir}"
        # Drop fields that only make sense in a source tree.
        grep -v '^version:' "${FORKS_DIR}/${fork}/${f}" > "${dir}/opam"
        cat >> "${dir}/opam" <<EOM
url {
  src: "${FORKS_URL}${fork}#${commit}"
}
EOM
        echo "${dir} <- ${fork}@${commit}"
    done
done
