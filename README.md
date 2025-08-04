# Jenkins Service (Podman/Docker)

A self‑contained toolkit for running **Jenkins** in a root‑less container on any Linux host that supports **Podman** (preferred) or **Docker**.

* **Container‑first** — systemd unit starts Jenkins as an OCI container.
* **Zero‑touch bootstrap** — Groovy init scripts create an *admin* user and install an SSH key on first boot.
* **Plugin automation** — helper scripts generate a minimal, version‑pinned *plugins.txt* and resolve transitive dependencies.
* **CLI included** — `jenkins-cli.jar` is shipped so you can script against the controller once it is up.

> **Note**
> This project originally shipped an RPM workflow.  That packaging flow is not stable yet and has been **deliberately omitted** from this README.

---

## Directory layout

```
jenkins-service/
├── jenkins.service                 # systemd unit – drop into /etc/systemd/system
├── jenkins.sh                      # helper script: detects Podman/Docker & launches
├── Makefile                        # convenience targets (tarball, plugin diff, etc.)
├── jenkins-cli.jar                 # upstream CLI client (matches default TAG)
├── SOURCES/
│   ├── jenkins.sysconfig           # Environment overrides sourced by the unit
│   ├── plugins.txt                 # One plugin ID per line (comments allowed)
│   └── …                           # sudoers, secret stub, etc.
├── init.groovy.d/                  # First‑run Groovy hooks
│   ├── init_admin_user.groovy
│   └── setup_ssh_public_key.groovy
├── generate-jenkins-plugins-installlist.sh
├── resolve-plugin-versions.sh
├── minimalJenkinsCore.sh           # jq pipeline → minimal core + plugins
├── minimal-core.jq                 # jq filter used by the script above
├── compat.jq                       # jq filter for plugin‑compat matrix
├── find-plugins-upgrade-for.sh     # diff your current catalogue vs latest
├── LICENSE (MIT)
└── …
```

---

## Prerequisites

| Requirement                               | Notes                                                                                          |
| ----------------------------------------- | ---------------------------------------------------------------------------------------------- |
| **Podman ≥ 4.0** <br>or **Docker ≥ 20.x** | The helper script prefers Podman and aliases it to `docker` if necessary.                      |
| **systemd ≥ 245**                         | Needed for the service unit’s `Type=oneshot` + `ExecStartPre` pattern.                         |
| **curl & jq**                             | Required by the plugin management helper scripts.                                              |
| **Jenkins image**                         | Defaults to `jenkins/jenkins:2.516.1-lts-jdk17`; override via *VERSION* in the sysconfig file. |

---

## Quick start

1. **Clone or unpack** the *jenkins-service* directory somewhere under `/usr/local/share` (or any path you like).

2. **Install the systemd unit**

   ```bash
   sudo cp jenkins.service /etc/systemd/system/jenkins.service
   sudo cp -r SOURCES /etc/jenkins-service
   ```

3. **Adjust configuration**
   Edit `/etc/jenkins-service/jenkins.sysconfig` (or point the unit to a different file via `EnvironmentFile=`):

   ```ini
   VERSION=2.516.1          # Jenkins image tag
   HTTP_PORT=8080           # Host port → container 8080
   SSH_PORT=50000           # Host port → container 50000 (JNLP/SSH)
   PLUGIN_FILE=/etc/jenkins-service/plugins.txt
   ```

4. **Enable & start**

   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now jenkins.service
   # Logs
   journalctl -fu jenkins.service
   ```

   The unit launches the helper script which in turn pulls the image (if missing) and starts the container in the background.

5. **First login**

   * Open [http://localhost:8080](http://localhost:8080).
   * Username: **admin**.  The password is auto‑generated and printed once in the journal; search for `Jenkins initial password`.
   * The `init_admin_user.groovy` script resets the admin password to the one you provide via `JENKINS_ADMIN_PASSWORD` env (optional) and sets up CSRF crumbs.

---

## Customising plugins

1. **Edit `SOURCES/plugins.txt`** – one plugin ID per line; `#` comments allowed.
2. Run the helper to materialise a full install list with explicit versions:

   ```bash
   ./generate-jenkins-plugins-installlist.sh 2.516.1 > SOURCES/plugins.txt
   ```

   *Internally this pulls the update‑centre JSON, resolves the dependency graph, and pins each plugin to the latest compatible release.*
3. **Re‑deploy**: restart the service.  The container volume `/var/jenkins_home` persists plugins, so Jenkins will install/upgrade them on boot.

### Keeping up‑to‑date

* `resolve-plugin-versions.sh` — rebuilds the catalogue cache and tells you which of your pinned plugins are outdated.
* `find-plugins-upgrade-for.sh <core‑version> <plugins.txt>` — diff smart upgrades when you raise the Jenkins core version.

---

## jenkins.sh – what it does

```text
1. Detects Podman ➜ uses it; else falls back to Docker.
2. Creates a root‑less *podman machine* if required (handy on macOS / WSL2).
3. Ensures the image `jenkins/jenkins:${VERSION}-lts` is present.
4. Runs the container with:
   * Named volume `jenkins_home` for persistence.
   * Published ports `$HTTP_PORT:$HTTP_PORT` and `$SSH_PORT:50000`.
   * `--restart=always` for resilience.
```

Feel free to replace it with your own wrapper or a direct `podman run` once you have evaluated the defaults.

---

## Jenkins CLI

`jenkins-cli.jar` (matching the default core tag) is included so you can script automation tasks:

```bash
java -jar jenkins-cli.jar -s http://localhost:8080/ -auth admin:secret list-jobs
```

If you have enabled the integrated SSH endpoint (`Manage Jenkins ▶ Configure Global Security`), you can also use:

```bash
ssh -p 2233 admin@localhost help
```

---

## Security bootstrap (Groovy hooks)

| Script                             | Purpose                                                                                                  |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------- |
| **init\_admin\_user.groovy**       | Creates/updates user *admin*, assigns *Overall/Administer*, and optionally stores a pre‑hashed password. |
| **setup\_ssh\_public\_key.groovy** | Adds an SSH public key to the *admin* account so you can run `jenkins-cli` over SSH without a token.     |

Place additional `.groovy` files into `init.groovy.d/` to automate seed jobs, credentials, etc.

---

## Upgrading Jenkins

1. Stop the service.
2. Bump `VERSION=` in `jenkins.sysconfig` (e.g. `2.517.2`).
3. Re‑run **plugin helper scripts** to refresh version pins.
4. Start the service and watch the logs.

The `minimalJenkinsCore.sh` + `minimal-core.jq` combo can help you calculate the smallest viable core when you prune plugins.

---

## Contributing

Patches are welcome, especially around:

* Enhanced error handling in the Bash helpers.
* Improved plugin‑diffing logic.
* Hardened systemd service (e.g. `ProtectSystem=strict`).

---

## License

This project is released under the **MIT License** — see the [LICENSE](LICENSE) file for details.
