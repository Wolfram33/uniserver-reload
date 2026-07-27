# Uniform Server Reload

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

## Development goals

* [ ] Support for current PHP versions (8.4 / 8.5) in the controller's version switching
* [ ] Package current Apache / MariaDB / OpenSSL versions
* [ ] Work through the open issues of the upstream repository
* [ ] Automated builds via CI (Free Pascal cross-compilation)

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
