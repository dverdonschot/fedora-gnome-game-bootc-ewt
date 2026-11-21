# bootc documentation index

Curated references for building and maintaining this image, plus the
project-local lessons learned (the stuff that cost hours and isn't obvious
from upstream docs). Keep this list short — only what we actually rely on.

## Authoritative

| Source | What to use it for |
| --- | --- |
| [bootc docs](https://bootc-dev.github.io/bootc/) | Image format, install/upgrade model, `bootc container lint`, install config (kargs) |
| [bootc images discussion](https://github.com/containers/bootc/discussions/802) | Which base images are bootc-suitable; dnf-in-container pattern |
| [Fedora bootc base image](https://quay.io/repository/fedora/fedora-bootc) / [silverblue](https://quay.io/repository/fedora-ostree-desktops/silverblue) | Base images (quay.io); silverblue = GNOME preinstalled |
| [Changes/DNFAndBootcInImageModeFedora](https://fedoraproject.org/wiki/Changes/DNFAndBootcInImageModeFedora) | Why `dnf5` in the Containerfile, not `rpm-ostree install` |
| [ostree native containers](https://www.fedoraproject.org/wiki/Changes/OstreeNativeContainerStable) | Rebase/upgrade model, `ostree-unverified-registry:` vs `ostree-image-signed:` |
| [ublue-os/image-template](https://github.com/ublue-os/image-template) | Reference shape: GH Actions workflow, cache mounts, `bootc container lint`, rechunk |
| [coreos/rpm-ostree#3738](https://github.com/coreos/rpm-ostree/issues/3738) | Why `rpm-ostree install` fails inside container builds |
| [bootc kernel args](https://bootc-dev.github.io/bootc/install/kernel-args.html) | `/usr/lib/bootc/install/*.toml` — applies at `bootc install` only |
| [cosign](https://docs.sigstore.dev/cosign/keyless/) | Keyless signing on CI; `ostree-image-signed:` on the client |

## Key facts (memorize these)

- **`/var` is only seeded from the image on first install.** Never bake state
  you expect to update into `/var`. Flatpaks live in `/var` — baked ones land
  on fresh installs; after a rebase run `build/install-flatpaks.sh` once.
- **`/usr` is the atomic image; `/etc` is merged per bootc's config model.**
  Package content goes in `/usr` (via dnf5); preset files in
  `/usr/lib/systemd/system-preset/` are the supported way to flip boot defaults.
- **Kargs come from `/usr/lib/bootc/install/*.toml`** and apply at
  `bootc install` time. A `rpm-ostree rebase` keeps the deployment's existing
  kernel args — apply manually once if needed (see README).
- **`ostree container commit` at the end of each RUN** that changes packages/
  files — required for ostree-native-container images.
- **Cache mounts** (`--mount=type=cache,dst=/var/cache,dst=/var/log`) keep the
  image layer clean and speed rebuilds. Do **not** tmpfs-mount `/tmp` on
  rootless buildah (containers/buildah#1240 — EACCES on librepo mkstemp).
- **Weekly scheduled rebuild** is the update mechanism for the base: the tag
  `silverblue:45` floats; CI pulls the new digest every Monday.
- **Machine-side auto-update = config + timer.** `AutomaticUpdatePolicy=stage`
  in the image's `/etc/rpm-ostreed.conf` plus a preset-enabled
  `rpm-ostreed-automatic.timer` (preset files match lexicographically,
  first match wins — ship it as `80-*.preset` to beat 90's `disable *`).
  Stock cadence: `OnBootSec=1h`, `OnUnitInactiveSec=1d`. Verify with
  `rpm-ostree status` → `AutomaticUpdates: stage`.
- **Delta updates**: a rechunker (rpm-ostree rechunk / chunkah) shrinks
  upgrade payloads. Not used here yet — reconsider when upgrade bandwidth
  hurts.

## Local lessons learned (this repo)

1. Rootless `buildah bud` needs `--isolation=chroot` on ostree hosts;
   rootful works either way.
2. `bootc container lint` hits IMA EACCES on `/sys/kernel/security/ima/...`
   when run from a chroot-isolated rootless build on a Fedora host — hence
   `LINT_SKIP=--skip=var-tmpfiles` locally; CI (GitHub runners, Ubuntu) runs
   the full lint.
3. `/usr/local` is a symlink to `/var/usrlocal` on Fedora Atomic — COPY files
   into it one-by-one; recursive COPY refuses to replace the symlink.
4. Flatpaks are deliberately **not** baked into the image: they live in
   `/var`, which bootc only seeds on first install and never updates on
   upgrade — baked copies would freeze at build-day versions and miss rebases.
   `build/flatpak-list.txt` + `build/install-flatpaks.sh` is the flow.
5. Fedora `nix` + `nix-daemon` rpms ship `nix-daemon.socket/.service` and
   `sysusers.d/nix.conf`; preset the units in the image, users appear at boot.
