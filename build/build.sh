#!/usr/bin/env bash
# build/build.sh — build fedora-gnome-game-bootc-ewt locally (or on VPS) with buildah.
#
# Usage:
#   ./build/build.sh                # build only
#   ./build/build.sh --push         # build and push to ${REGISTRY}/${REGISTRY_NAMESPACE}/${IMAGE}
#   FEDORA_VERSION=45 ./build/build.sh --push
#
# Env vars:
#   FEDORA_VERSION       (default 45)                       — silverblue tag
#   REGISTRY             (default ghcr.io)                  — registry host
#   REGISTRY_NAMESPACE   (default dverdonschot)             — owner / org under REGISTRY
#   IMAGE                (default fedora-gnome-game-bootc-ewt)
#   PLATFORM             (default linux/amd64)
#   LINT_SKIP            (default --skip=var-tmpfiles)      — set empty for full lint
#                        (see Containerfile lint section: IMA EACCES on Fedora hosts)
#   REGISTRY_USER        (optional; non-interactive login)
#   REGISTRY_TOKEN       (optional; non-interactive login; GHCR PAT, Quay robot, …)
#
# Auth for --push:
#   - If REGISTRY_USER + REGISTRY_TOKEN are set: non-interactive `podman login`.
#   - Else: interactive prompt (skipped if no TTY / running in CI without creds).
#
# Requires: buildah, podman (for push), skopeo (alternative push).

set -euo pipefail

FEDORA_VERSION="${FEDORA_VERSION:-45}"
LINT_SKIP="${LINT_SKIP:---skip=var-tmpfiles}"
REGISTRY="${REGISTRY:-ghcr.io}"
REGISTRY_NAMESPACE="${REGISTRY_NAMESPACE:-dverdonschot}"
IMAGE="${IMAGE:-fedora-gnome-game-bootc-ewt}"
PLATFORM="${PLATFORM:-linux/amd64}"

TAG="${FEDORA_VERSION}"
FULL_IMAGE="${REGISTRY}/${REGISTRY_NAMESPACE}/${IMAGE}:${TAG}"

PUSH=0
[[ ${1:-} == "--push" ]] && PUSH=1

cd "$(dirname "$0")/.."
ROOT="$(pwd)"

echo "==> buildah bud ${FULL_IMAGE} (fedora-${FEDORA_VERSION})"
buildah bud \
    --isolation=chroot \
    --platform="${PLATFORM}" \
    --build-arg "FEDORA_VERSION=${FEDORA_VERSION}" \
    --build-arg "LINT_SKIP=${LINT_SKIP}" \
    --tag "${FULL_IMAGE}" \
    --file Containerfile \
    "${ROOT}"

if [[ ${PUSH} -eq 1 ]]; then
    # ---- Authentication ----
    # Prefer non-interactive env vars. Fall back to a prompt so a local dev
    # doesn't have to hand-craft a `podman login` line. CI without creds is
    # a configuration error — surface it loudly rather than push an
    # unauthenticated image that 401s anyway.
    if [[ -n "${REGISTRY_USER:-}" && -n "${REGISTRY_TOKEN:-}" ]]; then
        echo "==> podman login ${REGISTRY} (from env)"
        printf '%s' "${REGISTRY_TOKEN}" | podman login "${REGISTRY}" -u "${REGISTRY_USER}" --password-stdin
    elif [[ -t 0 && -t 1 ]]; then
        echo "==> podman login ${REGISTRY} (interactive)"
        podman login "${REGISTRY}"
    else
        echo "ERROR: --push requested but no credentials available." >&2
        echo "       Set REGISTRY_USER and REGISTRY_TOKEN, or run interactively." >&2
        exit 1
    fi

    echo "==> podman push ${FULL_IMAGE}"
    podman push "${FULL_IMAGE}"
    # Also push :latest pointing at the same image for ergonomics.
    podman tag "${FULL_IMAGE}" "${REGISTRY}/${REGISTRY_NAMESPACE}/${IMAGE}:latest"
    podman push "${REGISTRY}/${REGISTRY_NAMESPACE}/${IMAGE}:latest"
fi

echo "==> done. Either rebase an existing Fedora Atomic install:"
echo "    sudo rpm-ostree rebase ostree-unverified-registry:${FULL_IMAGE}"
echo "    or install to disk:"
echo "    sudo bootc install to-disk --filesystem=xfs ostree-unverified-registry:${FULL_IMAGE} /dev/sdX"
