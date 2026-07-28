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
Invoke-WebRequest -Uri $baseUrl -OutFile base.exe -MaximumRedirection 10

Write-Host '==> Extracting base package'
& $sevenZip x -y -obase base.exe | Out-Null
if ($LASTEXITCODE -ne 0) { throw "7z extraction failed ($LASTEXITCODE)" }

$root = 'base\UniServerZ'
if (-not (Test-Path "$root\UniController.exe")) { throw "Unexpected base package layout - UniServerZ\UniController.exe not found" }

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

# --- Pack as self-extracting exe ---------------------------------------------
Write-Host '==> Packing self-extracting bundle'
New-Item -ItemType Directory -Force dist | Out-Null
& $sevenZip a -sfx"$sfxModule" -mx=7 'dist\UniServer-Reload.exe' '.\base\UniServerZ'
if ($LASTEXITCODE -ne 0) { throw "7z sfx packing failed ($LASTEXITCODE)" }

Get-Item 'dist\UniServer-Reload.exe' | Format-List Name, Length
