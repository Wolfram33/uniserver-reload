# Uniform Server Reload

[![Build](https://github.com/Wolfram33/uniserver-reload/actions/workflows/build.yml/badge.svg)](https://github.com/Wolfram33/uniserver-reload/actions/workflows/build.yml)

**A community fork of [The Uniform Server](https://github.com/iamola/uniserver), aiming to continue development.**

**No external dependencies, no installation, no configuration:** the complete WAMP stack — Apache, MySQL, PHP 8.3/8.4/8.5, phpMyAdmin and the updated controller — ships as a **single self-extracting 7-Zip archive** ([`UniServer-Reload.exe`](https://github.com/Wolfram33/uniserver-reload/releases/tag/latest)). Unpack it anywhere and everything is immediately ready to run. Nothing needs to be downloaded from SourceForge or windows.php.net, no modules need to be added, no settings need to be changed. Portable as ever: no installer, no registry entries.

The original project — a free lightweight WAMP server solution for Windows — has seen no commits since November 2023.
This fork imports the source of its two control programs (UniController and UniService) as a clean starting point for further development.

* Upstream repository: https://github.com/iamola/uniserver (imported at commit `1704fa1`, 2023-11-25)
* Upstream downloads: https://sourceforge.net/projects/miniserver/
* License: BSD (see [LICENSE](LICENSE)) — all credit for the original work goes to The Uniform Server Development Team.
* Fork initiated by **Rob de Roy**, who gave the impulse to revive the project.

## Repository contents

This repository contains the **source code of the controllers only**, written in Free Pascal and compiled with [Lazarus](https://www.lazarus-ide.org/):

* **[UniController](UniController/)** — the main GUI that starts, stops and configures Apache, MySQL/MariaDB and PHP (see its [README](UniController/README.md) for build instructions)
* **[UniService](UniService/)** — a plugin that runs the servers as a Windows service (see its [README](UniService/README.md))

The actual server binaries (Apache, PHP, MySQL, phpMyAdmin, …) are not part of this repository; they are packaged in the Uniform Server ZeroXV releases on SourceForge.

## Downloads

Every push triggers a build that updates the rolling release with fixed download links (no login required):

**➡ [Latest development build](https://github.com/Wolfram33/uniserver-reload/releases/tag/latest)**

| File | Description |
|---|---|
| **`UniServer-Reload.exe`** | **All-in-one, zero-setup package: the complete server (Apache, MySQL, phpMyAdmin, PHP 8.3/8.4/8.5, updated controller) in one self-extracting 7-Zip archive — unpack and it runs, no further downloads or configuration** |
| `UniController.exe` | Controller only — for updating an existing `UniServerZ` installation |
| `UniService.exe` | Windows service module — for updating an existing installation |
| `ZeroXV_php84_module.zip` | PHP 8.4 module (latest official thread-safe x64 build, Uniform Server layout) — for adding to an existing installation |
| `ZeroXV_php85_module.zip` | PHP 8.5 module — for adding to an existing installation |
| `ZeroXV_mariadb_module.zip` | Latest MariaDB LTS as database engine — fresh installs only: delete `core\mysql` first, then unzip into the `UniServerZ` root |

The single-file downloads exist only for users who want to upgrade an existing Uniform Server installation piece by piece; with `UniServer-Reload.exe` none of them are needed.

Quick start: run `UniServer-Reload.exe`, pick a target folder, then start `UniServerZ\UniController.exe` — the servers are ready to go. To switch the PHP version stop Apache first, then use *PHP > Select PHP version*.

## HTTPS (`https://localhost` without browser warning)

The controller generates a self-signed `localhost` certificate on first start and enables SSL automatically — `https://localhost` works right away, but browsers mark self-signed certificates as "not secure" until they are trusted. To get the padlock without a warning:

1. **Upgrading from an older install?** Delete `core\apache2\server_certs\server.crt` and `server.key` first (with Apache stopped), then start UniController — certificates created by the old generator lack the subjectAltName entries Chrome requires and are rejected even when trusted. Fresh installs skip this step.
2. In UniController: **Apache → Apache SSL → Trust certificate in Windows (remove browser warning)** and confirm the Windows security prompt with **Yes**.
3. **Restart the browser completely** (Chrome: enter `chrome://restart` in the address bar — closing the tab is not enough, and check the system tray for background instances).
4. Open `https://localhost` — the padlock now shows without a warning.

The certificate covers `localhost`, `127.0.0.1` and `::1`, is valid for 10 years and is only trusted for the current Windows user.

## Development goals

* [x] Support for current PHP versions (8.4 / 8.5) in the controller's version switching
* [x] HTTPS out of the box: the controller auto-generates a `localhost` certificate on first start and enables SSL; *Apache > Apache SSL > Trust certificate* adds it to the Windows store to remove the browser warning
* [x] Automated builds via CI (Lazarus build on Windows runners)
* [x] Package current PHP versions as ready-to-use modules (built by CI, see Downloads)
* [x] Automatic rolling GitHub release with fixed download links
* [x] Package current Apache / MariaDB versions (bundle ships the latest Apache Lounge 2.4.x build; MariaDB LTS available as a module) — every bundle is smoke-tested in CI: Apache is started on the runner and must serve a PHP-rendered page
* [ ] Work through the open issues of the upstream repository (see below)

## Upstream issue triage

Status of the [open upstream issues](https://github.com/iamola/uniserver/issues) in this fork:

| Issue | Status | Notes |
|---|---|---|
| [#18](https://github.com/iamola/uniserver/issues/18) PHP 8.4 & 8.5 modules | **Controller side done** | UniController and UniService now recognise `core\php84` and `core\php85`. Packaging the actual PHP builds as modules is a separate release task. |
| [#20](https://github.com/iamola/uniserver/issues/20) Future PHP versions | **Partially addressed** | php84/php85 added following the existing per-version pattern; a fully dynamic version discovery remains future work. |
| [#21](https://github.com/iamola/uniserver/issues/21) Host editor rejects TLDs > 3 letters | **Fixed in controller** | Server-name and e-mail validation now accepts TLDs of 2–63 letters (`.test`, `.online`, `.museum`, …). Note: the separate `EdHost.exe` utility shipped with releases is not part of this source repository and still needs the same fix. |
| [#14](https://github.com/iamola/uniserver/issues/14) Command console customization | Open | Feature request, candidate for future work. |
| [#17](https://github.com/iamola/uniserver/issues/17) Update modules/plugins | Open | Release/packaging task, not part of the controller source. |
| [#19](https://github.com/iamola/uniserver/issues/19) Forum captcha broken | Not applicable | Concerns the upstream project's forum infrastructure, not this code base. |

---

## Original project description

Uniform Server is a free lightweight WAMP server solution for Windows.
Build using a modular design approach, it includes the latest versions of Apache, MySQL or MariaDB, PHP (with version switching), phpMyAdmin or Adminer.

No installation required! No registry dust! Just unpack and fire up!

**Uniform Server Zero XV** can be found at SourceForge at https://sourceforge.net/projects/miniserver/ or can be downloaded by clicking on the button below:

[![Download Uniform Server](https://a.fsdn.com/con/app/sf-download-button)](https://sourceforge.net/projects/miniserver/files/latest/download)

### Uniform Server Core

The base version which is suitable for most users is the 15_x_x_ZeroXV.exe that contains the following:

 * Unicontroller - The Uniform Server Controller
 * Apache
 * PHP
 * MySQL
 * PhpMyAdmin
 * msmtp - A SMTP mail client
 * Cron Scheduler
 * Documentation

### Uniform Server Modules

Apart from the core, The Uniform Server Zero XV has a modular design. Install only modules (plugins) that you require.
Each server requires a controller, which automatically detects installed plugins.

The following are the optional plugins that can be used to enhance the Uniform Server Core from the **XV Modules** folder:

* **Core:** UniService - Enables the Servers to be run as a Windows Service.
* **PHP:** PHP 7.0 to 8.3
* **Database:** MariaDB
* **Database Administration:** Adminer, MySQL Auto Backup
* **FTP:** FileZilla Server with a custom controller
* **Perl:** Strawberry Perl
* **Portable Browser:** Pale Moon
