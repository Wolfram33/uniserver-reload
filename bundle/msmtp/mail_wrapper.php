<?php
/**
 * Uniform Server Reload - mail header wrapper
 *
 * Sits between PHP's mail() (sendmail_path) and msmtp. Reads the message
 * from STDIN, adds standard headers that spam filters expect but that
 * neither PHP nor msmtp add on this path (Date, Message-ID, MIME-Version,
 * Content-Type), then hands the message to msmtp.exe for delivery.
 *
 * Invoked via sendmail.bat; run with php.exe -n (no php.ini needed).
 */

$raw = stream_get_contents(STDIN);
if ($raw === false) { fwrite(STDERR, "mail_wrapper: could not read STDIN\n"); exit(1); }

// Split headers and body at the first empty line (tolerate LF and CRLF)
$eol = (strpos($raw, "\r\n") !== false) ? "\r\n" : "\n";
$sep = $eol . $eol;
$pos = strpos($raw, $sep);
if ($pos === false) { $headers = rtrim($raw, "\r\n"); $body = ''; }
else { $headers = substr($raw, 0, $pos); $body = substr($raw, $pos + strlen($sep)); }

$has = function ($name) use ($headers) {
    return preg_match('/^' . preg_quote($name, '/') . '\s*:/im', $headers) === 1;
};

$add = array();

if (!$has('Date')) {
    $add[] = 'Date: ' . date('r');
}

if (!$has('Message-ID')) {
    // Derive the id domain from the From header so it aligns with the sender
    $domain = 'localhost';
    if (preg_match('/^From\s*:.*?@([A-Za-z0-9.-]+)/im', $headers, $m)) {
        $domain = rtrim($m[1], '>. ');
    }
    $add[] = 'Message-ID: <' . bin2hex(random_bytes(16)) . '@' . $domain . '>';
}

if (!$has('MIME-Version')) {
    $add[] = 'MIME-Version: 1.0';
}

if (!$has('Content-Type')) {
    $add[] = 'Content-Type: text/plain; charset=UTF-8';
    if (!$has('Content-Transfer-Encoding')) {
        $add[] = 'Content-Transfer-Encoding: 8bit';
    }
}

if ($add) {
    $headers .= $eol . implode($eol, $add);
}
$message = $headers . $sep . $body;

// Forward to msmtp next to this script; -t reads recipients from the headers
$msmtp = __DIR__ . DIRECTORY_SEPARATOR . 'msmtp.exe';
$cfg   = __DIR__ . DIRECTORY_SEPARATOR . 'msmtprc.ini';
$cmd   = '"' . $msmtp . '" --file="' . $cfg . '" -t';

$proc = proc_open($cmd, array(0 => array('pipe', 'r'), 1 => STDOUT, 2 => STDERR), $pipes);
if (!is_resource($proc)) { fwrite(STDERR, "mail_wrapper: could not start msmtp\n"); exit(1); }
fwrite($pipes[0], $message);
fclose($pipes[0]);
exit(proc_close($proc));
