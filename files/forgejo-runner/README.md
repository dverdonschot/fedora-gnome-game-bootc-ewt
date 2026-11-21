# Forgejo Runner on the ODROID-H3+ (Intel N100)

The image ships the runner binary, a user-mode systemd unit, and a
setup script. The unit is **not enabled** and **not started** until
you choose to authorize it.

## Owner-only steps to bring it online

1. **Rebase to the new image.**
   ```bash
   sudo rpm-ostree upgrade
   systemctl reboot
   ```
   The image packages `forgejo-runner`.

2. **Get a registration token from the Forgejo web UI.**
   Site Admin → Actions → Runners → **Create new runner**. Copy the
   single opaque token it shows you.

3. **Paste the token into place.**
   ```bash
   mkdir -p ~/.config/forgejo/runners/h3plus
   install -m 0600 /dev/null ~/.config/forgejo/runners/h3plus/token
   ${EDITOR:-vi} ~/.config/forgejo/runners/h3plus/token
   ```
   Paste the token from step 2.

4. **Make sure you're in the GPU groups.** The runner will warn
   you if not, but smoke tests go easier if these are present
   before `--enable`:
   ```bash
   groups | grep -E '\b(render|video)\b' || \
     sudo usermod -aG render,video "$USER"
   # log out and back in once after this.
   ```

5. **Run the setup.**
   ```bash
   /usr/local/bin/setup-forgejo-runner.sh --enable
   ```
   This is idempotent — re-running it does no harm. `--enable`
   finalizes the config, registers the runner with Forgejo, and
   turns the unit on. Without `--enable` it just stages files and
   bails out without starting anything.

The Forgejo Runners page should now show `h3plus-runner` online with
labels `self-hosted,linux,x86_64,host=h3plus,size=large`.

## Verifying

```bash
systemctl --user status forgejo-runner.service
journalctl --user -u forgejo-runner.service -f
ls /dev/dri            # renderD128 — the Intel iGPU render node
```

Inside a CI job (after a real workflow runs):
- `/dev/dri/renderD128` should be visible.
If GPU access fails, see **GPU troubleshooting** below.

## What the labels mean

| Label | Why |
|---|---|
| `self-hosted` | distinguishes from forgejo-hosted runners. |
| `linux` | OS. |
| `x86_64` | arch (ODROID-H3+ is Intel N100). |
| `host=h3plus` | target runners from specific workflows. |
| `size=large` | capacity=1 today, but signals capacity-tier. |

## How to disable or remove

```bash
# Stop the unit but leave config + token in place:
systemctl --user disable --now forgejo-runner.service

# Or wipe the registration so it disappears from the Forgejo UI:
rm -f ~/.config/forgejo-runner/.runner
rm -f ~/.local/share/forgejo-runner/.runner
systemctl --user daemon-reload
```

To re-enable after a `rpm-ostree` upgrade that touched `forgejo-runner`
or podman, just re-run step 5.

## GPU troubleshooting

The runner passes `--device /dev/dri` to each job container. If a
job cannot open the render node:

1. Confirm `/dev/dri/renderD128` exists on the host.
2. Confirm the user is in `render` and `video` groups (step 4 above).
3. If still failing, set environment variable
   `FORGEJO_RUNNER_EXTRA_OPTIONS="--cap-add SYS_PTRACE"` in
   `~/.config/forgejo-runner/env` and re-run
   `setup-forgejo-runner.sh --enable`.

## Configuration layout

- **Token** — `~/.config/forgejo/runners/h3plus/token` (mode 0600). The
  script never overwrites an existing token; rotate by deleting it
  and re-running the script.
- **Rendered config** — `~/.config/forgejo-runner/config.yaml`,
  regenerated from `/etc/forgejo-runner/config.yaml.j2` on each
  setup run.
- **Env file** — `~/.config/forgejo-runner/env`, sets
  `DOCKER_HOST` and `FORGEJO_RUNNER_TOKEN_FILE`.
- **Workdir** — `/var/tmp/forgejo-runner/work` (NOT `/var/lib/...`,
  so it survives an rpm-ostree rollback).

## Security notes

- The systemd unit uses `ProtectSystem=full` and `ProtectHome=read-only`
  with `AF_UNIX AF_INET AF_INET6 AF_NETLINK` restricted. It cannot
  reach the network beyond what it needs to talk to Forgejo and the
  Docker socket.
- The registration token is sensitive: anyone with it can register
  a runner on this Forgejo instance. Treat the file like an
  `~/.ssh/id_*` key.
- The runner's container options pass `--device /dev/dri`
  (privileged=false), the minimum needed for GPU access. A malicious
  workflow gets the render node but not arbitrary host privileges.
