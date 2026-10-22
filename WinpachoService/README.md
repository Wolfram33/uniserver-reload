# WinpachoService

The service module of winpacho: it installs, starts, stops and removes
Apache and MariaDB/MySQL as Windows services. It is normally opened from the
controller (*Extra > Run Apache/MySQL as Windows service*) and asks for
administrator rights, because installing services needs them. Until 2.0.0 it
was called UniService (the service plugin of The Uniform Server Zero XV,
which this code is based on).

### Build

1. Install Lazarus (64-bit, Windows). CI uses the current Lazarus release.
2. Open `WinpachoService.lpi` in Lazarus (*Project > Open Project*) and
   build with *Run > Build* - or on the command line:

   ```
   lazbuild WinpachoService\WinpachoService.lpi
   ```

   The result is `WinpachoService.exe` in this folder.

Its manifest requires administrator rights (`manifest.xml`). Running it
straight from the Lazarus IDE therefore fails unless Lazarus itself runs as
administrator; build it and start the exe instead.

### Test run

The service module belongs into the `utils` subfolder of a server folder.
Extract a release `winpacho.zip` into e.g. `C:\winpacho-test`, copy your
freshly built `WinpachoService.exe` into `C:\winpacho-test\utils` and open it
from the controller in that folder. Started on its own (double click) it
first explains that it is meant to be opened from the controller.
