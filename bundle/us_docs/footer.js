// Footer below every manual page, inserted right after this <script> tag
// (see header.js); static markup only.
(function () {
  var html =
    '<table id="footer"><tr><td id="td_footer">' +
    '<div align="center">Originally developed by <a href="https://www.uniformserver.com/">The Uniform Server Development Team</a> &mdash; ' +
    '<a href="https://github.com/Wolfram33/winpacho">winpacho</a> (formerly Uniform Server Reload) initiated by Rob de Roy</div>' +
    '</td></tr></table>';
  var me = document.currentScript;
  if (me) { me.insertAdjacentHTML('afterend', html); }
})();
