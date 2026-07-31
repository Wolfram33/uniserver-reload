unit vhost_delete_form;

{#############################################################################
'# Name: vhost_delete_form.pas
'# Developed By: The Uniform Server Development Team
'# Web: https://www.uniformserver.com
'#############################################################################}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, LazFileUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  default_config_vars,
  us_common_procedures,
  us_common_functions,
  RegExpr;

type

  { Tvhost_delete }

  Tvhost_delete = class(TForm)
    Btn_delete_vhost: TButton;
    Btn_cancel_selection: TButton;
    Label1: TLabel;
    ListBox1: TListBox;
    procedure Btn_cancel_selectionClick(Sender: TObject);
    procedure Btn_delete_vhostClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    { private declarations }
  public
    { public declarations }
  end;

var
  vhost_delete: Tvhost_delete;


implementation

{$R *.lfm}

{===============================================================
Set Initial state:
 Read Vhost file and display Server Names (each host once,
 skipping the first/default vhost).
----------------------------------------------------------------}
procedure set_initial_state;
var
  sList     : TStringList;  // String list
  i         : integer;      // Loop counter
  RegexObj  : TRegExpr;     // Object
  is_first  : boolean;      // First Server name is default
  host      : string;
begin
  is_first  := True;
  vhost_delete.ListBox1.ItemIndex  := -1;  // Clear selection
  vhost_delete.ListBox1.Clear;             // Clear list box

  //Display Vhosts in Vhost configuration file
  If FileExists(USF_APACHE_VHOST_CNF) Then        // Check file exists
      begin
        sList  := TStringList.Create;             // Create object
        RegexObj := TRegExpr.Create;              // Create regex obj
        sList.LoadFromFile(USF_APACHE_VHOST_CNF); // Load Apache main config file

        for i:=0 to sList.Count-1 do
         begin
           //-- Get Server name
          RegexObj.Expression := '^\s*ServerName\s*([^\s]*)';      // Set search pattern
           if (sList[i]<>'') and RegexObj.Exec(sList[i]) then                         // Match found
             begin
               host := RegexObj.Match[1];
               If is_first Then
                  is_first := false //Do not display first (the default vhost)
               Else
                  // Each host appears in a :80 and a :443 block - show once
                  If vhost_delete.ListBox1.Items.IndexOf(host) < 0 Then
                     vhost_delete.ListBox1.Items.Add(host); // Add item
             end;
          end;

        //Clean up
        RegexObj.Free;   // release object
        sList.Free;      // Remove from memory
      end;//End File exists
end;

{--------------------------------------------------------------}

{===============================================================
Delete every VirtualHost block (http and the IfModule-wrapped
https block) whose ServerName matches In_ServerName, and return
the DocumentRoot found in those blocks.

Input  In_ServerName
Output Out_doc_root - DocumentRoot value (may contain ${US_ROOTF})
----------------------------------------------------------------}
procedure delete_vhost_block(In_ServerName:String; Var Out_doc_root:string);
var
  sList, outList : TStringList;
  i, j           : integer;
  reHost, reDoc  : TRegExpr;
  reVH, reVHend  : TRegExpr;
  reIf, reIfend  : TRegExpr;
  seg            : TStringList;
  blockMatches   : boolean;
  k              : integer;

  // Does the block (seg) contain exactly our ServerName?
  function SegHasHost(s:TStringList): boolean;
  var m:integer;
  begin
    Result := False;
    for m:=0 to s.Count-1 do
      If reHost.Exec(s[m]) and (reHost.Match[1] = In_ServerName) Then
        begin Result := True; Break; end;
  end;

  // Capture the first DocumentRoot in seg
  procedure SegGrabDocRoot(s:TStringList);
  var m:integer;
  begin
    for m:=0 to s.Count-1 do
      If reDoc.Exec(s[m]) Then begin Out_doc_root := Trim(reDoc.Match[1]); Break; end;
  end;

begin
  Out_doc_root := '';
  If Not FileExists(USF_APACHE_VHOST_CNF) Then Exit;

  sList   := TStringList.Create;
  outList := TStringList.Create;
  seg     := TStringList.Create;
  reHost  := TRegExpr.Create; reHost.Expression  := '^\s*ServerName\s+([^\s]+)';
  reDoc   := TRegExpr.Create; reDoc.Expression   := '^\s*DocumentRoot\s+(.+?)\s*$';
  reVH    := TRegExpr.Create; reVH.Expression    := '^\s*<VirtualHost\s';
  reVHend := TRegExpr.Create; reVHend.Expression := '^\s*</VirtualHost>';
  reIf    := TRegExpr.Create; reIf.Expression    := '^\s*<IfModule\s+ssl_module';
  reIfend := TRegExpr.Create; reIfend.Expression := '^\s*</IfModule>';

  sList.LoadFromFile(USF_APACHE_VHOST_CNF);

  i := 0;
  While i < sList.Count Do
   begin
     // --- IfModule ssl_module wrapper (our https block) ---
     If reIf.Exec(sList[i]) Then
       begin
         j := i;
         While (j < sList.Count) and (not reIfend.Exec(sList[j])) Do Inc(j);
         If j >= sList.Count Then j := sList.Count-1;   // Safety
         seg.Clear;
         for k:=i to j do seg.Add(sList[k]);
         blockMatches := SegHasHost(seg);
         If blockMatches Then SegGrabDocRoot(seg)
         Else for k:=i to j do outList.Add(sList[k]);
         i := j+1;
         Continue;
       end;
     // --- Plain VirtualHost block (http) ---
     If reVH.Exec(sList[i]) Then
       begin
         j := i;
         While (j < sList.Count) and (not reVHend.Exec(sList[j])) Do Inc(j);
         If j >= sList.Count Then j := sList.Count-1;   // Safety
         seg.Clear;
         for k:=i to j do seg.Add(sList[k]);
         blockMatches := SegHasHost(seg);
         If blockMatches Then SegGrabDocRoot(seg)
         Else for k:=i to j do outList.Add(sList[k]);
         i := j+1;
         Continue;
       end;
     // --- Any other line ---
     outList.Add(sList[i]);
     Inc(i);
   end;

  //== Clean file list: collapse blank lines, blank line before each vhost
  for i:=outList.Count-1 downto 0 do
     If Trim(outList[i])='' Then outList.Delete(i);
  for i:=outList.Count-1 downto 0 do
     If reVH.Exec(outList[i]) or reIf.Exec(outList[i]) Then outList.Insert(i,'');

  If FileIsWritable(USF_APACHE_VHOST_CNF) Then
     outList.SaveToFile(USF_APACHE_VHOST_CNF);

  //== Normalise the returned DocumentRoot path
  Out_doc_root := StringReplace(Out_doc_root, '${US_ROOTF}',UniConPath_F,[rfReplaceAll]); // Expand ${US_ROOTF}
  Out_doc_root := StringReplace(Out_doc_root, '${HOME}',UniConPath,[rfReplaceAll]);       // Expand ${HOME}
  Out_doc_root := StringReplace(Out_doc_root, '"','',[rfReplaceAll]);                     // Strip quotes
  Out_doc_root := StringReplace(Out_doc_root, '/','\',[rfReplaceAll]);                    // Forward -> back slash
  Out_doc_root := Trim(Out_doc_root);
  Out_doc_root := ExcludeTrailingPathDelimiter(Out_doc_root);

  seg.Free; sList.Free; outList.Free;
  reHost.Free; reDoc.Free; reVH.Free; reVHend.Free; reIf.Free; reIfend.Free;
end;
{--------------------------------------------------------------}


{ Tvhost_delete }

{===============================================================
 Is the path strictly inside the portable vhosts\ folder?
 Only such folders were created by the controller and may be
 offered for deletion. Any external project folder is off-limits.
----------------------------------------------------------------}
function path_is_inside_vhosts(const p:string): boolean;
var base, cand: string;
begin
  base := IncludeTrailingPathDelimiter(LowerCase(ExpandFileName(US_VHOSTS)));
  cand := LowerCase(ExpandFileName(p));
  // Must start with "<...>\vhosts\" and be deeper than the vhosts root itself
  Result := (Length(cand) > Length(base)) and (Copy(cand,1,Length(base)) = base);
end;

procedure Tvhost_delete.Btn_delete_vhostClick(Sender: TObject);
var
  selected_host   :string;
  Out_doc_root    :String;
  str             :string;
begin
  Out_doc_root :='';

  //Check for selected item and get value
  If  ListBox1.ItemIndex >=0 Then // Item selected
    begin
      selected_host := ListBox1.Items[ListBox1.ItemIndex]; // Get name selected
      delete_vhost_block(selected_host,Out_doc_root);      // Delete selected item(s) from config file
      us_delete_from_pac_file(selected_host);              // Delete selected host from PAC file
      us_delete_from_hosts_file(selected_host);            // Delete selected host from hosts file

      set_initial_state; //Get and display host entries

      //=== Folder deletion: ONLY for portable folders under vhosts\.
      //    An external (aliased) project folder is never touched.
      If (Out_doc_root <> '') and path_is_inside_vhosts(Out_doc_root)
         and DirectoryExists(Out_doc_root) Then
        begin
          str := 'The Vhost for "' + selected_host + '" was removed.' + sLineBreak + sLineBreak;
          str := str + 'This host used a folder created under vhosts\:' + sLineBreak;
          str := str + Out_doc_root + sLineBreak + sLineBreak;
          str := str + 'Delete this folder and ALL its content?' + sLineBreak;
          str := str + '(Click No to keep the files.)';
          if us_MessageDlg('Delete Vhost folder?', str, mtConfirmation,[mbYes, mbNo],0) = mrYes then
            begin
              DeleteDirectoryEx(Out_doc_root);
              us_MessageDlg('Apache Info','The Vhost folder was deleted.', mtInformation,[mbOk],0);
            end;
        end
      Else
        begin
          //External / aliased folder (or none): never delete, just inform.
          str := 'The Vhost for "' + selected_host + '" was removed' + sLineBreak;
          str := str + '(http and https blocks, hosts and PAC entries).' + sLineBreak + sLineBreak;
          If Out_doc_root <> '' Then
            begin
              str := str + 'Your document root was left untouched:' + sLineBreak;
              str := str + Out_doc_root + sLineBreak + sLineBreak;
            end;
          str := str + 'Restart Apache for the change to take effect.';
          us_MessageDlg('Vhost Deleted', str, mtInformation,[mbOk],0);
        end;

      vhost_delete.Close;                      // Close form
     end
  Else // No item selected
      us_MessageDlg('Warning','No selection!', mtWarning,[mbOk],0) ; //Display warning message
end;

procedure Tvhost_delete.Btn_cancel_selectionClick(Sender: TObject);
begin
    vhost_delete.ListBox1.ItemIndex  := -1;  // Clear selection
end;


procedure Tvhost_delete.FormCreate(Sender: TObject);
begin
  set_initial_state; // Get and display host entries
end;

procedure Tvhost_delete.FormShow(Sender: TObject);
begin
  set_initial_state; // Get and display host entries
end;

end.
