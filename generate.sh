#!/bin/sh
#
# Regenerate this opam repository from the forks.
#
# Each fork's opam files are copied in as <name>.<upstream version>+hvf.<N>,
# with a url pointing at the fork's current commit. Bump a fork's N when its
# commits change what gets installed, so that opam upgrades it. Run it after committing
# to any fork, then `opam update hvf-mac`.
#
# FORKS_DIR    directory holding the fork checkouts (default: ..)
# FORKS_URL    base URL the sources are fetched from, ending in '/'; the fork
#              directory name is appended (default: git+https://github.com/rococompute/)
#
set -eu

cd "$(dirname "$0")"
FORKS_DIR="$(cd "${FORKS_DIR:-..}" && pwd)"
FORKS_URL="${FORKS_URL:-git+https://github.com/rococompute/}"
case "${FORKS_URL}" in */) ;; *) echo "FORKS_URL must end in /" >&2; exit 2 ;; esac

# fork directory | upstream version | N | opam files (relative to the fork)
FORKS="
solo5|0.13.0|3|opam/solo5.opam
ocaml-solo5|1.3.4|2|ocaml-solo5.opam
mirage|4.11.2|1|mirage.opam mirage-runtime.opam
ocaml-gmp|6.3.0-1|1|gmp.opam
mirage-crypto|2.4.1|4|mirage-crypto.opam mirage-crypto-rng.opam mirage-crypto-rng-mirage.opam mirage-crypto-rng-mkernel.opam mirage-crypto-pk.opam mirage-crypto-ec.opam
"

stage="$(mktemp -d .generate.XXXXXX)"
trap 'rm -rf "${stage}"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "${stage}/packages"

echo "${FORKS}" | while IFS='|' read -r fork version rev files; do
    [ -n "${fork}" ] || continue
    checkout="$(cd "${FORKS_DIR}/${fork}" && pwd -P)"
    [ "$(git -C "${checkout}" rev-parse --show-toplevel)" = "${checkout}" ] || {
        echo "error: ${fork} is not an initialized checkout" >&2
        exit 2
    }
    commit="$(git -C "${FORKS_DIR}/${fork}" rev-parse HEAD)"
    if [ -n "$(git -C "${FORKS_DIR}/${fork}" status --porcelain \
            --untracked-files=no)" ]; then
        echo "warning: ${fork} has uncommitted changes, using ${commit}" >&2
    fi
    for f in ${files}; do
        name="$(basename "${f}" .opam)"
        dir="packages/${name}/${name}.${version}+hvf.${rev}"
        mkdir -p "${stage}/${dir}"
        # Drop fields that only make sense in a source tree.
        # Read the committed metadata, matching the pinned source revision.
        git -C "${checkout}" show "${commit}:${f}" > "${stage}/source.opam"
        sed '/^version:/d' "${stage}/source.opam" > "${stage}/${dir}/opam"
        cat >> "${stage}/${dir}/opam" <<EOM
url {
  src: "${FORKS_URL}${fork}#${commit}"
}
EOM
        echo "${dir} <- ${fork}@${commit}"
    done
done
rm -rf packages
mv "${stage}/packages" packages
printf 'opam-version: "2.0"\n' > repo
