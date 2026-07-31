unit vhost_create_form;

{#############################################################################
'# Name: vhost_create_form.pas
'# Developed By: The Uniform Server Development Team
'# Web: https://www.uniformserver.com
'#############################################################################}


{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, LazFileUtils, FileUtil, Forms, Controls, Graphics, Dialogs, StdCtrls,
  default_config_vars,
  us_common_procedures,
  us_common_functions,
  RegExpr;

type

  { Tvhost_create }

  Tvhost_create = class(TForm)
    Btn_create_vhost: TButton;
    Btn_browse: TButton;
    Btn_help_server_name: TButton;
    Btn_help_root_folder: TButton;
    Edit_root_folder: TEdit;
    Edit_server_name: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    Label3: TLabel;
    Label4: TLabel;
    SelectDirectoryDialog1: TSelectDirectoryDialog;
    procedure Btn_create_vhostClick(Sender: TObject);
    procedure Btn_browseClick(Sender: TObject);
    procedure Btn_help_root_folderClick(Sender: TObject);
    procedure Btn_help_server_nameClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    { private declarations }
  public
    { public declarations }
  end;

var
  vhost_create: Tvhost_create;

implementation

{$R *.lfm}

{===============================================================
Add Vhost block to Vhost configuration file:
Input In_RootFolder
Input In_ServerName

==File httpd-vhosts.conf:
 1) Check file exists
 2) Check for existing Vhost section
 3) Add new Vhost section
 4) Remove duplicated blank lines
 5) Save file

----------------------------------------------------------------}
procedure add_vhost_block(In_DocRoot:String;In_DirPath:String;In_ServerName:String);
var
 vhost_found :boolean;     // Vhost section found
 sList       :TStringList; // String list
 i           :integer;     // Loop counteri
begin
  vhost_found     := False;                 // Assume no vhost section

  If FileExists(USF_APACHE_VHOST_CNF) Then   // Check file exists
  begin
   sList  := TStringList.Create;             // Create object
   sList.LoadFromFile(USF_APACHE_VHOST_CNF); // Load Apache Vhost config file

   for i:=0 to sList.Count-1 do
     begin
        //-- Check section not present
        If (sList[i]<>'') and ExecRegExpr('^\s*ServerName\s*'+In_ServerName, sList[i]) Then
         begin
           vhost_found := True; //Already contains the new Vhost section
           break;               //Nothing else to do
          end;
      end;//End scan new list

   //--Add new section
   //  In_DocRoot - DocumentRoot value (portable ${US_ROOTF}/vhosts/name or an
   //               absolute path like D:/projects/app)
   //  In_DirPath - matching <Directory> path (Windows-style backslashes)
   If Not vhost_found Then
     begin
       sList.Add('');
       sList.Add('<VirtualHost *:${AP_PORT}>');
       sList.Add(' ServerAdmin webmaster@'+In_ServerName);
       sList.Add(' DocumentRoot '+In_DocRoot);
       sList.Add(' ServerName '+ In_ServerName);
       sList.Add(' ServerAlias www.'+IN_ServerName+ ' *.'+In_ServerName);
       sList.Add(' ErrorLog logs/'+In_ServerName+'-error.log');
       sList.Add(' CustomLog logs/'+In_ServerName+'-access.log common');
       sList.Add(' <Directory "'+In_DirPath+'">');
       sList.Add('   Options Indexes Includes FollowSymLinks');
       sList.Add('   AllowOverride All   ');
       sList.Add('   Require all granted ');
       sList.Add(' </Directory> ');
       sList.Add('</VirtualHost> ');
       sList.Add('');

       //==Clean file list

       //Remove all blank lines
       for i:=sList.Count-1 downto 0 do
         If sList[i]='' Then
           sList.Delete(i); //Delete entery

       //Insert blank line above start of each Vhost block
       for i:=sList.Count-1 downto 0 do
         begin
           //-- Get Start of Vhost
           If (sList[i]<>'') and ExecRegExpr('^\s*<VirtualHost\s', sList[i]) Then
              sList.Insert(i,''); // Insert blank line
         end;

       //Save new Vhost file
       If FileIsWritable(USF_APACHE_VHOST_CNF) Then
          sList.SaveToFile(USF_APACHE_VHOST_CNF); // Save Vhost file

     end;

   //Clean up
   sList.Free;      // Remove from memory
  end;//End Enable Vhost
end;
{--------------------------------------------------------------}

{ Tvhost_create }

procedure Tvhost_create.Btn_create_vhostClick(Sender: TObject);
{
Create new Vhost:
  Environment variable HOME=C:\UniserverZ
  Environment variable US_ROOTF=C:/UniserverZ
}
var
   new_ServerName  :string;      // New server name - Domain name
   new_root_input  :string;      // Raw text entered (folder name or full path)
   new_root_path   :string;      // Full document root path (Windows-style)
   doc_root_conf   :string;      // DocumentRoot value written to config
   dir_path_conf   :string;      // <Directory> path written to config
   is_external     :boolean;     // True when an absolute path was given
   sList           :TStringList; // String list
   valid_input     :boolean;     // Valid data from user
   i               :integer;     // Loop counteri
begin
   new_root_path   :='';
   new_root_input  := Trim(Edit_root_folder.Text); // Get root-folder/path entered
   new_ServerName  := Edit_server_name.Text;       // Get server name entered

   valid_input := True;    // Assume input is invalid

   // An absolute path (drive letter or UNC) means "use this folder directly"
   is_external := (Length(new_root_input) >= 2) and
                  ((new_root_input[2] = ':') or (Copy(new_root_input,1,2) = '\\'));

   //==Check data entered by user - Validate user input===

   If is_external Then
     begin
       new_root_path := ExcludeTrailingPathDelimiter(new_root_input);
       If Not DirectoryExists(new_root_path) Then
         begin
           valid_input := False;
           us_MessageDlg('Document Root',
             'The folder does not exist:' + sLineBreak + new_root_path + sLineBreak + sLineBreak +
             'Pick an existing folder with the Browse button.', mtError,[mbOk],0);
         end;
     end
   Else
     //--Check simple folder name (portable, created under vhosts\)
     If Not valid_root_folder_name(new_root_input,'Root folder') Then valid_input := False;

   //--Check domain name looks resonable e.g fred.com
   If Not valid_server_name(new_ServerName,'Server Name')       Then valid_input := False;

  //===Create full root path and config values
  If valid_input Then
    begin
      If is_external Then
        begin
          // Absolute path: reference it directly (forward slashes for
          // DocumentRoot, backslashes for the <Directory> match)
          doc_root_conf := StringReplace(new_root_path,'\','/',[rfReplaceAll]);
          dir_path_conf := StringReplace(new_root_path,'/','\',[rfReplaceAll]);
        end
      Else
        begin
          // Portable name under vhosts\  (keeps ${US_ROOTF}/${HOME} tokens)
          new_root_path := UniConPath+'\vhosts\'+new_root_input;
          doc_root_conf := '${US_ROOTF}/vhosts/'+new_root_input;
          dir_path_conf := '${HOME}\vhosts\'+new_root_input;
        end;
    end;

  //###== Create new Vhost ==###
  If valid_input Then
   begin

    //==File httpd.conf enable Vhost include section:
    If FileExists(USF_APACHE_CNF) Then       // Check file exists
    begin
     sList  := TStringList.Create;           // Create object
     sList.LoadFromFile(USF_APACHE_CNF);     // Load Apache main config file

     for i:=0 to sList.Count-1 do
       begin
          //-- Check section not enabled
          If (sList[i]<>'') and ExecRegExpr('^\s*#\s*Include\s*conf/extra/httpd-vhosts.conf', sList[i]) Then
           begin
             sList[i] := 'Include conf/extra/httpd-vhosts.conf'; // Enabled line (section)
             //Save updated file
             If FileIsWritable(USF_APACHE_CNF) Then
                sList.SaveToFile(USF_APACHE_CNF);     // Save new values to file

              sleep(100);
              break; //Nothing else to do
            end;
        end;//End scan new list

     //Clean up
     sList.Free;      // Remove from memory
    end;//End Enable Vhost

    //== Create new document root folder (portable mode only; an external
    //   folder is used as-is and its existing contents are left untouched)
    If (Not is_external) And (Not DirectoryExists(new_root_path)) Then
       ForceDirectories(new_root_path);   // If directory does not exist create it

    //== Seed helper files only for a freshly created portable root
    If Not is_external Then
      begin
        If not FileExists(new_root_path+'\.htaccess') then
           CopyFile(USF_VHOST_HTACCESS, new_root_path+'\.htaccess'); // .htaccess file for new Vhost

        If not FileExists(new_root_path+'\favicon.ico') then
           CopyFile(USF_VHOST_ICO,new_root_path+'\favicon.ico'); // favicon image for new Vhost
      end;

     //===Add new block to Vhost configuration file
     add_vhost_block(doc_root_conf,dir_path_conf,new_ServerName); // Add new Vhost to configuration file

     //===Add to Uniform Server PAC file
     us_add_to_pac_file(new_ServerName);                     // Add new host to PAC file

     //===Add to Windows hosts  file
     us_add_to_hosts_file(new_ServerName);                   // Add new host to hosts file

     //Inform user
     us_MessageDlg('Apache Info','New Vhost created', mtcustom,[mbOk],0) ; //Display information message
  end;//End valid_input

  If valid_input Then vhost_create.Close;

end;

procedure Tvhost_create.Btn_browseClick(Sender: TObject);
begin
  //Let the user pick any existing folder as the document root (alias mode)
  If DirectoryExists(Edit_root_folder.Text) Then
     SelectDirectoryDialog1.InitialDir := Edit_root_folder.Text
  Else
     SelectDirectoryDialog1.InitialDir := US_VHOSTS;

  If SelectDirectoryDialog1.Execute Then
     Edit_root_folder.Text := SelectDirectoryDialog1.FileName; // Store chosen full path
end;

procedure Tvhost_create.Btn_help_root_folderClick(Sender: TObject);
var
  str:string;
begin
    str :='';
    str := str + 'The document root is the folder Apache serves this'    + sLineBreak;
    str := str + 'host from. Two ways to set it:'                        + sLineBreak + sLineBreak;

    str := str + '1) A plain name, e.g. "app123":'                       + sLineBreak;
    str := str + '   A portable folder is created under'                 + sLineBreak;
    str := str + '   '+ US_VHOSTS+'\'                                     + sLineBreak;
    str := str + '   Moves with the UniServerZ folder.'                  + sLineBreak + sLineBreak;

    str := str + '2) A full path, e.g. "D:\projects\app" (Browse...):'   + sLineBreak;
    str := str + '   Apache serves that folder directly - no need to'    + sLineBreak;
    str := str + '   copy your project into www or vhosts. The folder'   + sLineBreak;
    str := str + '   must already exist; its contents are left as they'  + sLineBreak;
    str := str + '   are. Note: an absolute path is not portable if you' + sLineBreak;
    str := str + '   move the installation to another PC.'               + sLineBreak + sLineBreak;

    str := str + 'You can always fine-tune the generated block in:'      + sLineBreak;
    str := str +  USF_APACHE_VHOST_CNF;

   us_MessageDlg('Document Root', str, mtInformation,[mbOk],0) ; //Display message
end;

procedure Tvhost_create.Btn_help_server_nameClick(Sender: TObject);
var
   str:string;
begin
  str := '';
  str := str + 'Host name is the address you type into' + sLineBreak;
  str := str + 'a browser, excluding the http:// part. ' + sLineBreak + sLineBreak;

  str := str + 'Example 1: ' + sLineBreak;
  str := str + 'Full Internet address: http://www.me.com' + sLineBreak;
  str := str + 'Host name: www.me.com' + sLineBreak + sLineBreak;

  str := str + 'Example 2' + sLineBreak;
  str := str + 'Full Internet address: http://uniserver.com' + sLineBreak;
  str := str + 'Host name: uniserver.com';

  us_MessageDlg('Server Name - Host Name', str, mtInformation,[mbOk],0); //Display message
end;

procedure Tvhost_create.FormShow(Sender: TObject);
begin
   Edit_root_folder.Text :='';
   Edit_server_name.Text :='app.test';
end;

end.

