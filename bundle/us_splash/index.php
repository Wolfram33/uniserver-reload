<?php
$version="";

 if (getenv('HOME') == ''){                       // Not set when running as service
   $root= substr($_SERVER["DOCUMENT_ROOT"],0,-4); // this alternative with limitations
 }                                                // gets path to folder UniServerZ

 else{                                            // Set when run as standard program
   $root= getenv('HOME');                         // this is the ideal method to
 }                                                // get the path to folder UniServerZ

function us_h($text){                             // escape for HTML output
  return htmlspecialchars((string)$text, ENT_QUOTES, 'UTF-8');
}

$file="$root\home\us_config\us_config.ini" ;     // Name and path of configuration file

if (file_exists($file) && is_readable($file)){   // Check file
  $settings=parse_ini_file($file,true);          // parse file into an array
  if ($settings !== false && isset($settings["APP"]["AppVersion"])){
    $version=$settings["APP"]["AppVersion"];     // get parameter
  }
}

// Installed PHP versions: scan core/php* folders so this list can never go stale
$php_installed = array();
foreach (glob("$root/core/php[0-9][0-9]", GLOB_ONLYDIR) as $dir) {
  $name = basename($dir);                        // e.g. php84
  $php_installed[] = substr($name,3,1).".".substr($name,4);  // -> 8.4
}
rsort($php_installed);

$php_active  = PHP_VERSION;                                       // currently running version
$apache_ver  = function_exists('apache_get_version') ? apache_get_version() : 'Apache';
?>

<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>Uniform Server Reload - Splash page</title>
<meta name="Description" content="Uniform Server Reload - a maintained fork of The Uniform Server ZeroXV" />
<meta name="Keywords" content="Uniform Server Reload,The Uniform Server,ZeroXV,WAMP,Apache,MySQL,PHP" />
<link rel="icon" href="favicon.ico" />
<link rel="stylesheet" type="text/css" href="css/style.css" media="screen" />
</head>

<body>

<a class="skip-link" href="#main">Skip to main content</a>

<div id="wrap">
  <header id="header">
    <a href="https://github.com/Wolfram33/uniserver-reload">
      <img src="images/logo.png" width="465" height="93" alt="Uniform Server Reload - a lightweight WAMP server solution, reloaded" />
    </a>
    <div class="server-info">
      <strong>Reload<?php if ($version !== ""){ print " - ".us_h($version); } ?></strong><br />
      <?php print us_h($apache_ver); ?><br />
      MySQL 8.2.0<br />
      <?php
        if (count($php_installed) !== 0){
          print "PHP ".us_h(implode(" / ", $php_installed))." (active: ".us_h($php_active).")";
        } else {
          print "PHP ".us_h($php_active);
        }
      ?>
    </div>
  </header>

  <main id="main">
    <h1>Welcome to Uniform Server Reload</h1>
    <p><strong>Uniform Server Reload</strong> is a maintained community fork of The Uniform Server ZeroXV. This page and every other file are being served by Apache running from your <strong>UniServerZ</strong> folder. Documentation is included in <strong>UniServerZ\docs</strong> &mdash; see the <a href="/us_docs/manual/index.html">local documentation</a>.</p>

    <h2>This build</h2>
    <p>Everything below ships preinstalled in the all-in-one package &mdash; no further downloads or configuration needed.</p>

    <div class="columns">
      <section class="col">
        <h3>Core</h3>
        <ul>
          <li><strong>UniController (Reload build)</strong></li>
          <li><strong><?php print us_h($apache_ver); ?></strong></li>
          <li><strong>Mail client for PHP - msmtp</strong></li>
          <li><strong>Cron - Scheduler</strong></li>
        </ul>
        <h3>Databases</h3>
        <ul>
          <li><strong>MySQL 8.2.0-community</strong></li>
        </ul>
        <h3>Database Admin and Backup</h3>
        <ul>
          <li><strong>phpMyAdmin 5.2.1</strong></li>
          <li>MySQL Autobackup 1.0.2</li>
        </ul>
      </section>

      <section class="col">
        <h3>PHP Versions (installed)</h3>
        <ul>
          <li><strong>PHP installed as Apache module</strong></li>
          <li><strong>Active: PHP <?php print us_h($php_active); ?></strong></li>
<?php foreach ($php_installed as $v) { print "          <li>PHP ".us_h($v)."</li>\n"; } ?>
        </ul>
        <p>Switch versions in UniController: stop Apache, then <em>PHP &gt; Select PHP version</em>, then start Apache again.</p>
        <h3>HTTPS</h3>
        <p><a href="https://localhost">https://localhost</a> works out of the box and serves the same <strong>www</strong> folder as http. To remove the browser warning: <em>Apache &gt; Apache SSL &gt; Trust certificate in Windows</em>, confirm with Yes, then restart the browser completely.</p>
        <h3>PHP Accelerator</h3>
        <ul>
          <li><strong>Zend OpCache</strong></li>
        </ul>
      </section>
    </div>
  </main>

  <footer>
    <p class="footer-links"><a target="_1" rel="noopener" href="https://github.com/Wolfram33/uniserver-reload">GitHub Repository</a> | <a target="_1" rel="noopener" href="https://github.com/Wolfram33/uniserver-reload/releases/tag/latest">Latest Downloads</a> | <a target="_1" rel="noopener" href="https://github.com/Wolfram33/uniserver-reload/issues">Issues / Support</a> | <a href="/us_docs/manual/index.html">Local Documentation</a></p>
    <p>Uniform Server Reload is a portable WAMP package for Windows (64-bit): unpack it anywhere and Apache, MySQL and PHP are ready to run &mdash; no installation, no registry entries, no external dependencies. Updated builds with current PHP versions are published automatically on the <a target="_1" rel="noopener" href="https://github.com/Wolfram33/uniserver-reload/releases/tag/latest">releases page</a>.</p>
    <p class="credits">Originally developed by <a target="_1" rel="noopener" href="https://www.uniformserver.com/">The Uniform Server Development Team</a> &mdash; Reload fork initiated by Rob de Roy</p>
  </footer>
</div>
</body>
</html>
