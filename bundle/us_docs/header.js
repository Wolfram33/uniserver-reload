// Banner and notice above every manual page. Inserted right after this
// <script> tag (the pages load it synchronously in place), without
// document.write; the markup is static, no user data goes into it.
(function () {
  var html =
    '<table id="banner_table"><tr><td>' +
    ' <div id="banner_div">' +
    '   <img src="common/images/us_zero_logo.png" alt="winpacho" />' +
    '   <span id="banner_txt">winpacho <small id="banner_txt_small">Doc version 1.1.2</small></span>' +
    ' </div>' +
    '</td></tr></table>' +
    '<div style="background:#fff3cd;border:1px solid #e0c060;color:#5c4a00;padding:8px 14px;font-size:13px;font-family:Arial,sans-serif;">' +
    '<b>Note:</b> You are running <b>winpacho</b> (formerly Uniform Server Reload), a maintained successor of The Uniform Server with Apache, MariaDB and PHP 8.3/8.4/8.5 preinstalled in a single package. ' +
    'This manual was written for the original ZeroXV 15.0.2 release &mdash; download and plugin instructions on these pages may be outdated. ' +
    'Current downloads and information: <a href="https://github.com/Wolfram33/winpacho" target="_blank" rel="noopener">github.com/Wolfram33/winpacho</a>' +
    '</div>';
  var me = document.currentScript;
  if (me) { me.insertAdjacentHTML('afterend', html); }
})();
