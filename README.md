<h1 align=center>🖴 mipro98/infra 🖴</h1>
<h3 align=center>An Ansible playbook for a docker-based homelab with automatic maintenance and monitoring.</h3>

---

<h4 align=center>Flexible docker-compose templates for various services like Nextcloud, Vaultwarden, Gitea, Prometheus+Grafana,...</h4>
<h4 align=center>All services are set up ready-to-use with a Traefik reverse proxy and automatic TLS certificates.</h4>
<h4 align=center>Unattended server maintenance with auto updates, S.M.A.R.T monitoring, BTRFS snapshots and email notifications.</h4>

---

## Features

This playbook includes tasks for:
* Setting up the host system (packages, user, mounts,...).
* Deploying all docker services according to their docker-compose templates.
* Setting up fully automatic maintenance tasks like:
  * BTRFS snapshots and backups to a different drive using the [btrbk utility](https://digint.ch/btrbk/)
  * BTRFS scrubbing
  * S.M.A.R.T. monitoring with email notifications
  * automatic system and container updates.


Various configuration can be done using variables defined in `group_vars` or in `vault.yml`. For almost all files, [templates](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/template_module.html) are used to craft configuration files or docker-compose.yml files according to set variables.


<u>**This repo contains ready-to-use container setups for:**</u>
* Nextcloud ([with Mariadb, Redis, Cron, Collabora, Memories incl. hardware transcoding](#nextcloud-stack))
* A server monitoring stack with [Prometheus](https://prometheus.io/), [Grafana](https://grafana.com/) and [node_exporter](https://github.com/prometheus/node_exporter).
* [Dokuwiki](https://www.dokuwiki.org/dokuwiki)
* [Gitea](https://about.gitea.com/)
* [Homer](https://github.com/bastienwirtz/homer)
* [Vaultwarden](https://github.com/dani-garcia/vaultwarden)
* [ulogger](https://github.com/bfabiszewski/ulogger-server)
* [OwnTracks](https://owntracks.org/) ([recorder](https://github.com/owntracks/recorder) + [frontend](https://github.com/owntracks/frontend))
* [Planka](https://planka.app/)
* [Traefik v2](https://doc.traefik.io/traefik/) as the central reverse proxy.

**_All these services are setup to be exposed through Traefik on different domains by simply providing domain names for the services in `vault.yml`._**

## Quick start

1. Clone the repo.
2. Run `./git-init.sh`
3. (optionally: run `source unlock-bw.sh`)
4. Deploy (see below)


Deploy everything:
```bash
make deploy
```

* Deploy only host os system setup: `make system`
* Deploy only docker-compose changes: `make containers`
* Deploy only maintenance changes: `make maintenance`


## Ansible-Vault

This repo uses ansible-vault to encrypt secret variables used by Ansible (passwords, domain names, etc.). This affects the file `vars/vault.yml`. A template for `vault.yml` can be found in `vars/vault.yml.template` The password for the encryption is obtained by [bitwarden-cli](https://github.com/bitwarden/cli) in the script `vault-pass.sh`. Therefore you can encrypt and decrypt by just entering your bitwarden master password by just writing:

```bash
make encrypt
make decrpyt
```

**Always remember to encrypt the vault before commiting! Also, absolutely run the script `git-init.sh` after cloning to install a pre-commit hook which prevents committing the unencrypted vault!**

---
## Roles

The repo contains 3 ansible roles:
1. `system`
2. `containers`
3. `maintenance`


### `system` role

  * installs all packages defined in `extra_packages`
  * sets correct permissions for docker
  * sets fstab mount points for a "NAS" and a "BACKUP" drive
  * sets up `smartd` with a sane monitoring configuration and email alerts

_Note:_ SSH configuration is skipped for now.


### `container` role

* Creates the folder structure for docker-compose files according to enabled services
* Deploys the docker-compose.yml templates for the services in their respective folders
* Makes some special configuration for nextcloud, if nextcloud is enabled


### `maintenance` role

At the heart of the maintenance role is the script `mpserver-maintenance.sh` which gets deployed by ansible. Additionally:
* A systemd timer is set up which triggers above script every night at 2 A.M.
* The `btrbk.conf` file is deployed
* An `uptime-monitor.sh` script is deployed which checks continously whether the server is online. When it is offline, it optionally executes an ssh command  (I use it to restart my router). After successful reconnect, an E-Mail is sent about the downtime.
* A systemd service is installed to start the `uptime-monitor.sh` script on boot.

Refer to section [Automatic Maintenance](#automatic-maintenance) for more details.

---
## Automatic Maintenance

The custom bash script `mpserver-maintenance.sh` gets triggered every night at 2 A.M. by systemd. Based on the time (or command line flags), it decides what actions to take:

* monthly tasks _(when script is triggered on last sunday of a month)_
* weekly tasks _(when script is triggered on a sunday except the last sunday of a month)_
* daily tasks _(when triggered all other days between 0 A.M. and 6 A.M.)_

The script can be triggered manually for daily, monthly or weekly tasks. Refer to `sudo ./mpserver-maintenance.sh --help`.

```
Usage: ./mpserver-maintenance.sh [<options>] [<command>]

Options:
	--dry-run	Don't execute anything, only show what would be executed
	--no-email	Don't send an email with the log
	--help		Show this help message and exit.

Commands:
	daily		Run daily maintenance tasks
	weekly		Run weekly maintenance tasks
	monthly	Run monthly maintenance tasks

	If no command is passed, the script will determine the correct schedule and run the appropriate tasks.
```

The tasks are defined in the bash functions `weekly`, `monthly`, `daily`. Each trigger writes a detailed log into `~/maintenance/logs` which also gets emailed for `monthly` and `weekly` triggers.


**Daily tasks**:
1. Snapshot the subvolume "Daten" through btrbk

**Weekly tasks:**
1. backup `~/dockerdata` onto a backup location through rsync
2. snapshot _and_ backup all configured subvolumes according to `btrbk.conf`
3. update the host system
4. send an email with a the detailed log.

**Monthly tasks:**
1. backup `~/dockerdata` onto a backup location through rsync
2. snapshot _and_ backup all configured subvolumes according to `btrbk.conf`
3. update all containers (`docker-compose pull` all services)
4. prune old docker images and volumes
5. `btrfs-scrub` both the _NAS_ and the _BACKUP_ drive.
6. update the host system.
7. send an email with a the detailed log.

---

## Nextcloud stack


The Nextcloud stack is carefully fine-tuned for performance and simplicity using:

* A custom built Nextcloud image with `ffmpeg`, `imagemagick` and `ghostscript` for media previews.
* **MariaDB** for a performant database
* **Redis** for fast memory caching and Transactional File Locking _(I personally use APCu for caching and Redis only for File Locking)_
* A dedicated **go-vod** container with access to `/dev/dri` for hardware acceleration in Nextcloud Memories.
* A dedicated Nextcloud **cron** container <u>with mounted crontab file</u> so you can easily add cronjobs without messing on the host system's cron/systemd.
* A dedicated **Collabora** container for performant **Nextcloud Office** integration.

**Notes:**

* The nextcloud container will _not_ auto-update unless you run `docker-compose build --pull nextcloud` inside `~/docker/nextcloud` because the container is built using `~/docker/nextcloud/Dockerfile` in order to have ffmpeg support. Since Nextcloud updates often require manual intervention and can easily be discovered through the admin panel, this isn't that much of an issue.
* I use [Nextcloud Memories](https://memories.gallery/) alongside [Preview Generator](https://apps.nextcloud.com/apps/previewgenerator) and [Recognize](https://apps.nextcloud.com/apps/recognize) without issues and with hardware transcoding using the seperate go-vod instance. To make it work, adjust the following in the _Memories_ Admin GUI:
  * enable "Images", "HEIC" and "Videos" under "File Support"
  * define `/usr/bin/ffmpeg` / `/usr/bin/ffprobe` as ffmpeg / ffprobe path
  * enable "external transcoder" and just write `go-vod:47788` under "Connection address" _(The Traefik DNS will resolve `go-vod` correctly within the docker proxy network)_.
  * tick "Enable acceleration with VA-API" to <u>on</u>. _(ignore the warning "VA-API device not found")_
  * (note that I added the cronjob for preview generator in the mounted `crontab-www-data` file.)
* **To enter the Nextcloud container** (e.g. to run `occ` commands), **run:**
    ```bash
    docker exec -itu www-data nextcloud bash
    ```

---

## Notes & Tips


* **for [ulogger](/roles/containers/templates/ulogger.yml.j2)**:
  * The container is setup to use sqlite
  * Before the first run: Either use a _named_ volume[^1] or start the container once with a bind mount other than `/data` to copy the container contents of `/data` onto the host to bootstrap the database.
* The `makefile` supports shorthands for often used Ansible commands. For example, when only modifying `mpserver-maintenance.sh`, just run `make script` and it will only replace the script on the server.
* The **`~/docker/docker-compose.yml`**, serves as a "master" docker-compose.yml file with all the activated services [included](https://docs.docker.com/compose/compose-file/14-include/) in the file. You can use it to execute actions on **all** containers at once just with one `docker-compose <up|down|...>` command.
* <del>Make sure to also re-deploy the maintenance script when adding/removing docker services in `group_vars` since the script will change according to the enabled services.</del>[^2]
* Enable `debug_ports_open: true` to open ports on the host bypassing the reverse proxy. This can be used for debugging, e.g. Traefik metrics and node_exporter is usually not accessible outside of `traefik-net`.

[^1]:https://stackoverflow.com/q/65176940
[^2]:Not needed anymore since we can use the new [include](https://docs.docker.com/compose/compose-file/14-include/) mechanism to generate one "master" docker-compose.yml.

---

## TODOs

- [ ] Maintenance: Run all scrubbing tasks in parallel.
- [x] Maintenance: Send Email when scrubbing starts, send another one when scrubbing has ended containing possible errors.
- [x] Maintenance: Better log for transferred files during snapshots & backups with btrbk and rsync.
- [x] Maintenance: Email formatting with `code` so that `>>` doesn't get interpreted as quote by some Email clients.
- [x] Add overall downtime monitoring with alert when server comes back online (and possibly when it is down and monitoring is done from another host).
- [ ] Improve Grafana dashboards.
- [ ] Maintenance: Auto Reboot when Kernel has updated.
- [ ] Add alertion system for suspicious events like access from a specific country or a DDOS attempt.
- [x] Maintenance: Better system update / pacman / paru logging (do not log whole stdout).
- [x] Docker-Compose: making local compose invocations work exchangeably with master-compose invocations (since `com.docker.compose.project` and `com.docker.compose.project.working_dir` Label don't match) (fixed using )


---

## Credits

A large portion of the repository is inspired by [Alex Kretzschmar's infra repo](https://github.com/ironicbadger/infra) as well as [Wolfgang notthebee's infra repo](https://github.com/notthebee/infra). Also, both BTRFS maintenance and the system setup was largely inspired by [zilexa's Homeserver Guide](https://github.com/zilexa/Homeserver).

Thanks also goes to [Jeff Geerling's security role](https://github.com/geerlingguy/ansible-role-security) where I took almost all of my (not yet activated) SSH configuration.
