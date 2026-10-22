# WinpachoController

The controller of winpacho: the program that starts, stops and configures
Apache, MariaDB/MySQL and PHP. It is written in Pascal and built with
Lazarus. Until 2.0.0 it was called UniController (the controller of The
Uniform Server Zero XV, which this code is based on).

### Build

1. Install Lazarus (64-bit, Windows). CI uses the current Lazarus release.
2. Open `WinpachoController.lpi` in Lazarus (*Project > Open Project*) and
   build with *Run > Build* - or on the command line:

   ```
   lazbuild --build-mode=Release WinpachoController\WinpachoController.lpi
   ```

   The result is `WinpachoController.exe` in this folder. Synapse prints a
   number of hints; they are not errors.

### Test run

The controller only starts inside a server folder (the folder that contains
`home\us_config\us_config.ini`) whose path has no spaces. Extract a release
`winpacho.zip` into e.g. `C:\winpacho-test`, copy your freshly built
`WinpachoController.exe` into it and start it from there. A quick check
without the window: `WinpachoController.exe version` and
`WinpachoController.exe help` (see the help text for how to read the exit
code from cmd or PowerShell).

### Custom controls

The main form uses `TUsButton` (see `us_buttons.pas`), a flat coloured button
drawn by the controller itself, because the native `TButton` ignores colours
on Windows. It is registered at runtime, so `lazbuild` and the CI build work
unchanged. The Lazarus **form designer** however does not know the class:
to edit `main_unit.lfm` visually you must first add `us_buttons.pas` to a
design-time package, or simply edit the `.lfm` as text.

### Window looks: classic or medallion

The same `TMain` form shows one of two looks, chosen by `GuiStyle` in
`us_config.ini` `[APP]` (`classic` / `modern`, empty = not chosen yet):

- First interactive start (no command line parameters) with no choice
  saved: `us_gui_style_dlg.pas` shows a dialog with both looks and stores the
  answer. Closed without a choice, the medallion is used and the question
  comes again at the next start.
- `TMain.ApplyGuiStyle` switches at runtime (menu General > Window look):
  classic = `bsSingle` with `Menu := MainMenu1`, white form, no window
  region, tabs and `-`/`x` hidden, layout from `CLASSIC_BOUNDS`; medallion =
  `bsNone`, no menu, coin region, layout from the `.lfm` (remembered at start
  in design units, so DPI changes keep working). Set `Menu` **before**
  `BorderStyle`: the border change recreates the window, and a menu attached
  afterwards did not show.
- Controls whose place differs between the looks are listed once in
  `TMain.LayoutControls`, in the same order as `CLASSIC_BOUNDS`.

### The medallion window

The modern look is the 3D "Reload" medallion itself (`us_medallion.pas`):

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
