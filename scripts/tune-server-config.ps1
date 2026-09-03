# Server tuning for UniServer Reload: rotating Apache logs with bounded disk
# use, OPcache on in every PHP version, Apache/MySQL limits sized for a small
# business server instead of a developer laptop.
#
# build-bundle.ps1 runs this for every bundle. It also works stand-alone on an
# existing installation (with Apache and MySQL stopped):
#
#   powershell -ExecutionPolicy Bypass -File tune-server-config.ps1 -Root C:\UniServer-Reload
#
# Idempotent: running it again changes nothing. Every change is verified and
# the script stops with a clear message when a file does not look as expected.
#
# What it changes
#   core\apache2\conf\httpd.conf, extra\httpd-ssl.conf, extra\httpd-vhosts.conf
#       ErrorLog/CustomLog go through bin\rotatelogs.exe: logs\<name> stays the
#       current file (hard link), logs\rotated\ holds a ring of older parts
#       (access: 10 x 20M, error: 5 x 10M) - the logs can never fill the disk.
#   core\apache2\conf\extra\httpd-mpm.conf
#       400 worker threads (was 150) and an 8 MB thread stack for PHP.
#   core\php8x\php_production.ini, php_development.ini, php_test.ini
#       OPcache enabled with 256M cache / 20000 files, realpath cache on.
#       The zend_extension line uses the php_opcache.dll form the controller's
#       PHP > Accelerator toggle understands.
#   core\mysql\my.ini (MySQL flavour; the MariaDB module ships its own)
#       connections, caches, redo log and binlog retention for server load.
param([Parameter(Mandatory = $true)][string]$Root)
$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path $Root).Path
$apache = Join-Path $Root 'core\apache2'
if (-not (Test-Path (Join-Path $apache 'conf\httpd.conf'))) { throw "No Uniform Server installation at $Root (core\apache2\conf\httpd.conf missing)" }

# Rotating log settings: the ring of older parts lives in logs\rotated\
$ACCESS_FILES = 10; $ACCESS_SIZE = '20M'
$ERROR_FILES  = 5;  $ERROR_SIZE  = '10M'

function Read-Text([string]$path) { Get-Content $path -Raw }
function Write-Text([string]$path, [string]$text) { Set-Content $path -Value $text -NoNewline }

# Newline style of a file (the stock files mix CRLF and LF between files)
function Get-Newline([string]$text) { if ($text -match "`r`n") { "`r`n" } else { "`n" } }

# Piped log program for one log file: keeps logs\<name> as the current file
# (-L hard link) and rotates through logs\rotated\<name>[.1 .. .N-1].
function Get-RotatingLog([string]$name, [int]$files, [string]$size) {
  "|bin/rotatelogs.exe -n $files -D -L logs/$name logs/rotated/$name $size"
}

# Replaces the first match of $pattern (one whole line) with $replacement and
# comments out every later match, so a setting is never active twice.
# Returns the new text and the number of matches. (A plain loop instead of a
# MatchEvaluator: a scriptblock delegate cannot report a count back reliably.)
function Set-FirstMatch([string]$text, [string]$pattern, [string]$replacement, [string]$comment) {
  $hits = [regex]::Matches($text, $pattern)
  if ($hits.Count -eq 0) { return @($text, 0) }
  $sb = New-Object System.Text.StringBuilder
  $pos = 0
  for ($i = 0; $i -lt $hits.Count; $i++) {
    $m = $hits[$i]
    [void]$sb.Append($text.Substring($pos, $m.Index - $pos))
    if ($i -eq 0) { [void]$sb.Append($replacement) }
    else { [void]$sb.Append($comment + ($m.Value -replace '^[;#\t ]*', '')) }
    $pos = $m.Index + $m.Length
  }
  [void]$sb.Append($text.Substring($pos))
  return @($sb.ToString(), $hits.Count)
}

# Makes "$line" (key = value or key=value) the active setting for its key:
# the first occurrence of the key - commented out or not - becomes $line,
# later occurrences are commented out, a missing key is appended.
# $comment is the comment character of the file (';' php.ini, '#' my.ini).
function Set-IniLine([string]$text, [string]$line, [string]$comment = ';') {
  $key = ($line -split '=', 2)[0].Trim()
  $r = Set-FirstMatch $text ('(?m)^[;#\t ]*' + [regex]::Escape($key) + '[\t ]*=.*?(?=\r?$)') $line $comment
  if ($r[1] -eq 0) { $nl = Get-Newline $text; return $text.TrimEnd() + $nl + $line + $nl }
  return $r[0]
}

function Assert-IniLine([string]$text, [string]$line, [string]$file) {
  if ($text -notmatch ('(?m)^' + [regex]::Escape($line) + '[\t ]*\r?$')) { throw "$file`: failed to set '$line'" }
}

# --- Servers must be stopped: the files below are open while they run ---------
foreach ($p in 'httpd_z', 'mysqld_z', 'rotatelogs') {
  if (Get-Process -Name $p -ErrorAction SilentlyContinue) { throw "$p.exe is running - stop Apache and MySQL (UniController or the Windows services) before running this script" }
}

# =============================================================================
# Apache: rotating logs
# =============================================================================
if (-not (Test-Path (Join-Path $apache 'bin\rotatelogs.exe'))) { throw 'core\apache2\bin\rotatelogs.exe is missing - the Apache build in this installation has no rotatelogs, log rotation cannot be enabled' }
$logs = Join-Path $apache 'logs'
New-Item -ItemType Directory -Force (Join-Path $logs 'rotated') | Out-Null

# Existing plain log files become part 0 of their ring so no history is lost
# (rotatelogs appends to an existing part 0 and would otherwise delete the
# plain file when it creates the hard link).
foreach ($name in 'access.log', 'error.log', 'access_ssl.log', 'error_ssl.log') {
  $plain = Join-Path $logs $name
  $part0 = Join-Path $logs "rotated\$name"
  if (-not (Test-Path $plain)) { continue }
  $links = (& fsutil.exe hardlink list $plain | Measure-Object).Count
  if ($links -gt 1) { continue }                        # already a rotation link
  $old = Get-Content $plain -Raw
  if (-not $old) { Remove-Item $plain -Force; continue }
  if (Test-Path $part0) { Add-Content $part0 -Value $old -NoNewline; Remove-Item $plain -Force }
  else { Move-Item $plain $part0 -Force }
  Write-Host "   kept existing $name as logs\rotated\$name"
}

$accessPipe = Get-RotatingLog 'access.log' $ACCESS_FILES $ACCESS_SIZE
$errorPipe  = Get-RotatingLog 'error.log'  $ERROR_FILES  $ERROR_SIZE

# httpd.conf: main error log and access log
$conf = Join-Path $apache 'conf\httpd.conf'
$t = Read-Text $conf
$nl = Get-Newline $t
$note = "# UniServer Reload: logs rotate in place through bin\rotatelogs.exe. logs\<name> is$nl" +
        "# always the current file (hard link); logs\rotated\ keeps a ring of older parts$nl" +
        "# ($ACCESS_FILES x $ACCESS_SIZE access, $ERROR_FILES x $ERROR_SIZE error), so the logs can never fill the disk.$nl"
$t = $t -replace '(?m)^ErrorLog "logs/error\.log"(\r?)$', ('ErrorLog "' + $errorPipe + '"$1')
$t = $t -replace '(?m)^([\t ]*)CustomLog "logs/access\.log" combined(\r?)$', ('$1CustomLog "' + $accessPipe + '" combined$2')
if ($t -notmatch 'UniServer Reload: logs rotate in place') { $t = $t -replace '(?m)^(ErrorLog ")', ($note + '$1') }
Write-Text $conf $t
$t = Read-Text $conf
if ($t -notmatch ('(?m)^ErrorLog "' + [regex]::Escape($errorPipe) + '"'))                 { throw 'httpd.conf: ErrorLog rotation patch failed' }
if ($t -notmatch ('(?m)^\s*CustomLog "' + [regex]::Escape($accessPipe) + '" combined'))   { throw 'httpd.conf: CustomLog rotation patch failed' }

# httpd-vhosts.conf: the default vhosts log to the main files (same pipe
# command - Apache shares one rotatelogs process per identical command)
$vconf = Join-Path $apache 'conf\extra\httpd-vhosts.conf'
$t = Read-Text $vconf
$t = $t -replace '(?m)^([\t ]*)ErrorLog "logs/error\.log"(\r?)$',          ('$1ErrorLog "' + $errorPipe + '"$2')
$t = $t -replace '(?m)^([\t ]*)CustomLog "logs/access\.log" common(\r?)$', ('$1CustomLog "' + $accessPipe + '" common$2')
Write-Text $vconf $t
$t = Read-Text $vconf
if ($t -match '(?m)^\s*(ErrorLog|CustomLog) "logs/') { throw 'httpd-vhosts.conf: plain log files remain after the rotation patch' }
if ($t -notmatch ('(?m)^\s*CustomLog "' + [regex]::Escape($accessPipe) + '" common')) { throw 'httpd-vhosts.conf: CustomLog rotation patch failed' }

# httpd-ssl.conf: the SSL default host keeps its own log names
$sconf = Join-Path $apache 'conf\extra\httpd-ssl.conf'
$sslErrorPipe  = Get-RotatingLog 'error_ssl.log'  $ERROR_FILES  $ERROR_SIZE
$sslAccessPipe = Get-RotatingLog 'access_ssl.log' $ACCESS_FILES $ACCESS_SIZE
$t = Read-Text $sconf
$t = $t -replace '(?m)^ErrorLog "\$\{US_ROOTF\}/core/apache2/logs/error_ssl\.log"(\r?)$',      ('ErrorLog "' + $sslErrorPipe + '"$1')
$t = $t -replace '(?m)^TransferLog "\$\{US_ROOTF\}/core/apache2/logs/access_ssl\.log"(\r?)$', ('TransferLog "' + $sslAccessPipe + '"$1')
Write-Text $sconf $t
$t = Read-Text $sconf
if ($t -notmatch ('(?m)^ErrorLog "' + [regex]::Escape($sslErrorPipe) + '"'))       { throw 'httpd-ssl.conf: ErrorLog rotation patch failed' }
if ($t -notmatch ('(?m)^TransferLog "' + [regex]::Escape($sslAccessPipe) + '"'))   { throw 'httpd-ssl.conf: TransferLog rotation patch failed' }
Write-Host "==> Apache logs rotate: logs\<name> current, logs\rotated\ ring ($ACCESS_FILES x $ACCESS_SIZE access, $ERROR_FILES x $ERROR_SIZE error)"

# =============================================================================
# Apache: worker threads for server load
# =============================================================================
# mpm_winnt serves every connection from one thread pool. 150 threads are
# fine for one developer; chat apps that keep long-polling connections open
# for every user eat them quickly. 8 MB thread stacks are the PHP-on-Windows
# recommendation against stack overflows in deep framework call chains
# (reserved address space only - committed as used).
$mpmConf = Join-Path $apache 'conf\extra\httpd-mpm.conf'
$t = Read-Text $mpmConf
$nl = Get-Newline $t
$winnt = '(?s)(<IfModule mpm_winnt_module>.*?</IfModule>)'
if ($t -notmatch $winnt) { throw 'httpd-mpm.conf: mpm_winnt block not found' }
$block = $Matches[1]
$new = $block -replace '(?m)^([\t ]*)ThreadsPerChild[\t ]+\d+(\r?)$', '$1ThreadsPerChild        400$2'
if ($new -notmatch 'ThreadStackSize') { $new = $new -replace '(?m)^([\t ]*)(ThreadsPerChild[\t ]+400)(\r?)$', ('$1$2$3' + $nl + '$1ThreadStackSize    8388608$3') }
if ($new -ne $block) { Write-Text $mpmConf ($t.Replace($block, $new)) }
$t = Read-Text $mpmConf
if ($t -notmatch '(?s)<IfModule mpm_winnt_module>.*?ThreadsPerChild\s+400.*?ThreadStackSize\s+8388608.*?</IfModule>') { throw 'httpd-mpm.conf: mpm_winnt tuning failed' }
Write-Host '==> Apache mpm_winnt: 400 worker threads, 8 MB thread stack'

# =============================================================================
# PHP: OPcache on in every version
# =============================================================================
# Without OPcache every request recompiles every PHP file - the classic
# bottleneck once several people work at the same time. PHP 8.5 has OPcache
# built in (no DLL, on by default); older versions need the zend_extension
# line, written in the php_opcache.dll form the controller's toggle expects.
$OPCACHE_LINES = @(
  'opcache.enable=1',
  'opcache.enable_cli=0',
  'opcache.memory_consumption=256',
  'opcache.interned_strings_buffer=16',
  'opcache.max_accelerated_files=20000',
  'opcache.validate_timestamps=1',
  'realpath_cache_size = 4096k',
  'realpath_cache_ttl = 120'
)
$phpDirs = Get-ChildItem (Join-Path $Root 'core') -Directory -Filter 'php8*' | Sort-Object Name
if (-not $phpDirs) { throw 'No core\php8x folder found' }
foreach ($dir in $phpDirs) {
  $ver = $dir.Name
  $dll = Join-Path $dir.FullName 'extensions\php_opcache.dll'
  $hasDll = Test-Path $dll
  foreach ($iniName in 'php_production.ini', 'php_test.ini', 'php_development.ini') {
    $ini = Join-Path $dir.FullName $iniName
    if (-not (Test-Path $ini)) { continue }
    $t = Read-Text $ini
    $nl = Get-Newline $t
    if ($hasDll) {
      $zendLine = 'zend_extension=${US_ROOTF}/core/' + $ver + '/extensions/php_opcache.dll'
      # Replace whatever OPcache zend_extension line exists (";zend_extension=opcache"
      # from php.ini-production, the upstream DLL path form, or an active one)
      $r = Set-FirstMatch $t '(?m)^[;\t ]*zend_extension[\t ]*=[\t ]*\S*opcache\S*[\t ]*(?=\r?$)' $zendLine ';'
      $t = $r[0]
      if ($r[1] -eq 0) { $t = $t.TrimEnd() + $nl + $nl + '; UniServer Reload - OPcache' + $nl + $zendLine + $nl }
    }
    else {
      # Built-in OPcache (PHP 8.5+): a zend_extension line would only produce a
      # startup warning about a missing DLL
      $t = $t -replace '(?m)^zend_extension[\t ]*=[\t ]*(\S*opcache\S*)[\t ]*(?=\r?$)', ';zend_extension=$1'
    }
    foreach ($line in $OPCACHE_LINES) { $t = Set-IniLine $t $line }
    # Development: pick up file changes immediately; production/test: every 2 s
    $freq = if ($iniName -eq 'php_development.ini') { 'opcache.revalidate_freq=0' } else { 'opcache.revalidate_freq=2' }
    $t = Set-IniLine $t $freq
    Write-Text $ini $t
    $t = Read-Text $ini
    foreach ($line in $OPCACHE_LINES + @($freq)) { Assert-IniLine $t $line "$ver\$iniName" }
    if ($hasDll) {
      Assert-IniLine $t $zendLine "$ver\$iniName"
      if ($t -notmatch '(?m)^zend_extension=.*php_opcache\.dll') { throw "$ver\$iniName`: OPcache zend_extension line not active" }
    }
    elseif ($t -match '(?m)^zend_extension=.*opcache') { throw "$ver\$iniName`: zend_extension line present although $ver has no php_opcache.dll" }
  }
  # Prove it with the interpreter itself when it is there (it is in every bundle)
  $php = Join-Path $dir.FullName 'php.exe'
  if (Test-Path $php) {
    $env:US_ROOTF = $Root -replace '\\', '/'
    # Single quotes only: the argument must survive both PowerShell editions
    $probe = "exit((extension_loaded('Zend OPcache') && ini_get('opcache.enable') === '1') ? 0 : 1);"
    & $php -n -c (Join-Path $dir.FullName 'php_production.ini') -r $probe
    if ($LASTEXITCODE -ne 0) { throw "$ver`: OPcache does not load with php_production.ini" }
  }
  Write-Host "==> $ver`: OPcache on (256M, 20000 files), realpath cache on$(if (-not $hasDll) { ' - built into this PHP' })"
}

# =============================================================================
# MySQL: connections, caches, redo log, binlog retention
# =============================================================================
# 400 Apache threads can open 400 connections in a burst; MySQL's default
# max_connections (151) would answer 'Too many connections'. Binlogs are kept
# 7 days instead of 30: on a single server they only serve point-in-time
# recovery, and 30 days of a busy CRM's binlogs are gigabytes.
$myIni = Join-Path $Root 'core\mysql\my.ini'
if (-not (Test-Path $myIni)) { Write-Host '==> core\mysql\my.ini not found - MySQL tuning skipped' }
else {
  $t = Read-Text $myIni
  if ($t -match 'MariaDB configuration for Uniform Server Reload') {
    Write-Host '==> MariaDB module my.ini detected - it ships tuned, nothing to do'
  }
  elseif ($t -notmatch '(?m)^\[mysqld\]') { throw 'core\mysql\my.ini: no [mysqld] section' }
  else {
    $nl = Get-Newline $t
    $MYSQL_LINES = @(
      'max_connections = 500',
      'thread_cache_size = 64',
      'table_open_cache = 4000',
      'table_definition_cache = 2000',
      'tmp_table_size = 128M',
      'max_heap_table_size = 128M',
      'innodb_io_capacity = 1000',
      'innodb_io_capacity_max = 2000'
    )
    # MySQL 8 only settings (the MariaDB module has its own my.ini)
    if ($t -match '(?m)^innodb_redo_log_capacity') { $MYSQL_LINES += 'innodb_redo_log_capacity = 256M' }
    if ($t -match '(?m)^authentication_policy')    { $MYSQL_LINES += @('binlog_expire_logs_seconds = 604800', 'max_binlog_size = 256M') }
    # Keys already in [mysqld] are changed in place; new ones are added as a
    # block at the end of [mysqld] (before [mysqldump]) so they cannot land in
    # another section.
    $mysqldEnd = [regex]::Match($t, '(?m)^\[mysqldump\]')
    if (-not $mysqldEnd.Success) { throw 'core\mysql\my.ini: [mysqldump] section not found (needed as the end marker of [mysqld])' }
    $missing = @()
    foreach ($line in $MYSQL_LINES) {
      $key = ($line -split '=', 2)[0].Trim()
      if ($t -match ('(?m)^[#\t ]*' + [regex]::Escape($key) + '[\t ]*=')) { $t = Set-IniLine $t $line '#' } else { $missing += $line }
    }
    if ($missing) {
      $block = '# UniServer Reload - server load settings (see README, "Sized for a server")' + $nl + ($missing -join $nl) + $nl + $nl
      $pos = [regex]::Match($t, '(?m)^\[mysqldump\]').Index
      $t = $t.Insert($pos, $block)
    }
    if ($t -notmatch 'Server sizing: the InnoDB buffer pool') {
      $hint = '# Server sizing: the InnoDB buffer pool should hold the hot data set. On a box' + $nl +
              '# shared with Apache/PHP use 25-50% of RAM (16 GB box: 2G-4G); on a dedicated' + $nl +
              '# database server up to 70%. 512M is the developer-laptop default.' + $nl
      $t = $t -replace '(?m)^(innodb_buffer_pool_size = )', ($hint + '$1')
    }
    Write-Text $myIni $t
    $t = Read-Text $myIni
    foreach ($line in $MYSQL_LINES) { Assert-IniLine $t $line 'core\mysql\my.ini' }
    if ($t -notmatch 'Server sizing: the InnoDB buffer pool') { throw 'core\mysql\my.ini: buffer pool sizing hint missing' }
    Write-Host '==> MySQL my.ini: 500 connections, larger caches, 256M redo log, 7-day binlog retention'
  }
}

Write-Host "==> Server tuning applied to $Root"
