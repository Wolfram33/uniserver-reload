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

$sevenZip = Join-Path $env:ProgramFiles '7-Zip\7z.exe'
$sfxModule = Join-Path $env:ProgramFiles '7-Zip\7z.sfx'
if (-not (Test-Path $sevenZip))  { throw "7z.exe not found at $sevenZip" }
if (-not (Test-Path $sfxModule)) { throw "7z.sfx not found at $sfxModule" }

# --- Fetch and unpack the upstream base package ------------------------------
$baseUrl = 'https://downloads.sourceforge.net/project/miniserver/Uniform%20Server%20ZeroXV/15_0_2_ZeroXV/15_0_2_ZeroXV.exe'
Write-Host '==> Downloading Uniform Server ZeroXV 15.0.2 base package'
# curl.exe instead of Invoke-WebRequest: SourceForge serves browser-like
# clients an HTML mirror-selection page instead of the file.
& curl.exe -fsSL -o base.exe $baseUrl
if ($LASTEXITCODE -ne 0) { throw "Base package download failed ($LASTEXITCODE)" }
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
$dlHtml = (& curl.exe -fsSL -A 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' 'https://www.apachelounge.com/download/') -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Could not fetch Apache Lounge download page' }
# Accept any compiler tag (VS17, VS18, ...): pick the newest patch, then newest VS
$found = [regex]::Matches($dlHtml, 'httpd-2\.4\.(\d+)-win64-VS(\d+)\.zip') |
  ForEach-Object { [pscustomobject]@{ Patch = [int]$_.Groups[1].Value; VS = [int]$_.Groups[2].Value; Name = $_.Value } } |
  Sort-Object Patch, VS -Descending | Select-Object -First 1
if (-not $found) {
  Write-Host "--- Page length: $($dlHtml.Length); excerpt: ---"
  Write-Host ($dlHtml.Substring(0, [Math]::Min(1500, $dlHtml.Length)))
  throw 'No httpd win64 zip found on Apache Lounge page'
}
$apVer = "2.4.$($found.Patch)"
Write-Host "==> Downloading Apache $apVer ($($found.Name))"
& curl.exe -fsSL -A 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' -e 'https://www.apachelounge.com/download/' -o apache.zip "https://www.apachelounge.com/download/VS$($found.VS)/binaries/$($found.Name)"
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

# --- Smoke test: start Apache with PHP 8.4 and verify PHP executes -----------
Write-Host '==> Smoke test: starting Apache'
$rootAbs = (Resolve-Path $root).Path
$env:US_ROOTF        = $rootAbs -replace '\\', '/'
$env:US_ROOTF_WWW    = "$env:US_ROOTF/www"
$env:US_SERVERNAME   = 'localhost'
$env:AP_PORT         = '8088'
$env:PHP_SELECT      = 'php84'
$env:PHP_INI_SELECT  = 'php_test.ini'
& "$rootAbs\core\apache2\bin\httpd_z.exe" -t -f "$rootAbs\core\apache2\conf\httpd.conf" -d "$rootAbs\core\apache2"
if ($LASTEXITCODE -ne 0) { throw 'Apache configuration syntax check failed' }
Start-Process -FilePath "$rootAbs\core\apache2\bin\httpd_z.exe" `
  -ArgumentList '-f', "$rootAbs\core\apache2\conf\httpd.conf", '-d', "$rootAbs\core\apache2" | Out-Null
$resp = $null
foreach ($i in 1..30) {
  Start-Sleep -Seconds 1
  $resp = & curl.exe -fsS 'http://localhost:8088/us_splash/index.php' 2>$null
  if ($LASTEXITCODE -eq 0 -and $resp) { break }
}
& taskkill /F /IM httpd_z.exe 2>$null | Out-Null
if (-not $resp) { throw 'Smoke test failed: Apache did not serve the splash page' }
if ($resp -match '<\?php') { throw 'Smoke test failed: PHP source served instead of being executed' }
if ($resp -notmatch 'Uniform Server Reload') { throw 'Smoke test failed: unexpected splash page content' }
Write-Host "==> Smoke test passed: Apache $apVer serves PHP-rendered pages"

# --- Pack as self-extracting exe ---------------------------------------------
Write-Host '==> Packing self-extracting bundle'
New-Item -ItemType Directory -Force dist | Out-Null
& $sevenZip a -sfx"$sfxModule" -mx=7 'dist\UniServer-Reload.exe' '.\base\UniServerZ'
if ($LASTEXITCODE -ne 0) { throw "7z sfx packing failed ($LASTEXITCODE)" }
Add-Content 'dist\module-versions.txt' "Apache $apVer (bundle)"

Get-Item 'dist\UniServer-Reload.exe' | Format-List Name, Length
