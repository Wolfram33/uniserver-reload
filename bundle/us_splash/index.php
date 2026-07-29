<?php
$version="";

 if (getenv('HOME') == ''){                       // Not set when running as service
   $root= substr($_SERVER["DOCUMENT_ROOT"],0,-4); // this alternative with limitations
 }                                                // gets path to folder UniServerZ

 else{                                            // Set when run as standard program
   $root= getenv('HOME');                         // this is the ideal method to
 }                                                // get the path to folder UniServerZ


$file="$root\home\us_config\us_config.ini" ;     // Name and path of configuration file

if (file_exists($file) && is_readable($file)){   // Check file
  $settings=parse_ini_file($file,true);          // parse file into an array
  $version=$settings["APP"]["AppVersion"];       // get parameter
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

<!DOCTYPE HTML>
<html>
<head>
<meta http-equiv="Content-Type" content="text/html;charset=utf-8" />
<title>Uniform Server Reload - Splash page</title>
<meta name="Description" content="Uniform Server Reload - a maintained fork of The Uniform Server ZeroXV" />
<meta name="Keywords" content="Uniform Server Reload,The Uniform Server,ZeroXV,WAMP,Apache,MySQL,PHP" />
<link rel="stylesheet" type="text/css" href="css/style.css" media="screen" />
</head>
<body>

<div id="wrap">
  <div id="header">

     <a href="https://github.com/Wolfram33/uniserver-reload"><img src="images/logo.png" align="left" alt="Uniform Server Reload" /></a>
       <div id="header_txt2" >
         <div style="position:absolute;">
           <b>Reload <?php print "- ".$version; ?> </b><br />
           <?php print $apache_ver; ?> <br />
           MySQL 8.2.0 <br />
           PHP <?php print implode(" / ", $php_installed); ?> &nbsp;(active: <?php print $php_active; ?>)
         </div>
       </div>
  </div>

  <div id="content">
    <h2>Welcome to Uniform Server Reload</h2>
    <p><b>Uniform Server Reload</b> is a maintained community fork of The Uniform Server ZeroXV. This page and every other file are being served by Apache running from your <b>UniServerZ</b> folder. Documentation is included in <b>UniServerZ\docs</b> &mdash; see the <a href="/us_docs/manual/index.html">local documentation</a>.</p>
    <p>&nbsp;</p>
    <h2>This build</h2>
    <p>Everything below ships preinstalled in the all-in-one package &mdash; no further downloads or configuration needed.</p>
    <p>&nbsp;</p>
  <table>
   <tr valign="top">
   <td>
	<big><strong>Core</strong></big>
    <ul>
      <li> <b>UniController (Reload build)</b></li>
	  <li> <b><?php print $apache_ver; ?></b></li>
	  <li> <b>Mail client for PHP - msmtp</b></li>
	  <li> <b>Cron - Scheduler</b></li>
	</ul>
	<br />
	<big><strong>Databases</strong></big>
	<ul>
	  <li> <b>MySQL 8.2.0-community</b></li>
	</ul>
	<br />
	<big><strong>Database Admin and Backup</strong></big>
	<ul>
	  <li> <b>phpMyAdmin 5.2.1</b></li>
	  <li> MySQL Autobackup 1.0.2</li>
	</ul>
   </td>
   <td>
     &nbsp;&nbsp;&nbsp;&nbsp;
   </td>
   <td>
	<big><strong>PHP Versions (installed)</strong></big>
	<ul>
	  <li> <b>PHP installed as Apache module</b></li>
	  <li> <b>Active: PHP <?php print $php_active; ?></b></li>
<?php foreach ($php_installed as $v) { print "	  <li> PHP $v</li>\n"; } ?>
    </ul>
	<p>Switch versions in UniController: stop Apache, then <i>PHP &gt; Select PHP version</i>, then start Apache again.</p>
	<br />
	<big><strong>PHP Accelerator</strong></big>
	<ul>
	  <li> <b>Zend OpCache</b></li>
	</ul>
   </td>
   </tr>
  </table>
  </div>


  <div id="divider"> <a target="_1" href="https://github.com/Wolfram33/uniserver-reload">GitHub Repository</a> | <a target="_1" href="https://github.com/Wolfram33/uniserver-reload/releases/tag/latest">Latest Downloads</a> | <a target="_1" href="https://github.com/Wolfram33/uniserver-reload/issues">Issues / Support</a> | <a href="/us_docs/manual/index.html">Local Documentation</a> </div>

  <div id="content">
  <p>Uniform Server Reload is a portable WAMP package for Windows (64-bit): unpack it anywhere and Apache, MySQL and PHP are ready to run &mdash; no installation, no registry entries, no external dependencies. Updated builds with current PHP versions are published automatically on the <a target="_1" href="https://github.com/Wolfram33/uniserver-reload/releases/tag/latest">releases page</a>.</p>
  </div>

  <div id="divider">Originally developed by <a target="_1" href="https://www.uniformserver.com/">The Uniform Server Development Team</a> &mdash; Reload fork initiated by Rob de Roy</div>
</div>
</body>
</html>
