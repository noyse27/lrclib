Option Explicit

Dim shell, fileSystem, scriptDirectory, powerShellScript, command
Set shell = CreateObject("WScript.Shell")
Set fileSystem = CreateObject("Scripting.FileSystemObject")

scriptDirectory = fileSystem.GetParentFolderName(WScript.ScriptFullName)
powerShellScript = fileSystem.BuildPath(scriptDirectory, "LRCLIB-Tray.ps1")
command = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ _
    & powerShellScript & """"

shell.Run command, 0, False
