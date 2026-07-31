@echo off
rem Uniform Server Reload - sendmail shim for PHP mail()
rem Adds standard mail headers via mail_wrapper.php, then delivers via msmtp.
rem US_ROOTF and PHP_SELECT are set by UniController before Apache starts.
"%US_ROOTF%\core\%PHP_SELECT%\php.exe" -n "%US_ROOTF%\core\msmtp\mail_wrapper.php"
