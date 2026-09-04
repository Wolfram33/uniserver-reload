-- phpMyAdmin control user for Uniform Server Reload.
--
-- home\us_opt1\config.inc.php uses 'pma' as controluser for the
-- configuration storage (bookmarks, relations, history, ...), with the same
-- password as root: UniController changes both passwords together (MySQL >
-- Change root password) and restores both (Restore root password). The
-- tables come from phpmyadmin-create_tables.sql, run right after this file.
--
-- Executed once by the module packaging scripts (scripts\package-*-module.ps1)
-- against the freshly initialized data directory; works on MariaDB and MySQL.
CREATE USER IF NOT EXISTS 'pma'@'localhost' IDENTIFIED BY 'root';
GRANT ALL PRIVILEGES ON *.* TO 'pma'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
