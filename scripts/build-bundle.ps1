# Build the all-in-one self-extracting bundle: Uniform Server ZeroXV base
# package + freshly built UniController/UniService + PHP 8.4/8.5 modules +
# the MariaDB module as the database engine (replaces the base's MySQL).
#
# Expects (as laid out by actions/download-artifact):
#   artifacts/uniserver-binaries/UniController/UniController.exe
#   artifacts/uniserver-binaries/UniService/UniService.exe
#   artifacts/php-module-*/UniServer-Reload_php8*_module.zip
#   artifacts/mariadb-module/UniServer-Reload_mariadb_module.zip
#
# Produces: dist/UniServer-Reload.exe (7-Zip GUI self-extractor). Unlike the
# upstream 15_0_2_ZeroXV.exe it extracts FLAT: the server files land directly
# in the chosen target folder, without a UniServerZ subfolder.
$ErrorActionPreference = 'Stop'

# --- Fork version: single source of truth is UniController/reload_version.inc
$versionInc = Get-Content 'UniController\reload_version.inc' -Raw
if ($versionInc -notmatch "US_RELOAD_VERSION\s*=\s*'([^']+)'") { throw 'US_RELOAD_VERSION not found in UniController\reload_version.inc' }
$reloadVersion = $Matches[1]
$baseVersion = '15.0.2'   # Uniform Server ZeroXV base package the bundle builds on
Write-Host "==> Building UniServer Reload $reloadVersion (base package $baseVersion)"

$sevenZip = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
$sfxModule = Join-Path $env:ProgramFiles '7-Zip\7z.sfx'
if (-not (Test-Path $sevenZip))  { throw "7z.exe not found at $sevenZip" }
if (-not (Test-Path $sfxModule)) { throw "7z.sfx not found at $sfxModule" }

# --- Fetch and unpack the base package ---------------------------------------
# Preferred source is our own mirror (assets of the base-package release) so
# builds do not depend on SourceForge availability; SourceForge is the fallback.
$mirrorUrl = 'https://github.com/Wolfram33/uniserver-reload/releases/download/base-package/15_0_2_ZeroXV.exe'
$baseUrl = 'https://downloads.sourceforge.net/project/miniserver/Uniform%20Server%20ZeroXV/15_0_2_ZeroXV/15_0_2_ZeroXV.exe'
Write-Host '==> Downloading Uniform Server ZeroXV 15.0.2 base package (mirror)'
& curl.exe -fsSL -o base.exe $mirrorUrl
if ($LASTEXITCODE -ne 0) {
  Write-Host '==> Mirror not available, falling back to SourceForge'
  # curl.exe instead of Invoke-WebRequest: SourceForge serves browser-like
  # clients an HTML mirror-selection page instead of the file.
  & curl.exe -fsSL -o base.exe $baseUrl
  if ($LASTEXITCODE -ne 0) { throw "Base package download failed ($LASTEXITCODE)" }
}
$size = (Get-Item base.exe).Length
if ($size -lt 40MB) { throw "Base package download too small ($size bytes) - got an HTML page instead of the installer?" }

Write-Host '==> Extracting base package'
& $sevenZip x -y -obase base.exe | Out-Null
if ($LASTEXITCODE -ne 0) { throw "7z extraction failed ($LASTEXITCODE)" }

$root = 'base\UniServerZ'
if (-not (Test-Path "$root\UniController.exe")) { throw "Unexpected base package layout - UniServerZ\UniController.exe not found" }

# --- Upgrade Apache to the latest Apache Lounge build ------------------------
# The base package ships Apache 2.4.58 (Oct 2023). Scrape the Apache Lounge
# download page for the newest 2.4.x VS17 win64 build and swap the binary
# directories while keeping the Uniform Server configuration.
Write-Host '==> Checking for latest Apache Lounge build'
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)'
function Find-HttpdZip([string]$html) {
  # Accept anything between the patch level and -win64 (build dates, openssl
  # tags, ...) and any compiler tag: newest patch, then newest VS wins
  [regex]::Matches($html, 'httpd-2\.4\.(\d+)[\w.-]*?-win64-VS(\d+)\.zip') |
    ForEach-Object { [pscustomobject]@{ Patch = [int]$_.Groups[1].Value; VS = [int]$_.Groups[2].Value; Name = $_.Value } } |
    Sort-Object Patch, VS -Descending | Select-Object -First 1
}
$dlHtml = (& curl.exe -fsSL -A $UA 'https://www.apachelounge.com/download/') -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Could not fetch Apache Lounge download page' }
$found = Find-HttpdZip $dlHtml
if (-not $found) {
  # Zips may live on per-compiler subpages (e.g. /download/VS18/): follow the
  # newest one referenced on the main page
  $vsPages = [regex]::Matches($dlHtml, 'download/VS(\d+)') | ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique -Descending
  foreach ($vs in $vsPages) {
    Write-Host "==> Scanning subpage /download/VS$vs/"
    $subHtml = (& curl.exe -fsSL -A $UA "https://www.apachelounge.com/download/VS$vs/") -join "`n"
    if ($LASTEXITCODE -eq 0) { $found = Find-HttpdZip $subHtml }
    if ($found) { break }
  }
}
if (-not $found) {
  Write-Host '--- No match. All .zip references on the main page: ---'
  [regex]::Matches($dlHtml, '[\w/.-]*\.zip') | ForEach-Object { $_.Value } | Sort-Object -Unique | Select-Object -First 40 | ForEach-Object { Write-Host $_ }
  Write-Host '--- All href values: ---'
  [regex]::Matches($dlHtml, 'href="([^"]+)"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique | Select-Object -First 60 | ForEach-Object { Write-Host $_ }
  throw 'No httpd win64 zip found on Apache Lounge page'
}
$apVer = "2.4.$($found.Patch)"
Write-Host "==> Downloading Apache $apVer ($($found.Name))"
& curl.exe -fsSL -A $UA -e 'https://www.apachelounge.com/download/' -o apache.zip "https://www.apachelounge.com/download/VS$($found.VS)/binaries/$($found.Name)"
if ($LASTEXITCODE -ne 0) { throw 'Apache download failed' }
if ((Get-Item apache.zip).Length -lt 8MB) { throw 'Apache download suspiciously small - HTML page instead of ZIP?' }
Expand-Archive apache.zip -DestinationPath apachedist
if (-not (Test-Path 'apachedist\Apache24\bin\httpd.exe')) { throw 'Unexpected Apache archive layout' }
foreach ($d in 'bin', 'modules', 'error', 'icons', 'include', 'lib') {
  if (Test-Path "$root\core\apache2\$d") { Remove-Item "$root\core\apache2\$d" -Recurse -Force }
  if (Test-Path "apachedist\Apache24\$d") { Copy-Item "apachedist\Apache24\$d" "$root\core\apache2\$d" -Recurse }
}
Move-Item "$root\core\apache2\bin\httpd.exe" "$root\core\apache2\bin\httpd_z.exe" -Force
Write-Host "==> Apache upgraded to $apVer"

# --- Replace controllers with the fork builds --------------------------------
# UniService lives in utils\ since 1.3.0: it is launched from the controller
# menu (Extra > Run Apache/MySQL as Windows service) instead of sitting next
# to UniController.exe, where it invited accidental double-clicks.
Write-Host '==> Installing fork UniController/UniService'
Copy-Item 'artifacts\uniserver-binaries\UniController\UniController.exe' "$root\UniController.exe" -Force
New-Item -ItemType Directory -Force "$root\utils" | Out-Null
Copy-Item 'artifacts\uniserver-binaries\UniService\UniService.exe' "$root\utils\UniService.exe" -Force
if (Test-Path "$root\UniService.exe") { Remove-Item "$root\UniService.exe" -Force }

# --- Database engine: MariaDB replaces the base package's MySQL (1.3.6) ------
# The engine is the MariaDB module built by package-mariadb-module.ps1 in the
# same CI run, so bundle and module are identical. The base's core\mysql
# (MySQL 8.2 with its data directory) goes completely: the two engines'
# data formats are incompatible, a mix of files corrupts the data directory.
$dbModule = Get-ChildItem -Path 'artifacts' -Recurse -Filter 'UniServer-Reload_mariadb_module.zip' | Select-Object -First 1
if (-not $dbModule) { throw 'MariaDB module ZIP not found in artifacts (package-mariadb-module job)' }
Write-Host "==> Replacing MySQL with MariaDB ($($dbModule.Name))"
Remove-Item "$root\core\mysql" -Recurse -Force
Expand-Archive -Path $dbModule.FullName -DestinationPath $root -Force
foreach ($f in 'core\mysql\bin\mysqld_z.exe', 'core\mysql\bin\mysql.exe', 'core\mysql\bin\mysqladmin.exe',
               'core\mysql\bin\mysqldump.exe', 'core\mysql\my.ini', 'core\mysql\us_opt.ini',
               'core\mysql\data\mysql', 'core\mysql\data\phpmyadmin', 'htpasswd\mysql\passwd.txt') {
  if (-not (Test-Path "$root\$f")) { throw "MariaDB module incomplete: $f missing after merge" }
}
$dbVersionLine = ((& "$root\core\mysql\bin\mysqld_z.exe" --no-defaults --version 2>&1) | ForEach-Object { "$_" }) -join ' '
if ($dbVersionLine -notmatch '(\d+\.\d+\.\d+)-MariaDB') { throw "core\mysql\bin\mysqld_z.exe is not a MariaDB server: $dbVersionLine" }
$dbVersion = $Matches[1]
if ((Get-Content "$root\core\mysql\us_opt.ini" -Raw) -notmatch '(?m)^text = MariaDB') { throw 'core\mysql\us_opt.ini does not name MariaDB' }
Write-Host "==> Database engine: MariaDB $dbVersion"

# --- Stamp the fork version --------------------------------------------------
# AppVersion carries the fork version (splash page and controller read it);
# BaseVersion records the ZeroXV base package the bundle was built from.
Write-Host "==> Stamping version $reloadVersion"
$cfg = "$root\home\us_config\us_config.ini"
$c = Get-Content $cfg -Raw
$c = $c -replace '(?m)^AppVersion=.*?(\r?)$', "AppVersion=$reloadVersion`$1"
if ($c -notmatch '(?m)^BaseVersion=') {
  $c = $c -replace '(?m)^(AppVersion=.*?\r?)$', "`$1`nBaseVersion=$baseVersion"
}
# DatabaseVersion: engine and version for the splash page ("MariaDB 11.8.9");
# without it the page falls back to the flavour file core\mysql\us_opt.ini
if ($c -match '(?m)^DatabaseVersion=') {
  $c = $c -replace '(?m)^DatabaseVersion=.*?(\r?)$', "DatabaseVersion=MariaDB $dbVersion`$1"
} else {
  $c = $c -replace '(?m)^(BaseVersion=.*?\r?)$', "`$1`nDatabaseVersion=MariaDB $dbVersion"
}
# Window title / tray hover text still carries the upstream name in the stock ini
$c = $c -replace '(?m)^ServerTypeText1=Uniform Server Zero(\r?)$', 'ServerTypeText1=Uniform Server Reload$1'
# Minimum VC++ runtime per PHP version: UniController warns (with download
# link) before an Apache start that would die on module load (issue #3).
if ($c -notmatch '(?m)^\[VCRUNTIME\]') {
  $c = $c.TrimEnd() + "`r`n`r`n[VCRUNTIME]`r`n; Minimum Microsoft Visual C++ runtime (x64) per PHP version (major.minor).`r`n; UniController warns before starting Apache when the installed runtime is older.`r`nphp85=14.44`r`n"
}
Set-Content $cfg -Value $c -NoNewline
if ((Get-Content $cfg -Raw) -notmatch "(?m)^AppVersion=$([regex]::Escape($reloadVersion))") { throw 'us_config.ini version stamp failed' }
if ((Get-Content $cfg -Raw) -notmatch '(?m)^ServerTypeText1=Uniform Server Reload') { throw 'us_config.ini ServerTypeText1 stamp failed' }
if ((Get-Content $cfg -Raw) -notmatch "(?m)^DatabaseVersion=MariaDB $([regex]::Escape($dbVersion))") { throw 'us_config.ini DatabaseVersion stamp failed' }
if ((Get-Content $cfg -Raw) -notmatch '(?m)^php85=14\.44') { throw 'us_config.ini VCRUNTIME stamp failed' }
Set-Content "$root\home\version.txt" -Value "UniServer Reload $reloadVersion (base package Uniform Server ZeroXV $baseVersion)"

# --- Merge the PHP modules ---------------------------------------------------
$modules = Get-ChildItem -Path 'artifacts' -Recurse -Filter 'UniServer-Reload_php8*_module.zip'
if ($modules.Count -eq 0) { throw 'No PHP module ZIPs found in artifacts' }
foreach ($m in $modules) {
  Write-Host "==> Merging $($m.Name)"
  Expand-Archive -Path $m.FullName -DestinationPath $root -Force
}
foreach ($p in 'php84', 'php85') {
  if (-not (Test-Path "$root\core\$p\php.exe")) { throw "core\$p\php.exe missing after merge" }
}

# --- Patch httpd.conf --------------------------------------------------------
# The stock config only has <IfDefine> include blocks up to php83; without
# them Apache serves .php files as plain text for php84/php85.
$conf = "$root\core\apache2\conf\httpd.conf"
$text = Get-Content $conf -Raw
if ($text -notmatch '<IfDefine php84>') {
  Write-Host '==> Adding php84/php85 include blocks to httpd.conf'
  $block = @'


<IfDefine php84>
   Include ${US_ROOTF}/core/apache2/conf/extra_us/php84.conf
</IfDefine>

<IfDefine php85>
   Include ${US_ROOTF}/core/apache2/conf/extra_us/php85.conf
</IfDefine>
'@
  $anchor = $text.IndexOf('<IfDefine php83>')
  if ($anchor -lt 0) { throw 'php83 IfDefine block not found in httpd.conf' }
  $insertAt = $text.IndexOf('</IfDefine>', $anchor) + '</IfDefine>'.Length
  $text = $text.Insert($insertAt, $block)
  Set-Content -Path $conf -Value $text -NoNewline
}
if ((Get-Content $conf -Raw) -notmatch '<IfDefine php85>') { throw 'httpd.conf patch failed' }

# Ensure mod_rewrite works out of the box: the module must be loaded and the
# served directories need FollowSymLinks, without which Apache rejects
# RewriteRule in directory/.htaccess context (WordPress-style rewrites).
$text = Get-Content $conf -Raw
if ($text -notmatch '(?m)^LoadModule rewrite_module') { throw 'mod_rewrite is not enabled in the stock httpd.conf' }
$patched = $text -replace '(?m)^(\s*)Options Indexes Includes(\r?)$', '$1Options Indexes Includes FollowSymLinks$2'
if ($patched -ne $text) {
  Write-Host '==> Adding FollowSymLinks to Options directives'
  Set-Content -Path $conf -Value $patched -NoNewline
}
if ((Get-Content $conf -Raw) -notmatch 'Options Indexes Includes FollowSymLinks') { throw 'FollowSymLinks patch failed' }

# --- Modern mail setup: CA bundle, secure msmtp template, header wrapper -----
# The stock msmtprc disables certificate checks and PHP mail() via msmtp
# lacks Date/Message-ID headers (spam-filter penalties). Ship the Mozilla
# CA bundle, a certcheck-on template and the header-adding sendmail shim.
Write-Host '==> Installing mail setup (CA bundle, msmtp template, header wrapper)'
& curl.exe -fsSL -o "$root\core\msmtp\cacert.pem" 'https://curl.se/ca/cacert.pem'
if ($LASTEXITCODE -ne 0) { throw 'cacert.pem download failed' }
if ((Get-Item "$root\core\msmtp\cacert.pem").Length -lt 100KB) { throw 'cacert.pem suspiciously small' }
Copy-Item 'bundle\msmtp\msmtprc.ini' "$root\core\msmtp\msmtprc.ini" -Force
Copy-Item 'bundle\msmtp\mail_wrapper.php' "$root\core\msmtp\mail_wrapper.php" -Force
# Normalize the bat to CRLF while copying
Get-Content 'bundle\msmtp\sendmail.bat' | Set-Content "$root\core\msmtp\sendmail.bat"
# Point the base php83 inis at the header wrapper AND enable the extensions
# every version should ship with (the php84/85 module inis are generated with
# these already). SQLite is the most common DB for small PHP apps; fileinfo
# and curl are near-universally expected. DLLs are present in extensions\.
# Covers php_production/development/test.ini (Apache-style, ;extension= lines)
# and php-cli.ini (bare extension= lines, some extensions absent entirely).
foreach ($ini in Get-ChildItem "$root\core\php83" -Filter 'php*.ini' -ErrorAction SilentlyContinue) {
  $c = Get-Content $ini.FullName -Raw
  $c = $c -replace '(?m)^sendmail_path = ".*msmtp\.exe.*"', 'sendmail_path = "${US_ROOTF}/core/msmtp/sendmail.bat"'
  $append = ''
  foreach ($ext in 'pdo_sqlite', 'sqlite3', 'fileinfo', 'curl') {
    if ($c -match ('(?m)^extension=' + $ext + '\s*$')) { continue }       # already active
    elseif ($c -match ('(?m)^;extension=' + $ext + '\s*$')) {
      $c = $c -replace ('(?m)^;extension=' + $ext + '\s*$'), ('extension=' + $ext)
    }
    else { $append += "`nextension=$ext" }                                 # absent (e.g. cli ini)
  }
  if ($append) { $c = $c.TrimEnd() + "`n; Uniform Server Reload - default extensions" + $append + "`n" }
  Set-Content $ini.FullName -Value $c -NoNewline
  # Verify each extension is now active
  foreach ($ext in 'pdo_sqlite', 'sqlite3', 'fileinfo', 'curl') {
    if ((Get-Content $ini.FullName -Raw) -notmatch ('(?m)^extension=' + $ext + '\s*$')) {
      throw "php83 $($ini.Name): failed to enable $ext"
    }
  }
}

# (The database my.ini needs no patching here: the MariaDB module ships
# bundle\db\mariadb-my.ini with the development and server-load values
# already in, and tune-server-config.ps1 below recognises it.)

# --- Serve the same document root over HTTP and HTTPS ------------------------
# Upstream serves https from a separate ssl folder, which surprises users
# whose apps live in www ('works on http, 404 on https'). Point the SSL root
# at www; the classic split can be restored via US_ROOTF_SSL=./ssl.
$userIni = "$root\home\us_config\us_user.ini"
(Get-Content $userIni -Raw) -replace 'US_ROOTF_SSL=\./ssl', 'US_ROOTF_SSL=./www' | Set-Content $userIni -NoNewline
if ((Get-Content $userIni -Raw) -notmatch [regex]::Escape('US_ROOTF_SSL=./www')) { throw 'us_user.ini SSL root patch failed' }

# --- Console look -------------------------------------------------------------
# Server Console / MySQL Console open in Windows Terminal with a translucent
# acrylic background (UniController reads CONSOLE_OPACITY, default 50).
# Document the knob in the shipped ini right next to RUN_CONSOLE.
$consoleDoc = 'RUN_CONSOLE=yes$1;$1;--Console windows (Server Console, MySQL Console): opacity in percent, 50-100. 100 = classic opaque cmd window$1CONSOLE_OPACITY=50$1'
(Get-Content $userIni -Raw) -replace 'RUN_CONSOLE=yes(\r?\n)', $consoleDoc | Set-Content $userIni -NoNewline
if ((Get-Content $userIni -Raw) -notmatch 'CONSOLE_OPACITY=50') { throw 'us_user.ini console opacity patch failed' }

# --- Default SSL vhost -------------------------------------------------------
# The stock httpd-vhosts.conf only carries a default vhost for the http port.
# Once user vhosts exist, requests with unknown host names (e.g. access by IP)
# on the SSL port would be answered by the first user vhost instead of www.
# Mirror the default block for the SSL port so both ports behave identically.
$vhostConf = "$root\core\apache2\conf\extra\httpd-vhosts.conf"
$v = Get-Content $vhostConf -Raw
if ($v -notmatch '_default_:\$\{AP_SSL_PORT\}') {
  $sslBlock = @'


# Same shallow duplicate for the SSL port: keeps requests with unknown host
# names on https in the main document root instead of the first user vhost.
# No log lines: the block inherits the main logs (tune-server-config.ps1
# strips them from the stock http block as well).
<IfModule ssl_module>
<VirtualHost _default_:${AP_SSL_PORT}>
  DocumentRoot ${US_ROOTF_SSL}
  ServerName ${US_SERVERNAME}
  SSLEngine on
  SSLCertificateFile "${US_ROOTF}/core/apache2/server_certs/server.crt"
  SSLCertificateKeyFile "${US_ROOTF}/core/apache2/server_certs/server.key"
</VirtualHost>
</IfModule>
'@
  $idx = $v.IndexOf('</VirtualHost>')
  if ($idx -lt 0) { throw 'httpd-vhosts.conf: default vhost block not found' }
  $v = $v.Insert($idx + '</VirtualHost>'.Length, $sslBlock)
  Set-Content $vhostConf -Value $v -NoNewline
}
if ((Get-Content $vhostConf -Raw) -notmatch '_default_:\$\{AP_SSL_PORT\}') { throw 'httpd-vhosts.conf SSL default vhost patch failed' }
Write-Host '==> Default SSL vhost added to httpd-vhosts.conf'

# --- Server tuning: rotating logs, OPcache, load limits ----------------------
# One script for the bundle and for existing installations (see README):
# Apache logs rotate with bounded disk use, OPcache is on in every PHP
# version, Apache/MySQL limits are sized for a small-business server. Runs
# after the vhost/SSL patches above because it rewrites their log lines.
& "$PSScriptRoot\tune-server-config.ps1" -Root $root

# --- Install fork splash page ------------------------------------------------
# Replaces the stock splash page (stale version list, upstream download links)
# with the fork's version-aware page. The stock static index.html must go:
# DirectoryIndex prefers index.html over index.php, so it would shadow the
# fork page (with a stale version) for anyone browsing /us_splash/.
Copy-Item 'bundle\us_splash\index.php' "$root\home\us_splash\index.php" -Force
if (Test-Path "$root\home\us_splash\index.html") { Remove-Item "$root\home\us_splash\index.html" -Force }
# Fork stylesheet: flex header keeps the status block below the banner instead
# of the stock CSS absolutely positioning it over the banner text.
Copy-Item 'bundle\us_splash\css\style.css' "$root\home\us_splash\css\style.css" -Force
if (Test-Path "$root\home\us_splash\images\branding_bg.png") { Remove-Item "$root\home\us_splash\images\branding_bg.png" -Force }

# --- Brand bundled documentation ---------------------------------------------
# header.js/footer.js are included by every manual page: the fork header adds
# a notice that the manual describes the original 15.0.2 release. The manual
# landing page gets corrected install instructions.
Copy-Item 'bundle\us_docs\header.js' "$root\docs\manual\common\header.js" -Force
Copy-Item 'bundle\us_docs\footer.js' "$root\docs\manual\common\footer.js" -Force
Copy-Item 'bundle\us_docs\index.html' "$root\docs\manual\index.html" -Force
# The fork controller adds restart/status commands and exit codes: ship the
# matching manual page instead of the stock one.
Copy-Item 'bundle\us_docs\command_line_parameters.html' "$root\docs\manual\command_line_parameters.html" -Force

# --- Reload branding: banner, favicon, www test page -------------------------
Copy-Item 'bundle\branding\banner.png' "$root\home\us_splash\images\logo.png" -Force
Copy-Item 'bundle\branding\banner.png' "$root\docs\manual\common\images\us_zero_logo.png" -Force
Copy-Item 'bundle\branding\favicon.ico' "$root\home\us_splash\favicon.ico" -Force
if (Test-Path "$root\www\favicon.ico") { Copy-Item 'bundle\branding\favicon.ico' "$root\www\favicon.ico" -Force }
# Branded www test page: replaces the stock ZeroXV page; the banner doubles as
# its header logo and the old background tile becomes obsolete (CSS gradient).
Copy-Item 'bundle\www\index.php' "$root\www\index.php" -Force
Copy-Item 'bundle\www\css\style.css' "$root\www\css\style.css" -Force
Copy-Item 'bundle\branding\banner.png' "$root\www\images\logo.png" -Force
if (Test-Path "$root\www\images\branding_bg.png") { Remove-Item "$root\www\images\branding_bg.png" -Force }

# --- Smoke test: every PHP version must execute and load the default exts ----
# Starts Apache once per installed PHP version and verifies PHP is executed
# (not served as source) and that the extensions the fork guarantees are
# actually loaded. Catches ini regressions per version for good.
Write-Host '==> Smoke test: verifying every PHP version'
$rootAbs = (Resolve-Path $root).Path
$env:US_ROOTF        = $rootAbs -replace '\\', '/'
$env:US_ROOTF_WWW    = "$env:US_ROOTF/www"
$env:US_SERVERNAME   = 'localhost'
$env:AP_PORT         = '8088'
$env:PHP_INI_SELECT  = 'php_test.ini'
$REQUIRED_EXT = @('pdo_sqlite', 'sqlite3', 'fileinfo', 'curl', 'mbstring', 'gd', 'openssl', 'Zend OPcache')

# Probe page: prints a marker, the OPcache switch and the loaded extensions
@'
<?php echo "USR-PROBE ", PHP_VERSION, " OPC:", ini_get("opcache.enable"), " EXT:", implode(",", get_loaded_extensions());
'@ | Set-Content "$root\www\_ci_probe.php" -NoNewline

$httpd = "$rootAbs\core\apache2\bin\httpd_z.exe"
& $httpd -t -f "$rootAbs\core\apache2\conf\httpd.conf" -d "$rootAbs\core\apache2"
if ($LASTEXITCODE -ne 0) { throw 'Apache configuration syntax check failed' }

# Stops the test Apache. Its piped log writers (rotatelogs_z.exe) must exit on
# their own once httpd closes the pipe - an orphan here would mean an orphan
# after every controller stop as well.
function Stop-SmokeApache {
  & taskkill /F /IM httpd_z.exe 2>$null | Out-Null
  foreach ($i in 1..40) {
    if (-not (Get-Process -Name rotatelogs, rotatelogs_z -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 250
  }
  if (Get-Process -Name rotatelogs, rotatelogs_z -ErrorAction SilentlyContinue) {
    & taskkill /F /IM rotatelogs_z.exe 2>$null | Out-Null
    & taskkill /F /IM rotatelogs.exe 2>$null | Out-Null
    throw 'Smoke test: rotatelogs_z.exe did not exit after Apache was stopped'
  }
}

$versions = Get-ChildItem "$root\core" -Directory -Filter 'php8*' | ForEach-Object { $_.Name } | Sort-Object
foreach ($ver in $versions) {
  $env:PHP_SELECT = $ver
  Start-Process -FilePath $httpd -ArgumentList '-f', "$rootAbs\core\apache2\conf\httpd.conf", '-d', "$rootAbs\core\apache2" | Out-Null
  $resp = $null
  foreach ($i in 1..30) {
    Start-Sleep -Seconds 1
    $resp = & curl.exe -fsS 'http://localhost:8088/_ci_probe.php' 2>$null
    if ($LASTEXITCODE -eq 0 -and $resp) { break }
  }
  Stop-SmokeApache
  $text = ($resp -join "`n")
  if ($text -match '<\?php') { throw "Smoke test ($ver): PHP served as source instead of executing" }
  if ($text -notmatch 'USR-PROBE') { throw "Smoke test ($ver): Apache did not serve the PHP probe" }
  if ($text -notmatch ' OPC:1 ') { throw "Smoke test ($ver): opcache.enable is not 1" }
  $loaded = @()
  if ($text -match 'EXT:(.*)$') { $loaded = $Matches[1] -split ',' }
  $missing = $REQUIRED_EXT | Where-Object { $_ -notin $loaded }
  if ($missing) { throw "Smoke test ($ver): required extensions not loaded: $($missing -join ', ')" }
  Write-Host "   $ver OK - PHP executes, OPcache on, extensions loaded"
}
Remove-Item "$root\www\_ci_probe.php" -Force

# Piped logging works: rotatelogs wrote the access log (hard link in logs\,
# ring part in logs\rotated\) and the probe requests are in it
$accessLog = "$rootAbs\core\apache2\logs\access.log"
if (-not (Test-Path $accessLog)) { throw 'Smoke test: logs\access.log was not created by rotatelogs' }
if (-not (Test-Path "$rootAbs\core\apache2\logs\rotated\access.log")) { throw 'Smoke test: logs\rotated\access.log (rotation ring) is missing' }
if ((Get-Content $accessLog -Raw) -notmatch '_ci_probe\.php') { throw 'Smoke test: probe requests are missing from the rotated access log' }
# The writer must be the windowless copy (GUI subsystem), or every log opens
# a terminal window on the user's desktop (1.3.3)
$rz = [IO.File]::ReadAllBytes("$rootAbs\core\apache2\bin\rotatelogs_z.exe")
$peOff = [BitConverter]::ToInt32($rz, 0x3C)
if ([BitConverter]::ToUInt16($rz, $peOff + 4 + 20 + 68) -ne 2) { throw 'Smoke test: bin\rotatelogs_z.exe is not a GUI-subsystem executable' }
Write-Host '   log rotation OK - access log written through the windowless rotatelogs_z.exe'

# --- Smoke test: MariaDB starts, PHP reaches it, phpMyAdmin logs in ----------
# Started the way the controller starts it: --defaults-file only, the port
# in MYSQL_TCP_PORT (server, client tools and phpMyAdmin's config.inc.php
# all read that variable), data directory implied by the exe location.
Write-Host '==> Smoke test: database engine'
$env:MYSQL_TCP_PORT = '33306'
$mysqld   = "$rootAbs\core\mysql\bin\mysqld_z.exe"
$mysqladm = "$rootAbs\core\mysql\bin\mysqladmin.exe"
$dbErrLog = "$rootAbs\core\mysql\data\mysql.err"
$dbProc = Start-Process -FilePath $mysqld -ArgumentList "--defaults-file=`"$rootAbs\core\mysql\my.ini`"" -PassThru -NoNewWindow
$dbReady = $false
foreach ($i in 1..120) {
  Start-Sleep -Milliseconds 500
  if ($dbProc.HasExited) { break }
  $ping = & $mysqladm --host=127.0.0.1 --port=$env:MYSQL_TCP_PORT --user=root --password=root ping 2>&1
  if ($LASTEXITCODE -eq 0 -and (($ping | ForEach-Object { "$_" }) -join ' ') -match 'alive') { $dbReady = $true; break }
}
if (-not $dbReady) {
  if (-not $dbProc.HasExited) { $dbProc.Kill() }
  if (Test-Path $dbErrLog) { Get-Content $dbErrLog | Select-Object -Last 40 | ForEach-Object { Write-Host "   mysql.err: $_" } }
  throw 'Smoke test: MariaDB did not become ready'
}
# The error log must be where the controller's "error log" menu looks
if (-not (Test-Path $dbErrLog)) { throw 'Smoke test: core\mysql\data\mysql.err was not written (log_error in my.ini)' }

# Probe page: connects as root and as the phpMyAdmin control user, the way
# apps and phpMyAdmin do (TCP to 127.0.0.1, port from MYSQL_TCP_PORT)
@'
<?php
$port  = (int) getenv('MYSQL_TCP_PORT');
$parts = array();
mysqli_report(MYSQLI_REPORT_OFF);
foreach (array('root', 'pma') as $user) {
  $db = @new mysqli('127.0.0.1', $user, 'root', 'phpmyadmin', $port);
  if ($db->connect_errno) { echo 'USR-DBPROBE FAIL ', $user, ': ', $db->connect_error; exit; }
  $version = $db->query('SELECT VERSION()')->fetch_row();
  $tables  = $db->query("SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'phpmyadmin'")->fetch_row();
  $parts[] = $user . '=' . $version[0] . '/' . $tables[0];
  $db->close();
}
echo 'USR-DBPROBE OK ', implode(' ', $parts);
'@ | Set-Content "$root\www\_ci_dbprobe.php" -NoNewline
$pmaTables = ([regex]::Matches((Get-Content 'bundle\db\phpmyadmin-create_tables.sql' -Raw), 'CREATE TABLE IF NOT EXISTS')).Count

$env:PHP_SELECT = ($versions | Select-Object -First 1)
Start-Process -FilePath $httpd -ArgumentList '-f', "$rootAbs\core\apache2\conf\httpd.conf", '-d', "$rootAbs\core\apache2" | Out-Null
$resp = $null
foreach ($i in 1..30) { Start-Sleep -Seconds 1; $resp = & curl.exe -fsS 'http://localhost:8088/_ci_dbprobe.php' 2>$null; if ($LASTEXITCODE -eq 0 -and $resp) { break } }
$pmaHtml = & curl.exe -fsS 'http://localhost:8088/us_opt1/index.php' 2>$null
Stop-SmokeApache
$text = ($resp -join "`n")
if ($text -notmatch 'USR-DBPROBE OK') { throw "Smoke test: PHP could not use the database: $text" }
foreach ($user in 'root', 'pma') {
  if ($text -notmatch "$user=$([regex]::Escape($dbVersion))-MariaDB/$pmaTables") { throw "Smoke test: unexpected probe result for $user (want MariaDB $dbVersion and $pmaTables phpmyadmin tables): $text" }
}
$pmaText = ($pmaHtml -join "`n")
if ($pmaText -notmatch 'phpMyAdmin') { throw 'Smoke test: phpMyAdmin page did not render' }
if ($pmaText -match 'mysqli::real_connect|Cannot connect|#1045|#2002') { throw 'Smoke test: phpMyAdmin could not log in to MariaDB' }
if ($pmaText -notmatch [regex]::Escape($dbVersion)) { throw "Smoke test: phpMyAdmin page does not show server version $dbVersion" }

& $mysqladm --host=127.0.0.1 --port=$env:MYSQL_TCP_PORT --user=root --password=root shutdown
if ($LASTEXITCODE -ne 0) { throw 'Smoke test: mysqladmin shutdown failed' }
if (-not $dbProc.WaitForExit(60000)) { $dbProc.Kill(); throw 'Smoke test: MariaDB did not stop within 60 s after shutdown' }
Remove-Item "$root\www\_ci_dbprobe.php" -Force
Remove-Item Env:\MYSQL_TCP_PORT
# The run's error log and pid file must not ship
foreach ($f in 'mysql.err', 'mysql.pid') { Remove-Item "$root\core\mysql\data\$f" -Force -ErrorAction SilentlyContinue }
Write-Host "   MariaDB $dbVersion OK - PHP and phpMyAdmin connect as root and pma, clean shutdown"

# Splash page and www test page render (fork content) under the default version
$env:PHP_SELECT = ($versions | Select-Object -First 1)
Start-Process -FilePath $httpd -ArgumentList '-f', "$rootAbs\core\apache2\conf\httpd.conf", '-d', "$rootAbs\core\apache2" | Out-Null
$resp = $null
foreach ($i in 1..30) { Start-Sleep -Seconds 1; $resp = & curl.exe -fsS 'http://localhost:8088/us_splash/index.php' 2>$null; if ($LASTEXITCODE -eq 0 -and $resp) { break } }
$respWww = & curl.exe -fsS 'http://localhost:8088/index.php' 2>$null
Stop-SmokeApache
if (($resp -join "`n") -notmatch 'Uniform Server Reload') { throw 'Smoke test: splash page did not render fork content' }
if (($respWww -join "`n") -notmatch 'Uniform Server Reload') { throw 'Smoke test: www test page did not render fork content' }
Write-Host "==> Smoke test passed: Apache $apVer, all PHP versions execute with OPcache and required extensions"

# The smoke test's logs must not ship: empty log folder, rotation ring gone
Remove-Item "$root\core\apache2\logs\rotated" -Recurse -Force -ErrorAction SilentlyContinue
foreach ($f in 'access.log', 'error.log', 'access_ssl.log', 'error_ssl.log', 'httpd.pid') {
  Remove-Item "$root\core\apache2\logs\$f" -Force -ErrorAction SilentlyContinue
}

# --- Pack as self-extracting exe ---------------------------------------------
# Flat layout (since 1.3.0): the archives carry the server files at their
# root, so extraction puts them directly into the folder the user picks -
# no UniServerZ nesting any more. 7z's dir\* form keeps empty directories
# (Apache log folders) and dot-files (.htaccess).
Write-Host '==> Packing self-extracting bundle'
New-Item -ItemType Directory -Force dist | Out-Null
& $sevenZip a -sfx"$sfxModule" -mx=7 'dist\UniServer-Reload.exe' '.\base\UniServerZ\*'
if ($LASTEXITCODE -ne 0) { throw "7z sfx packing failed ($LASTEXITCODE)" }

# Same payload as plain zip: for users whose antivirus/SmartScreen distrusts
# unsigned self-extracting exes. The SFX does nothing beyond extracting, so
# the zip is fully equivalent - extract into an empty folder and start
# UniController.exe.
Write-Host '==> Packing plain-zip bundle'
& $sevenZip a -tzip -mx=5 'dist\UniServer-Reload.zip' '.\base\UniServerZ\*'
if ($LASTEXITCODE -ne 0) { throw "7z zip packing failed ($LASTEXITCODE)" }

# Guard the flat layout: the controller must sit at the archive root and no
# stray UniServerZ folder may sneak back in.
$listing = & $sevenZip l -slt 'dist\UniServer-Reload.zip'
if ($LASTEXITCODE -ne 0) { throw 'Could not list bundle zip' }
if ($listing -notcontains 'Path = UniController.exe') { throw 'Bundle layout broken: UniController.exe is not at the archive root' }
if ($listing | Where-Object { $_ -like 'Path = UniServerZ*' }) { throw 'Bundle layout broken: unexpected UniServerZ folder in the archive' }
if ($listing -contains 'Path = UniService.exe') { throw 'Bundle layout broken: UniService.exe must live in utils\, not at the root' }
if ($listing -notcontains 'Path = utils\UniService.exe') { throw 'Bundle layout broken: utils\UniService.exe is missing' }
if ($listing -notcontains 'Path = core\mysql\bin\mysqld_z.exe') { throw 'Bundle layout broken: core\mysql\bin\mysqld_z.exe (MariaDB) is missing' }

Add-Content 'dist\module-versions.txt' "UniServer Reload $reloadVersion (base ZeroXV $baseVersion)"
Add-Content 'dist\module-versions.txt' "Apache $apVer (bundle)"
Add-Content 'dist\module-versions.txt' "MariaDB $dbVersion (bundle)"

Get-Item 'dist\UniServer-Reload.exe', 'dist\UniServer-Reload.zip' | Format-List Name, Length
