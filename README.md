# Installing vesslet

vesslet runs local Kubernetes sandboxes ("vessels") for your projects and a team of AI agents that work on your tasks, all on your own machine. This guide takes you from nothing to an open dashboard in about 10 minutes.

## 1. Before you start

You need:

| | macOS | Linux | Windows |
|---|---|---|---|
| System | macOS on Apple Silicon or Intel | x86-64 or ARM64 | Windows 10/11, x86-64 |
| Docker | [Docker Desktop](https://www.docker.com/products/docker-desktop/), **running** | Docker Engine, your user in the `docker` group | [Docker Desktop](https://www.docker.com/products/docker-desktop/), **running** |
| Package manager (recommended) | [Homebrew](https://brew.sh) | — | winget (built into Windows 11) |
| Disk / memory | ~10 GB free, 8 GB RAM or more | same | same |

You don't need admin rights for vesslet itself. Everything else it needs, the installer offers to install for you: **k3d, kubectl and the GitHub CLI** are downloaded straight from their official releases (checksum-verified) into vesslet's own folder on every OS — no Homebrew or winget needed; Claude Code uses its own official installer, and Docker you install yourself (step above).

> **Linux:** after installing Docker, run `sudo usermod -aG docker $USER` and log out and back in, so Docker works without `sudo`.

## 2. Install

**macOS / Linux** — in a terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/vesslet/vesslet-releases/main/install.sh | sh
```

**Windows** — in **PowerShell** (Start → "PowerShell"; the prompt starts with `PS C:\…>`), not the Command Prompt:

```powershell
irm https://raw.githubusercontent.com/vesslet/vesslet-releases/main/install.ps1 | iex
```

From the Command Prompt (`cmd`) instead — `irm is not recognized` means you're there:

```cmd
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/vesslet/vesslet-releases/main/install.ps1 | iex"
```

What happens:

1. The right build for your machine is downloaded and checked against its published checksum. If the check fails, nothing is installed.
2. vesslet goes into `~/.vesslet/bin` (Windows: `%USERPROFILE%\.vesslet\bin`) and, on macOS/Linux, a link into `~/.local/bin`.
3. **`vesslet setup` runs**: it lists the tools that are missing and asks before installing each one (`Install it with "brew install k3d"? [Y/n]`). Press Enter to accept, `n` to skip. Anything skipped is printed with how to install it yourself.
4. When Docker is running and k3d and kubectl are present, it **starts the harbor** (your local Kubernetes) and the background companion, and prints the dashboard address.

The end of a successful install looks like this:

```
[✓] vesslet is ready — dashboard: http://vesslet-harbor.localhost
```

### If `vesslet` isn't found afterwards

The installer tells you when `~/.local/bin` isn't on your PATH yet and prints the line to add, for example:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && export PATH="$HOME/.local/bin:$PATH"
```

On Windows, open a **new** PowerShell window — the PATH change only applies to new windows.

Check:

```bash
vesslet version
# vesslet v0.1.2 (darwin/arm64)
```

## 3. Sign in to the tools vesslet uses

These need your own accounts, so the installer can't do them for you:

```bash
claude          # Claude Code — follow the login prompt once, then exit
gh auth login   # GitHub CLI — needed to open pull requests and follow their CI
```

## 4. First steps

1. **Open the dashboard:** http://vesslet-harbor.localhost
2. **Add a project** — any git repository on your machine:
   ```bash
   vesslet project add ~/code/my-app
   ```
   It appears under **Projects** in the dashboard, with a starter `.vesslet.yaml` describing how to run the app.
3. **Create a Task** in the dashboard (**Tasks → + New Task**), pick the project, describe what you want, and launch a vessel or a team from it.

Handy commands:

```bash
vesslet harbor status   # is the local cluster up?
vesslet vessel list     # running vessels
vesslet doctor          # check every prerequisite
vesslet setup           # re-check tools and start the harbor again
```

## 5. Updating

vesslet tells you once a day, in the terminal and on the dashboard, when a new version is out. To update:

```bash
vesslet update
```

It refuses while agents are working (an update restarts the companion and would cut them off) — wait for them, or run `vesslet update --force`. If an update is interrupted, the previous version keeps working.

Running the install command again also upgrades in place; your projects, tasks and settings in `~/.vesslet` are kept.

## 6. Installing a specific version

```bash
curl -fsSL https://raw.githubusercontent.com/vesslet/vesslet-releases/main/install.sh | sh -s -- --version v0.1.0
```

Windows: `$env:VESSLET_VERSION = "v0.1.0"` before the install command. All versions: https://github.com/vesslet/vesslet-releases/releases

Other options: `--yes` installs every missing tool without asking (useful in scripts), `--no-setup` only installs the vesslet binary.

## 7. Troubleshooting

| Problem | What to do |
|---|---|
| `irm is not recognized` (Windows) | You're in the Command Prompt — open PowerShell, or use the `powershell -Command "…"` line from step 2. |
| Just after a release, the installer picks the previous version | GitHub caches for up to 5 minutes — run the command again a few minutes later, or `vesslet update`. |
| `checksum mismatch` | The download was altered or corrupted. Nothing was installed — run the command again. If it repeats, check for a proxy rewriting downloads. |
| `download failed` / `retrying (2/3)` | A network hiccup; the installer retries by itself. Behind a corporate proxy, make sure `curl` can reach `github.com` and `objects.githubusercontent.com` (`HTTPS_PROXY` must be set in your shell). |
| Pods stuck on `ImagePullBackOff` with `x509: certificate signed by unknown authority` (corporate network) | Your network inspects HTTPS with its own root certificate. vesslet copies the root your machine trusts Docker Hub with into the harbor when it's **created** — so recreate it: `vesslet harbor remove`, then `vesslet setup`. If it still fails, export your company's root certificate (ask IT, or from your system's certificate store) as a `.crt` file into `~/.vesslet/certs/` and recreate the harbor again. |
| `EOF` from `https://host.docker.internal:…` (Windows) | A harbor created by vesslet before v0.1.6 — recreate it: `vesslet harbor remove`, then `vesslet setup`. |
| `Docker isn't running` | Start Docker Desktop (Linux: `sudo systemctl start docker`), then `vesslet setup`. |
| `The harbor isn't started yet` | A required tool (Docker, k3d, kubectl) is still missing — install it as printed, then `vesslet setup`. |
| Dashboard doesn't open | `vesslet harbor status`; if the harbor is down, `vesslet setup`. |
| `vesslet update` refuses | Agents are working. Wait, or `vesslet update --force`. |
| `this vesslet build can't build the harbor's images` | You're running a self-built binary outside the source checkout — install a release with the command above. |

Still stuck? Run `vesslet doctor` and send its output to the vesslet maintainers.

## 8. Uninstalling

```bash
vesslet harbor remove        # delete the local cluster and every vessel
rm -rf ~/.vesslet ~/.local/bin/vesslet
```

Windows: `vesslet harbor remove`, then delete `%USERPROFILE%\.vesslet` and remove it from your user PATH (Settings → System → About → Advanced system settings → Environment Variables).
