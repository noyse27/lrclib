# LRCLIB Windows tray starter

This package starts the LRCLIB server in the background and provides a Windows
notification-area icon.

## Default command

The tray application runs the equivalent of:

```powershell
Set-Location "E:\lrclib"
$env:LRCLIB_LOG = "info"
cargo run --release -- serve --database db.sqlite3
```

## Installation

1. Clone this repository to `E:\lrclib`.
2. Confirm that Rust/Cargo is installed for the current Windows user.
3. Double-click `Start-LRCLIB-Tray.vbs` or `Start-LRCLIB-Tray.cmd` in this
   directory.

The VBS launcher starts PowerShell without leaving a console window open.
Windows may hide the icon behind the notification-area overflow arrow the first
time it starts.

## Tray menu

- Start, restart, or stop the server
- Open the LRCLIB source directory
- Open the log directory
- Exit the tray application and stop the complete Cargo/server process tree

A double-click starts a stopped server. While it is running, a double-click
opens the log directory.

Standard output and errors are stored separately in:

```text
E:\lrclib\logs
```

The tray application remembers the Cargo process identity. If only the tray
application crashes and is started again, it adopts the matching live process
instead of starting a second server.

## Optional Windows login start

Press `Win+R`, enter `shell:startup`, and place a shortcut to
`Start-LRCLIB-Tray.vbs` in that directory.

## Configuration

The defaults can be changed in the `param(...)` block at the top of
`LRCLIB-Tray.ps1`. The supported settings are:

- `ServerDirectory`
- `DatabaseFile`
- `LogLevel`
- `AutoStart`

The tray starter uses `%USERPROFILE%\.cargo\bin\cargo.exe` first and then
searches `PATH`.
