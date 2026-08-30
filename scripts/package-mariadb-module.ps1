# Package the latest MariaDB LTS as a Uniform Server ZeroXV module.
#
# Replicates the layout of the upstream ZeroXV_mariadb module:
#   core/mysql/bin/       mysqld_z.exe (renamed mariadbd) + classic client
#                         tool names (mysql.exe, mysqladmin.exe,
#                         mysqldump.exe) + required DLLs
#   core/mysql/share/     error messages, charsets
#   core/mysql/data/      initialized system tables, root password 'root'
#   core/mysql/my.ini     from bundle/mariadb/my.ini
#   core/mysql/us_opt.ini flavor info for the controller
#   htpasswd/mysql/passwd.txt  password file read by the controller
#
# The module ZIP replaces core\mysql of an installation. Fresh installs
# only: remove the existing core\mysql (MySQL) folder first - mixing the
# two engines' files corrupts the data directory.
param([string]$OutDir = 'dist')
$ErrorActionPreference = 'Stop'

# --- Find the latest stable LTS release via the MariaDB REST API -------------
$majorsJson = & curl.exe -fsSL 'https://downloads.mariadb.org/rest-api/mariadb/'
if ($LASTEXITCODE -ne 0) { throw 'Could not query MariaDB REST API' }
$majors = ($majorsJson | ConvertFrom-Json).major_releases
$lts = $majors |
  Where-Object { $_.release_status -eq 'Stable' -and $_.release_support_type -eq 'Long Term Support' } |
  Sort-Object { [version]$_.release_id } -Descending | Select-Object -First 1
if (-not $lts) { throw 'No stable MariaDB LTS release found in REST API' }
Write-Host "==> Latest MariaDB LTS series: $($lts.release_id)"

$relJson = & curl.exe -fsSL "https://downloads.mariadb.org/rest-api/mariadb/$($lts.release_id)/latest/"
if ($LASTEXITCODE -ne 0) { throw 'Could not query MariaDB release listing' }
$releases = ($relJson | ConvertFrom-Json).releases
$release = $releases.PSObject.Properties.Value | Select-Object -First 1
$ver = $release.release_id
$file = $release.files |
  Where-Object { $_.file_name -like 'mariadb-*-winx64.zip' -and $_.file_name -notlike '*debug*' } |
  Select-Object -First 1
if (-not $file) { throw "No winx64 ZIP found for MariaDB $ver" }

Write-Host "==> Downloading $($file.file_name) (MariaDB $ver)"
& curl.exe -fsSL -o mariadb.zip $file.file_download_url
if ($LASTEXITCODE -ne 0) { throw 'MariaDB download failed' }
if ((Get-Item mariadb.zip).Length -lt 50MB) { throw 'MariaDB download suspiciously small' }

Write-Host '==> Extracting'
Expand-Archive mariadb.zip -DestinationPath mariadbdist
$dist = (Get-ChildItem mariadbdist -Directory | Select-Object -First 1).FullName

# --- Initialize the data directory (root password 'root') --------------------
# Run inside the pristine distribution so basedir-relative paths resolve.
Write-Host '==> Initializing data directory'
& "$dist\bin\mariadb-install-db.exe" --datadir="$dist\data" --password=root | Out-Null
if ($LASTEXITCODE -ne 0) { throw "mariadb-install-db failed ($LASTEXITCODE)" }
if (-not (Test-Path "$dist\data\mysql")) { throw 'Data directory initialization incomplete' }
# install-db writes its own my.ini into the data dir - remove so only the
# module's core\mysql\my.ini is in effect
Remove-Item "$dist\data\my.ini" -ErrorAction SilentlyContinue

# --- Assemble the module layout ----------------------------------------------
Write-Host '==> Assembling module'
$m = 'module'
New-Item -ItemType Directory -Force "$m\core\mysql\bin", "$m\htpasswd\mysql", "$m\docs\licenses\mariadb" | Out-Null

Copy-Item "$dist\bin\mariadbd.exe" "$m\core\mysql\bin\mysqld_z.exe"
foreach ($pair in @(
    @('mysql.exe',      'mariadb.exe'),
    @('mysqladmin.exe', 'mariadb-admin.exe'),
    @('mysqldump.exe',  'mariadb-dump.exe'))) {
  $classic = $pair[0]; $modern = $pair[1]
  if (Test-Path "$dist\bin\$classic")     { Copy-Item "$dist\bin\$classic" "$m\core\mysql\bin\$classic" }
  elseif (Test-Path "$dist\bin\$modern")  { Copy-Item "$dist\bin\$modern"  "$m\core\mysql\bin\$classic" }
  else { throw "Client tool $modern not found in distribution" }
}
Copy-Item "$dist\bin\*.dll" "$m\core\mysql\bin\"
Copy-Item "$dist\share" "$m\core\mysql\share" -Recurse
Copy-Item "$dist\data"  "$m\core\mysql\data"  -Recurse
Copy-Item 'bundle\mariadb\my.ini' "$m\core\mysql\my.ini"
$major = ($ver -split '\.')[0]
(Get-Content 'bundle\mariadb\us_opt.ini') -replace '\{MAJOR\}', $major | Set-Content "$m\core\mysql\us_opt.ini"
Set-Content "$m\htpasswd\mysql\passwd.txt" -Value 'root' -NoNewline
if (Test-Path "$dist\COPYING") { Copy-Item "$dist\COPYING" "$m\docs\licenses\mariadb\COPYING" }

# --- Package -----------------------------------------------------------------
New-Item -ItemType Directory -Force $OutDir | Out-Null
Compress-Archive -Path "$m\core", "$m\htpasswd", "$m\docs" -DestinationPath "$OutDir\UniServer-Reload_mariadb_module.zip" -Force
Add-Content "$OutDir\module-versions.txt" "MariaDB $ver (module)"
Write-Host "==> Created $OutDir\UniServer-Reload_mariadb_module.zip (MariaDB $ver)"
