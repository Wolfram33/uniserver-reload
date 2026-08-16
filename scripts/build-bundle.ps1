# Build the all-in-one self-extracting bundle: Uniform Server ZeroXV base
# package + freshly built UniController/UniService + PHP 8.4/8.5 modules.
#
# Expects (as laid out by actions/download-artifact):
#   artifacts/uniserver-binaries/UniController/UniController.exe
#   artifacts/uniserver-binaries/UniService/UniService.exe
#   artifacts/php-module-*/ZeroXV_php8*_module.zip
#
# Produces: dist/UniServer-Reload.exe (7-Zip GUI self-extractor, same
# format as the upstream 15_0_2_ZeroXV.exe)
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
Write-Host '==> Installing fork UniController/UniService'
Copy-Item 'artifacts\uniserver-binaries\UniController\UniController.exe' "$root\UniController.exe" -Force
Copy-Item 'artifacts\uniserver-binaries\UniService\UniService.exe' "$root\UniService.exe" -Force

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
Set-Content $cfg -Value $c -NoNewline
if ((Get-Content $cfg -Raw) -notmatch "(?m)^AppVersion=$([regex]::Escape($reloadVersion))") { throw 'us_config.ini version stamp failed' }
Set-Content "$root\home\version.txt" -Value "UniServer Reload $reloadVersion (base package Uniform Server ZeroXV $baseVersion)"

# --- Merge the PHP modules ---------------------------------------------------
$modules = Get-ChildItem -Path 'artifacts' -Recurse -Filter 'ZeroXV_php8*_module.zip'
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

# --- Development-friendly MySQL configuration --------------------------------
# The stock my.ini uses minimal 1990s-style buffers (key_buffer 16K,
# max_allowed_packet 1M, innodb pool 32M). Raise them to sensible values
# for development machines.
$myIni = "$root\core\mysql\my.ini"
$my = Get-Content $myIni -Raw
$my = $my -replace '(?m)^key_buffer_size = .*?(\r?)$',        'key_buffer_size = 32M$1'
$my = $my -replace '(?m)^max_allowed_packet = 1M(\r?)$',      'max_allowed_packet = 256M$1'
$my = $my -replace '(?m)^max_allowed_packet = 16M(\r?)$',     'max_allowed_packet = 256M$1'
$my = $my -replace '(?m)^table_open_cache = .*?(\r?)$',       'table_open_cache = 2000$1'
$my = $my -replace '(?m)^sort_buffer_size = .*?(\r?)$',       'sort_buffer_size = 2M$1'
$my = $my -replace '(?m)^read_buffer_size = .*?(\r?)$',       'read_buffer_size = 1M$1'
$my = $my -replace '(?m)^read_rnd_buffer_size = .*?(\r?)$',   'read_rnd_buffer_size = 1M$1'
$my = $my -replace '(?m)^net_buffer_length = .*?(\r?)$',      'net_buffer_length = 16K$1'
$my = $my -replace '(?m)^thread_stack = 256K',                "thread_stack = 256K`ntmp_table_size = 64M`nmax_heap_table_size = 64M"
$my = $my -replace '(?m)^innodb_buffer_pool_size = .*?(\r?)$','innodb_buffer_pool_size = 512M$1'
$my = $my -replace '(?m)^innodb_log_buffer_size = .*?(\r?)$', 'innodb_log_buffer_size = 32M$1'
Set-Content $myIni -Value $my -NoNewline
if ((Get-Content $myIni -Raw) -notmatch 'innodb_buffer_pool_size = 512M') { throw 'my.ini tuning patch failed' }
Write-Host '==> MySQL my.ini tuned for development'

# --- Serve the same document root over HTTP and HTTPS ------------------------
# Upstream serves https from a separate ssl folder, which surprises users
# whose apps live in www ('works on http, 404 on https'). Point the SSL root
# at www; the classic split can be restored via US_ROOTF_SSL=./ssl.
$userIni = "$root\home\us_config\us_user.ini"
(Get-Content $userIni -Raw) -replace 'US_ROOTF_SSL=\./ssl', 'US_ROOTF_SSL=./www' | Set-Content $userIni -NoNewline
if ((Get-Content $userIni -Raw) -notmatch [regex]::Escape('US_ROOTF_SSL=./www')) { throw 'us_user.ini SSL root patch failed' }

# --- Install fork splash page ------------------------------------------------
# Replaces the stock splash page (stale version list, upstream download links)
# with the fork's version-aware page.
Copy-Item 'bundle\us_splash\index.php' "$root\home\us_splash\index.php" -Force

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

# --- Reload branding: banner, favicon ----------------------------------------
Copy-Item 'bundle\branding\banner.png' "$root\home\us_splash\images\logo.png" -Force
Copy-Item 'bundle\branding\banner.png' "$root\docs\manual\common\images\us_zero_logo.png" -Force
Copy-Item 'bundle\branding\favicon.ico' "$root\home\us_splash\favicon.ico" -Force
if (Test-Path "$root\www\favicon.ico") { Copy-Item 'bundle\branding\favicon.ico' "$root\www\favicon.ico" -Force }

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
$REQUIRED_EXT = @('pdo_sqlite', 'sqlite3', 'fileinfo', 'curl', 'mbstring', 'gd', 'openssl')

# Probe page: prints a marker plus the loaded extensions
@'
<?php echo "USR-PROBE ", PHP_VERSION, " EXT:", implode(",", get_loaded_extensions());
'@ | Set-Content "$root\www\_ci_probe.php" -NoNewline

$httpd = "$rootAbs\core\apache2\bin\httpd_z.exe"
& $httpd -t -f "$rootAbs\core\apache2\conf\httpd.conf" -d "$rootAbs\core\apache2"
if ($LASTEXITCODE -ne 0) { throw 'Apache configuration syntax check failed' }

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
  & taskkill /F /IM httpd_z.exe 2>$null | Out-Null
  Start-Sleep -Milliseconds 500
  $text = ($resp -join "`n")
  if ($text -match '<\?php') { throw "Smoke test ($ver): PHP served as source instead of executing" }
  if ($text -notmatch 'USR-PROBE') { throw "Smoke test ($ver): Apache did not serve the PHP probe" }
  $loaded = @()
  if ($text -match 'EXT:(.*)$') { $loaded = $Matches[1] -split ',' }
  $missing = $REQUIRED_EXT | Where-Object { $_ -notin $loaded }
  if ($missing) { throw "Smoke test ($ver): required extensions not loaded: $($missing -join ', ')" }
  Write-Host "   $ver OK - PHP executes, extensions loaded"
}
Remove-Item "$root\www\_ci_probe.php" -Force

# Splash page renders (fork content) under the default version
$env:PHP_SELECT = ($versions | Select-Object -First 1)
Start-Process -FilePath $httpd -ArgumentList '-f', "$rootAbs\core\apache2\conf\httpd.conf", '-d', "$rootAbs\core\apache2" | Out-Null
$resp = $null
foreach ($i in 1..30) { Start-Sleep -Seconds 1; $resp = & curl.exe -fsS 'http://localhost:8088/us_splash/index.php' 2>$null; if ($LASTEXITCODE -eq 0 -and $resp) { break } }
& taskkill /F /IM httpd_z.exe 2>$null | Out-Null
if (($resp -join "`n") -notmatch 'Uniform Server Reload') { throw 'Smoke test: splash page did not render fork content' }
Write-Host "==> Smoke test passed: Apache $apVer, all PHP versions execute with required extensions"

# --- Pack as self-extracting exe ---------------------------------------------
Write-Host '==> Packing self-extracting bundle'
New-Item -ItemType Directory -Force dist | Out-Null
& $sevenZip a -sfx"$sfxModule" -mx=7 'dist\UniServer-Reload.exe' '.\base\UniServerZ'
if ($LASTEXITCODE -ne 0) { throw "7z sfx packing failed ($LASTEXITCODE)" }
Add-Content 'dist\module-versions.txt' "UniServer Reload $reloadVersion (base ZeroXV $baseVersion)"
Add-Content 'dist\module-versions.txt' "Apache $apVer (bundle)"

Get-Item 'dist\UniServer-Reload.exe' | Format-List Name, Length
