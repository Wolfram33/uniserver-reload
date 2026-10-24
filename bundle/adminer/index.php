<?php
/**
 * winpacho entry page for Adminer (home\us_opt1, the controller's "Adminer" button).
 *
 * adminer.php is the unmodified upstream single file (https://www.adminer.org/,
 * Apache License 2.0 or GPL 2, version in its file header), put here by
 * scripts\build-bundle.ps1. Everything winpacho changes lives in winpacho-adminer.php.
 */
declare(strict_types=1);

if (!is_file(__DIR__ . '/adminer.php')) {
    http_response_code(500);
    header('Content-Type: text/plain; charset=utf-8');
    echo "Adminer is missing: home\\us_opt1\\adminer.php was not found.\n"
        . "Copy the folder home\\us_opt1 from the winpacho bundle of your version into this server folder.\n";
    exit;
}

// Adminer's documented extension point: when this function exists, Adminer asks it
// for the object that answers its hooks (login, credentials, version check, CSP).
function adminer_object(): Adminer\Plugins
{
    require_once __DIR__ . '/winpacho-adminer.php';
    return WinpachoAdminer::plugins();
}

require __DIR__ . '/adminer.php';
