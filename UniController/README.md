# Uniform Server
Uniform Server is a free lightweight WAMP server solution for Windows.
Build using a modular design approach, it includes the latest versions of Apache, MySQL or MariaDB, PHP (with version switching), phpMyAdmin or Adminer.

No installation required! No registry dust! Just unpack and fire up!

## UniController
The UniController is the heart of the Uniform Server Package where everything can be controlled, modified and updated. It is built using Pascal and compiled with Lazarus.

### Create working environment

Create a working environment for compiling and testing code:

 1. Create a new folder, for example z_controller.
 2. Download the latest version of Uniform Server ZeroXV, for example 15_x_x_ZeroXV.exe and save to folder z_controller.
 3. Double click on downloaded file (15_x_x_ZeroXV.exe); this extracts Uniform Server ZeroXV to folder z_controller\UniServerZ.
 4. Download the source from Github to folder z_controller\UniServerZ.
 5. Note: Two new folders are created: z_controller\UniServerZ\synapse and z_controller\UniServerZ\unicon_images. 
    Project source code is added to folder z_controller\UniServerZ.
 6. That completes working environment creation.
 
###  Compiling UniController

With the working environment in place, you are ready to compile UniController as follows:
 
 1. Start Lazarus.
 2. Close any existing project: Project > Close Project.
 3. In the pop-up window, click "Open Project" button.
    Navigate to folder: z_controller\UniServerZ.
    Click on file UniController.lpi, click Open button.
    The project opens and is ready for compiling.
 4. A quick test run the project: Run > run or press F9.
    Note: Synapse will produce several warning Hint messages; these are not errors.
    Last line displayed: Project "UniController" successfully built.
 5. UniController will run.

 You can now change code as required and re-compile.

### Custom controls

The main form uses `TUsButton` (see `us_buttons.pas`), a flat coloured button
drawn by the controller itself, because the native `TButton` ignores colours
on Windows. It is registered at runtime, so `lazbuild` and the CI build work
unchanged. The Lazarus **form designer** however does not know the class:
to edit `main_unit.lfm` visually you must first add `us_buttons.pas` to a
design-time package, or simply edit the `.lfm` as text.

### The medallion window

The main window is the 3D "Reload" medallion itself (`us_medallion.pas`):

- The artwork is the `MEDALLION` RCDATA resource in `unicon_images.rc`
  (`unicon_images/medaillon.png`, 2000 x 2000, PNG with alpha). Any change to
  that file needs a clean build (`lazbuild -B`), an incremental build keeps
  the old resource.
- At start-up and after every DPI change the coin is scaled to the form size
  (alpha-aware supersampling), dark translucent pads are baked in under the
  text rows for contrast, and the window is clipped to the coin with
  `SetWindowRgn`. The form stays an ordinary opaque window, so all native
  controls keep working; only its outline is round. Clicks outside the coin
  fall through to whatever is behind it.
- `TUsButton` copies its corner area from that background bitmap
  (`UsButtonBackground`), so the rounding shows metal, not a flat colour.
  `FillOpacity` lets a little of the metal shimmer through the fills.
- There is no title bar: dragging any free spot of the coin moves the
  window (`FormMouseDown` sends `WM_NCLBUTTONDOWN`/`HTCAPTION`), and the
  small `-` / `x` buttons minimize and close. Alt+F4 still works.
- The menu bar is replaced by text tabs (`TUsButton` with `Style = ubsTab`).
  A tab opens its `TMainMenu` top-level item as a popup with
  `TrackPopupMenuEx(... TPM_RETURNCMD)` and dispatches the chosen command
  through `MainMenu1.FindItem(cmd, fkCommand).Click`: the form has no menu
  attached, so the LCL could not route `WM_COMMAND` itself. All menu items,
  handlers, icons and enable/disable logic in `us_server_state.pas` are
  untouched; `TMain.SyncMenuTabs` mirrors caption and enabled state of the
  top-level items onto the tabs (and explains a greyed tab in its hint).
- Layout is defined at `DesignTimePPI = 120` on an 800 x 800 form; the
  usable area is the inner disc (radius about 340 design units), so keep
  new controls inside that circle.
- If the resource is missing or unreadable the window falls back to a plain
  dark disc, so a broken artwork never takes the controller down.
