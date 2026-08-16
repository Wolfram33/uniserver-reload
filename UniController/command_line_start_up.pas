unit command_line_start_up;

{#############################################################################
'# Name: command_line_start_up.pas
'# Developed By: The Uniform Server Development Team
'# Web: https://www.uniformserver.com
'#############################################################################}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms,
  default_config_vars,
  us_common_procedures,
  us_common_functions;

procedure us_command_line_start_up; //UniController started with parameters

implementation

uses
  main_unit;
{****************************************************************************
 us_command_line_start_up:
  This procedure starts, stops and restarts the servers via UniController
  command line parameters and reports server status. A single parameter is
  passed to UniController, this is executed and UniController is terminated
  with an exit code so the servers can be controlled from scripts (batch
  files, PowerShell, CI pipelines).
  Note: A special command line parameter "pc_win_start" is covered seperately
        in section TMain.FormCreate
  Note: It is assumed the servers have been configured and are run-able.

  Canonical parameters (legacy underscore form):
   start_apache   stop_apache   restart_apache
   start_mysql    stop_mysql    restart_mysql
   start_both     stop_both     restart_both
   status         help

  Also accepted:
   --start-apache style: leading dashes/slashes, dashes for underscores
   start_all / stop_all / restart_all as aliases for the _both commands

  Exit codes:
   Actions: 0 = requested state reached, 1 = failed, 2 = unknown parameter
   status : bit mask - 0 = all running, +1 = Apache not running,
            +2 = MySQL/MariaDB not running

  Note: UniController is a GUI application - an interactive shell does not
        wait for it. To read the exit code use
         cmd        : start /wait UniController.exe start_apache
         PowerShell : $p = Start-Process .\UniController.exe start_apache -PassThru
                      $p.WaitForExit(); $p.ExitCode
        Inside a batch file cmd waits automatically.
        Do NOT use Start-Process -Wait: it waits for child processes too,
        i.e. for a started server itself, and blocks until the server stops.
============================================================================}
const
  CLI_EXIT_OK        = 0;  // Requested operation succeeded
  CLI_EXIT_FAILED    = 1;  // Server did not reach the requested state
  CLI_EXIT_BAD_PARAM = 2;  // Unknown command line parameter

  //status command exit code bit mask
  CLI_STATUS_APACHE_DOWN = 1;  // Apache not running (or not installed)
  CLI_STATUS_MYSQL_DOWN  = 2;  // MySQL/MariaDB not running (or not installed)

{****************************************************************************
 cli_normalize_command:
  Map all accepted command spellings onto the canonical underscore form:
  --restart-apache, /restart-apache, restart-apache -> restart_apache
============================================================================}
function cli_normalize_command(raw:string): string;
var
  cmd: string;
begin
  cmd := LowerCase(Trim(raw));
  While (cmd <> '') and ((cmd[1] = '-') or (cmd[1] = '/')) do // Strip --/-// prefixes
    Delete(cmd, 1, 1);
  cmd := StringReplace(cmd, '-', '_', [rfReplaceAll]);        // Dashes to underscores

  //Convenience aliases
  If (cmd = 'start_all')   Then cmd := 'start_both';
  If (cmd = 'stop_all')    Then cmd := 'stop_both';
  If (cmd = 'restart_all') Then cmd := 'restart_both';
  If (cmd = '?') or (cmd = 'h') Then cmd := 'help';

  cli_normalize_command := cmd;
end;
{--- End cli_normalize_command ----------------------------------------------}

{****************************************************************************
 cli_known_command: True for every command this unit implements
============================================================================}
function cli_known_command(cmd:string): Boolean;
begin
  cli_known_command :=
       (cmd = 'start_apache') or (cmd = 'stop_apache') or (cmd = 'restart_apache')
    or (cmd = 'start_mysql')  or (cmd = 'stop_mysql')  or (cmd = 'restart_mysql')
    or (cmd = 'start_both')   or (cmd = 'stop_both')   or (cmd = 'restart_both')
    or (cmd = 'status')       or (cmd = 'help');
end;
{--- End cli_known_command --------------------------------------------------}

{****************************************************************************
 cli_print_usage: Print command line help to the calling console
============================================================================}
procedure cli_print_usage;
begin
  cli_write_line('UniController command line usage: UniController.exe <command>');
  cli_write_line('');
  cli_write_line('Commands (also accepted as --command form, e.g. --restart-apache):');
  cli_write_line('  start_apache | stop_apache | restart_apache');
  cli_write_line('  start_mysql  | stop_mysql  | restart_mysql');
  cli_write_line('  start_both   | stop_both   | restart_both   (aliases: *_all)');
  cli_write_line('  status       Report server state');
  cli_write_line('  help         Show this help');
  cli_write_line('');
  cli_write_line('Exit codes: 0 = success, 1 = operation failed, 2 = unknown command');
  cli_write_line('status exit code: 0 = all running, +1 = Apache down, +2 = MySQL/MariaDB down');
  cli_write_line('');
  cli_write_line('Note: interactive shells do not wait for GUI programs. To read the exit code:');
  cli_write_line('  cmd        : start /wait UniController.exe <command>');
  cli_write_line('  PowerShell : $p = Start-Process .\UniController.exe <command> -PassThru');
  cli_write_line('               $p.WaitForExit(); $p.ExitCode');
  cli_write_line('Batch files wait automatically. Do not use Start-Process -Wait: it also');
  cli_write_line('waits for started servers and only returns when the server stops.');
end;
{--- End cli_print_usage ----------------------------------------------------}

{****************************************************************************
 cli_status_exit_code:
  Print the state of both servers and build the status exit code bit mask.
============================================================================}
function cli_status_exit_code: Integer;
var
  code: Integer;
begin
  code := 0;

  //Apache
  If DirectoryExists(US_APACHE) Then
   begin
     If ApacheRunning() Then
       cli_write_line('Apache: running')
     Else
      begin
        cli_write_line('Apache: stopped');
        code := code or CLI_STATUS_APACHE_DOWN;
      end;
   end
  Else
   begin
     cli_write_line('Apache: not installed');
     code := code or CLI_STATUS_APACHE_DOWN;
   end;

  //MySQL/MariaDB
  If DirectoryExists(US_MYSQL) Then
   begin
     If MysqlRunning() Then
       cli_write_line(US_MYMAR_TXT + ': running')
     Else
      begin
        cli_write_line(US_MYMAR_TXT + ': stopped');
        code := code or CLI_STATUS_MYSQL_DOWN;
      end;
   end
  Else
   begin
     cli_write_line(US_MYMAR_TXT + ': not installed');
     code := code or CLI_STATUS_MYSQL_DOWN;
   end;

  cli_status_exit_code := code;
end;
{--- End cli_status_exit_code -----------------------------------------------}

{****************************************************************************
 cli_apache_action:
  Execute action (start/stop/restart) on Apache. Returns True when Apache
  reached the requested state. The final state is printed to the console.
============================================================================}
function cli_apache_action(action:string): Boolean;
begin
  cli_apache_action := False;

  If not DirectoryExists(US_APACHE) Then
   begin
     cli_write_line('Apache: not installed');
     Exit;
   end;

  If (action = 'stop') or (action = 'restart') Then us_kill_apache_program;
  If (action = 'restart') Then sleep(1000);              // Allow port to be released
  If (action = 'start') or (action = 'restart') Then us_start_apache_program;

  If (action = 'stop') Then
    cli_apache_action := not ApacheRunning()
  Else
    cli_apache_action := ApacheRunning();

  //Report final state
  If ApacheRunning() Then
    cli_write_line('Apache: running')
  Else
    cli_write_line('Apache: stopped');
end;
{--- End cli_apache_action --------------------------------------------------}

{****************************************************************************
 cli_mysql_action:
  Execute action (start/stop/restart) on MySQL/MariaDB. Returns True when
  the server reached the requested state. Final state printed to console.
============================================================================}
function cli_mysql_action(action:string): Boolean;
begin
  cli_mysql_action := False;

  If not DirectoryExists(US_MYSQL) Then
   begin
     cli_write_line(US_MYMAR_TXT + ': not installed');
     Exit;
   end;

  If (action = 'stop') or (action = 'restart') Then us_clean_stop_mysql_program;
  If (action = 'restart') Then sleep(1000);              // Allow port to be released
  If (action = 'start') or (action = 'restart') Then us_start_mysql_program;

  If (action = 'stop') Then
    cli_mysql_action := not MysqlRunning()
  Else
    cli_mysql_action := MysqlRunning();

  //Report final state
  If MysqlRunning() Then
    cli_write_line(US_MYMAR_TXT + ': running')
  Else
    cli_write_line(US_MYMAR_TXT + ': stopped');
end;
{--- End cli_mysql_action ---------------------------------------------------}

procedure us_command_line_start_up;
var
  cmd    : string;
  action : string;
  target : string;
  ok     : Boolean;
begin
  If ParamCount < 1 Then Exit;              // No parameter: normal GUI start-up

  cmd := cli_normalize_command(ParamStr(1));

  If cmd = 'pc_win_start' Then Exit;        // Auto start-up: handled in TMain.FormCreate

  If cmd = 'help' Then
   begin
     cli_print_usage;
     Halt(CLI_EXIT_OK);
   end;

  If not cli_known_command(cmd) Then
   begin
     cli_write_line('UniController: unknown parameter "' + ParamStr(1) + '"');
     cli_write_line('');
     cli_print_usage;
     Halt(CLI_EXIT_BAD_PARAM);
   end;

  //---Command line control mode: hide GUI, suppress all dialogs (USC_CLI_MODE),
  //   report result via console text and exit code.
  USC_CLI_MODE := True;
  Main.visible := False;                    // Hide form
  Application.ShowMainForm := False;        // Never show main form while processing

  try
    us_main_init;  // Set initial values for variables, paths and environment variables.
    sleep(1000);

    //---Status report
    If cmd = 'status' Then Halt(cli_status_exit_code);

    //---Actions: split command into action (start/stop/restart) and
    //   target (apache/mysql/both)
    action := Copy(cmd, 1, Pos('_', cmd) - 1);
    target := Copy(cmd, Pos('_', cmd) + 1, Length(cmd));

    If target = 'both' Then
     begin
       If (not DirectoryExists(US_APACHE)) and (not DirectoryExists(US_MYSQL)) Then
        begin
          cli_write_line('No servers installed');
          Halt(CLI_EXIT_FAILED);
        end;
       //Act on installed servers only: success = every installed server
       //reached the requested state
       ok := True;
       If DirectoryExists(US_APACHE) Then ok := cli_apache_action(action) and ok;
       sleep(1000);                                       // Legacy pacing between the two servers
       If DirectoryExists(US_MYSQL)  Then ok := cli_mysql_action(action) and ok;
     end
    Else If target = 'apache' Then
      ok := cli_apache_action(action)
    Else // mysql
      ok := cli_mysql_action(action);

    If ok Then
      Halt(CLI_EXIT_OK)
    Else
      Halt(CLI_EXIT_FAILED);

  except
    on E: Exception do
     begin
       //Never leave a script hanging on an error dialog: report and exit
       cli_write_line('UniController error: ' + E.Message);
       Halt(CLI_EXIT_FAILED);
     end;
  end;
end;
{--End us_command_line_start_up ---------------------------------------------}
end.
