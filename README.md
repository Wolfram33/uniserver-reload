# Uniform Server Reload

[![Build](https://github.com/Wolfram33/uniserver-reload/actions/workflows/build.yml/badge.svg)](https://github.com/Wolfram33/uniserver-reload/actions/workflows/build.yml)

**A community fork of [The Uniform Server](https://github.com/iamola/uniserver), aiming to continue development.**

The original project — a free lightweight WAMP server solution for Windows — has seen no commits since November 2023.
This fork imports the source of its two control programs (UniController and UniService) as a clean starting point for further development.

* Upstream repository: https://github.com/iamola/uniserver (imported at commit `1704fa1`, 2023-11-25)
* Upstream downloads: https://sourceforge.net/projects/miniserver/
* License: BSD (see [LICENSE](LICENSE)) — all credit for the original work goes to The Uniform Server Development Team.

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
| `UniController.exe` | Freshly built controller — replaces the one in your `UniServerZ` folder |
| `UniService.exe` | Windows service module |
| `ZeroXV_php84_module.zip` | PHP 8.4 module (latest official thread-safe x64 build, Uniform Server layout) — unzip into the `UniServerZ` root |
| `ZeroXV_php85_module.zip` | PHP 8.5 module — unzip into the `UniServerZ` root |

Quick start: unpack [Uniform Server ZeroXV 15.0.2](https://sourceforge.net/projects/miniserver/), replace `UniController.exe`, unzip a PHP module into the `UniServerZ` root folder, then pick the version under *PHP > Select PHP version*.

## Development goals

* [x] Support for current PHP versions (8.4 / 8.5) in the controller's version switching
* [x] Automated builds via CI (Lazarus build on Windows runners)
* [x] Package current PHP versions as ready-to-use modules (built by CI, see Downloads)
* [x] Automatic rolling GitHub release with fixed download links
* [ ] Package current Apache / MariaDB / OpenSSL versions
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
