unit main_form;

{#############################################################################
'# Name: main_form.pas
'# Developed By: The Uniform Server Development Team
'# Web: https://www.uniformserver.com
'#
'# Main UniService application.
'#############################################################################}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, default_config_vars, us_common_procedures, us_common_functions,
  about_form,
  JwaTlHelp32,
  windows;

type

  { TMain }

  TMain = class(TForm)
    Btn_apache_install_uninstall: TButton;
    Btn_apache_service_test: TButton;
    Btn_apache_start_stop: TButton;
    Btn_mysql_install_uninstall: TButton;
    Btn_mysql_start_stop: TButton;
    Button1: TButton;
    Button2: TButton;
    GB_apache: TGroupBox;
    GB_mysql: TGroupBox;
    GroupBox1: TGroupBox;
    Image1: TImage;
    P_apache_install_indicator: TPanel;
    P_apache_start_indicator: TPanel;
    P_mysql_install_indicator: TPanel;
    P_mysql_start_indicator: TPanel;
    procedure Btn_apache_install_uninstallClick(Sender: TObject);
    procedure Btn_apache_service_testClick(Sender: TObject);
    procedure Btn_apache_start_stopClick(Sender: TObject);
    procedure Btn_mysql_install_uninstallClick(Sender: TObject);
    procedure Btn_mysql_start_stopClick(Sender: TObject);
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
  private
    { private declarations }
  public
    { public declarations }
  end;

var
  Main: TMain;

implementation

{$R *.lfm}
{$R manifest.rc}  // Add manifest to raise privileges to admin

{ TMain }

{=================================================================
 WinUniqueInstance:
 Returns true if this is the only running instance of UniService,
 false if another instance is already running.
 Same mechanism as UniController's instance check
 (are_servers_runable.pas): count processes with this exe name.
==================================================================}
function WinUniqueInstance:boolean;
var
  ProcessName:string;            // This application
  total:integer;                 // Number of this application running
  hProcessSnap: THandle;         // Snapshot
  pe          : TProcessEntry32; // Process entry
  Continue    : BOOL;            // Flag
begin
 WinUniqueInstance := True;                   // Assume Unique
 total             := 0;                      // Reset counter
 ProcessName       := ApplicationName+'.exe'; // Name of this exe file

 hProcessSnap := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0); //Take snapshot
 if (hProcessSnap=0) or (hProcessSnap=INVALID_HANDLE_VALUE) then Exit;
   try
     pe.dwSize := SizeOf(pe);                       // Set-up structure size
     Continue := Process32First(hProcessSnap, pe);  // Set flag first (first tobe processed)

     while Continue do
     begin
       //Walk snapshot and count number of ProcessNames
       if SameText(pe.szExeFile, ProcessName) then total:= total+1; // Count instances
       If total >= 2 then                          // Test two or more not unique
         begin
           WinUniqueInstance := False;             // Set False not unique
           exit;                                   // Nothing else to do
         end;
      Continue := Process32Next(hProcessSnap, pe); // Set flag next (more to process)
     end;

   finally
     CloseHandle(hProcessSnap); // Close handle
   end;
end;

procedure TMain.FormCreate(Sender: TObject);

begin
 //=== Only allow a single instance of UniService
 If not WinUniqueInstance Then
  begin
    Application.ShowMainForm := False;   // Hide application
    MessageDlg('UniService not unique instance',
               'An instance of UniService is already running.'+ sLineBreak + sLineBreak +
               'This new UniService instance will close.', mtError,[mbOk],0);
    Application.Terminate;               // Close this instance
    Exit;                                // Skip initialisation
  end;

 //=== Started directly (double-click)? The normal path is the controller
 //menu, which passes --from-controller. New users who double-click
 //UniService.exe get an explanation and the way to the right place
 //instead of an unexplained service window.
 If ParamStr(1) <> '--from-controller' Then
  begin
   If MessageDlg('UniService - Windows service module',
        'UniService installs and runs Apache and MySQL as Windows services.'+ sLineBreak +
        'It is normally opened from the controller:'+ sLineBreak + sLineBreak +
        '    UniController.exe  >  Extra  >  Run Apache/MySQL as Windows service'+ sLineBreak + sLineBreak +
        'Open the service module anyway?',
        mtConfirmation,[mbYes, mbNo],0) <> mrYes Then
    begin
      Application.ShowMainForm := False; // Hide application
      Application.Terminate;             // Close this instance
      Exit;                              // Skip initialisation
    end;
  end;

 us_main_init;     // Set initial values for variables, paths and environment variables.
 us_update_status; // Update button text and indicators

end;

procedure TMain.Btn_apache_install_uninstallClick(Sender: TObject);
begin
 //Check configuration files exist
 If All_config_files_exist Then //Back up files
   begin
     //Check files were backed-up
     If All_config_files_backed_up Then
      begin
       //Disable button until complete
       Main.Btn_apache_install_uninstall.Enabled := False; //Disable button
       Main.Btn_apache_start_stop.Enabled := False;        //Disable button

       If Main.Btn_apache_install_uninstall.Caption = Btn_install_service Then
        begin  //Install apache service
          us_update_config_files;      // Update variables in config files.
          us_install_apache_service;   // Install service
        end
       Else
        begin  //Uninstall apache service
          us_uninstall_apache_service; // Uninstall service
          us_restore_files;            // Restore configuration files.
        end;
       us_update_status; //Complete now update state

      end //All_config_files_backed_up
     Else //Failed to backup files
      begin
        showmessage('Unable to back-up files. Application will now terminate.');
        Application.Terminate;   // Exit application
      end;

   end  //All configs files backed up
 Else  //One or more config files not found
  begin
    showmessage('Config file/s not found. Application will now terminate.');
    Application.Terminate;   // Exit application
  end;
end;

procedure TMain.Btn_apache_service_testClick(Sender: TObject);
var
  str:string;
begin
 If All_config_files_exist then    // Check all config files exist
   begin                           // The do continue
     showmessage('All required configuration files exist.');

      //Check files were backed
      If All_config_files_backed_up Then
        begin
          str := '';
          str := str + 'All required backed-up configuration files exist.';
          showmessage(str);

          us_update_config_files; // Update variables in config files.
           str := '';
           str := str + 'Original configuration updated.'+ sLineBreak ;
           str := str + 'Variables replaced with absolute paths.';
           showmessage(str);

          us_apache_service_test; // Runs service test
           str := '';
           str := str + 'If any errors were reported, fix them.'+ sLineBreak;
           str := str + 'Otherwise, the service will not run.';
           showmessage(str);

          us_restore_files;       // Restore configuration files.
           str := '';
           str := str + 'Restored back-up files.'+ sLineBreak;
           str := str + 'Removed back-up files and folder.';
           showmessage(str);

        end
      Else  //One or more files missing
        begin
          showmessage('Back-up folder "service_back" will now be deleted.');
          DeleteDirectory(US_CORE_SB,true);  // Delete folder content
          DeleteDirectory(US_CORE_SB,false); // Delete folder
        end;
   end;

  // Directory US_CORE_SB does not exists, perform test
//  us_backup_files;        // Backup configuration files
//  us_update_config_files; // Update variables in original config files.

//  us_apache_service_test; // Runs service test

//  us_restore_files; // Restore backup files

end;

procedure TMain.Btn_apache_start_stopClick(Sender: TObject);
begin
  //Disable button until complete
  Main.Btn_apache_install_uninstall.Enabled := False; //Disable button
  Main.Btn_apache_start_stop.Enabled := False;        //Disable button

  //Start stop Apache service
  If Main.Btn_apache_start_stop.Caption = Btn_run_service Then
   begin
     us_start_apache_service;     // Start Apache service
   end
  Else
   begin
     us_stop_apache_service;      // Stop Apache service
   end;

  us_update_status; //Complete now update state
end;

procedure TMain.Btn_mysql_install_uninstallClick(Sender: TObject);
begin
  //Disable button until complete
  Main.Btn_mysql_install_uninstall.Enabled := False; //Disable button
  Main.Btn_mysql_start_stop.Enabled := False;        //Disable button

  If Main.Btn_mysql_install_uninstall.Caption = Btn_install_service Then
   begin //Install MySQL service
     us_install_mysql_service;
   end
  Else
   begin //Uninstall MySQL service
      us_uninstall_mysql_service;
   end;
  us_update_status; //Complete now update state
end;

procedure TMain.Btn_mysql_start_stopClick(Sender: TObject);
begin
  //Disable button until complete
  Main.Btn_mysql_install_uninstall.Enabled := False; //Disable button
  Main.Btn_mysql_start_stop.Enabled := False;        //Disable button

  //Start stop MySQL service
  If Main.Btn_mysql_start_stop.Caption = Btn_run_service Then
   begin
     us_start_mysql_service;  // Start MySQL service
   end
  Else
   begin
     us_stop_mysql_service;   // Stop MySQL service
   end;
  us_update_status;     //Complete now update state
end;

procedure TMain.Button1Click(Sender: TObject);
begin
    about.ShowModal;
end;

procedure TMain.Button2Click(Sender: TObject);
var
  str :string;
begin
  str :='';
  str := str + 'Errors in Apache configuration files will prevent Apache running as a service.' + sLineBreak  + sLineBreak;

  str := str + 'Apache service test performs the following:'       + sLineBreak;
  str := str + '1) Check configuration files exist'                + sLineBreak;
  str := str + '2) Create back-up folder and copy files'           + sLineBreak;
  str := str + '3) Check all back-up files exist'                  + sLineBreak;
  str := str + '4) Replace variables with absolute paths'         + sLineBreak;
  str := str + '5) Open a command window'                          + sLineBreak;
  str := str + '6) Install Apache service'                         + sLineBreak;
  str := str + '7) Performs Apache configuration test'             + sLineBreak;
  str := str + '8) Uninstall Apache service (close window when done)'                      + sLineBreak;
  str := str + '9) Restore original files from back-up'           + sLineBreak;
  str := str + '10) Delete back-up files and folder'               + sLineBreak  + sLineBreak;

  str := str + 'Closing above command window returns to the Uniform Server Service utility.' + sLineBreak  + sLineBreak;

  str := str + 'If any errors were reported, you must fix them before the service '    + sLineBreak;
  str := str + 'can be installed and started from the Uniform Server Service utility.' + sLineBreak;

  MessageDlg('Apache service test information', str,  mtcustom,[mbOk],0) ; //Display message
end;

procedure TMain.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  //==== File array for source and backup
 StrAllSource.Free; // Free List of config files
 StrAllBackup.Free; // Free List of backup config files
end;

end.

