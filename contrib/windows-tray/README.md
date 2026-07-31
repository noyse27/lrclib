# LRCLIB Windows tray starter

This package starts the LRCLIB server in the background and provides a Windows
notification-area icon.

## First start

On the first start, the tray application asks for:

- the LRCLIB server directory containing `Cargo.toml`
- the SQLite database file (an existing file or a path for a new database)

The selected paths are stored for the current Windows user in:

```text
%LOCALAPPDATA%\LRCLIB\windows-tray\config.json
```

Later starts reuse this configuration automatically. Use **Configure paths...**
in the tray menu to change it.

## Installation

1. Clone this repository to any local directory.
2. Confirm that Rust/Cargo is installed for the current Windows user.
3. Double-click `Start-LRCLIB-Tray.vbs` or `Start-LRCLIB-Tray.cmd` in this
   directory.
4. Select the server directory and database file when prompted.

The VBS launcher starts PowerShell without leaving a console window open.
Windows may hide the icon behind the notification-area overflow arrow the first
time it starts.

## Tray menu

- Start, restart, or stop the server
- Open the LRCLIB source directory
- Open the log directory
- Change the saved server and database paths
- Exit the tray application and stop the complete Cargo/server process tree

A double-click starts a stopped server. While it is running, a double-click
opens the log directory.

Standard output and errors are stored separately in the `logs` directory below
the selected server directory.

The tray application remembers the Cargo process identity. If only the tray
application crashes and is started again, it adopts the matching live process
instead of starting a second server.

## Optional Windows login start

Press `Win+R`, enter `shell:startup`, and place a shortcut to
`Start-LRCLIB-Tray.vbs` in that directory.

## Additional configuration

The launcher can also pass these optional PowerShell parameters:

- `ServerDirectory`
- `DatabaseFile`
- `LogLevel`
- `AutoStart`

Explicit `ServerDirectory` and `DatabaseFile` parameters override the saved
paths for that launch. If either path is missing and no saved value exists, the
first-start dialogs are shown.

The tray starter uses `%USERPROFILE%\.cargo\bin\cargo.exe` first and then
searches `PATH`.
