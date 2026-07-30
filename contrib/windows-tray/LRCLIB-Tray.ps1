param(
    [string]$ServerDirectory = "E:\lrclib",
    [string]$DatabaseFile = "db.sqlite3",
    [string]$LogLevel = "info",
    [bool]$AutoStart = $true
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:ServerProcess = $null
$script:StoppingServer = $false
$script:LastKnownRunning = $false
$script:LogDirectory = Join-Path $ServerDirectory "logs"
$script:PidFile = Join-Path $ServerDirectory ".lrclib-tray-process.json"

function Show-Error {
    param([string]$Message)

    [System.Windows.Forms.MessageBox]::Show(
        $Message,
        "LRCLIB Server",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
}

function Show-Notification {
    param(
        [string]$Title,
        [string]$Text,
        [System.Windows.Forms.ToolTipIcon]$Icon =
            [System.Windows.Forms.ToolTipIcon]::Info
    )

    $script:NotifyIcon.BalloonTipTitle = $Title
    $script:NotifyIcon.BalloonTipText = $Text
    $script:NotifyIcon.BalloonTipIcon = $Icon
    $script:NotifyIcon.ShowBalloonTip(3000)
}

function Find-Cargo {
    $userCargo = Join-Path $env:USERPROFILE ".cargo\bin\cargo.exe"
    if (Test-Path -LiteralPath $userCargo -PathType Leaf) {
        return $userCargo
    }

    $command = Get-Command "cargo.exe" -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    throw "cargo.exe was not found. Install Rust or add Cargo to PATH."
}

function Test-ServerRunning {
    if ($null -eq $script:ServerProcess) {
        return $false
    }

    try {
        $script:ServerProcess.Refresh()
        return -not $script:ServerProcess.HasExited
    }
    catch {
        return $false
    }
}

function Save-ProcessIdentity {
    if (-not (Test-ServerRunning)) {
        return
    }

    $identity = @{
        pid = $script:ServerProcess.Id
        start_time_utc_ticks =
            $script:ServerProcess.StartTime.ToUniversalTime().Ticks
    } | ConvertTo-Json

    Set-Content -LiteralPath $script:PidFile -Value $identity -Encoding UTF8
}

function Remove-ProcessIdentity {
    if (Test-Path -LiteralPath $script:PidFile -PathType Leaf) {
        Remove-Item -LiteralPath $script:PidFile -Force -ErrorAction SilentlyContinue
    }
}

function Restore-ServerProcess {
    if (-not (Test-Path -LiteralPath $script:PidFile -PathType Leaf)) {
        return
    }

    try {
        $identity = Get-Content -LiteralPath $script:PidFile -Raw |
            ConvertFrom-Json
        $process = Get-Process -Id ([int]$identity.pid) -ErrorAction Stop
        $actualTicks = $process.StartTime.ToUniversalTime().Ticks

        if ($actualTicks -ne [long]$identity.start_time_utc_ticks) {
            Remove-ProcessIdentity
            return
        }

        $script:ServerProcess = $process
    }
    catch {
        Remove-ProcessIdentity
    }
}

function Update-TrayState {
    $running = Test-ServerRunning

    if ($running) {
        $script:StatusItem.Text = "Status: running (PID $($script:ServerProcess.Id))"
        $script:NotifyIcon.Text = "LRCLIB Server - running"
        $script:StartItem.Enabled = $false
        $script:RestartItem.Enabled = $true
        $script:StopItem.Enabled = $true
    }
    else {
        $script:StatusItem.Text = "Status: stopped"
        $script:NotifyIcon.Text = "LRCLIB Server - stopped"
        $script:StartItem.Enabled = $true
        $script:RestartItem.Enabled = $false
        $script:StopItem.Enabled = $false
    }
}

function Start-LrclibServer {
    if (Test-ServerRunning) {
        Show-Notification "LRCLIB Server" "The server is already running."
        return
    }

    if (-not (Test-Path -LiteralPath $ServerDirectory -PathType Container)) {
        Show-Error "The server directory does not exist:`n$ServerDirectory"
        return
    }

    try {
        $cargo = Find-Cargo
        New-Item -ItemType Directory -Path $script:LogDirectory -Force |
            Out-Null

        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $stdoutLog = Join-Path $script:LogDirectory "lrclib-$timestamp.out.log"
        $stderrLog = Join-Path $script:LogDirectory "lrclib-$timestamp.err.log"

        $oldLogLevel = $env:LRCLIB_LOG
        $env:LRCLIB_LOG = $LogLevel
        try {
            $script:ServerProcess = Start-Process `
                -FilePath $cargo `
                -ArgumentList @(
                    "run",
                    "--release",
                    "--",
                    "serve",
                    "--database",
                    $DatabaseFile
                ) `
                -WorkingDirectory $ServerDirectory `
                -WindowStyle Hidden `
                -RedirectStandardOutput $stdoutLog `
                -RedirectStandardError $stderrLog `
                -PassThru
        }
        finally {
            if ($null -eq $oldLogLevel) {
                Remove-Item Env:LRCLIB_LOG -ErrorAction SilentlyContinue
            }
            else {
                $env:LRCLIB_LOG = $oldLogLevel
            }
        }

        Start-Sleep -Milliseconds 300
        if (-not (Test-ServerRunning)) {
            throw "Cargo exited immediately. Check the log files in $script:LogDirectory."
        }

        Save-ProcessIdentity
        $script:LastKnownRunning = $true
        Update-TrayState
        Show-Notification `
            "LRCLIB Server started" `
            "PID $($script:ServerProcess.Id), log level $LogLevel"
    }
    catch {
        $script:ServerProcess = $null
        Remove-ProcessIdentity
        Update-TrayState
        Show-Error "The LRCLIB server could not be started:`n$($_.Exception.Message)"
    }
}

function Stop-LrclibServer {
    param([switch]$Silent)

    if (-not (Test-ServerRunning)) {
        $script:ServerProcess = $null
        Remove-ProcessIdentity
        Update-TrayState
        return
    }

    $script:StoppingServer = $true
    $processId = $script:ServerProcess.Id

    try {
        $taskkill = Join-Path $env:SystemRoot "System32\taskkill.exe"
        & $taskkill /PID $processId /T /F 2>&1 | Out-Null

        try {
            $script:ServerProcess.WaitForExit(5000)
        }
        catch {
            # taskkill already handled the process tree.
        }
    }
    finally {
        $script:ServerProcess = $null
        $script:StoppingServer = $false
        $script:LastKnownRunning = $false
        Remove-ProcessIdentity
        Update-TrayState
    }

    if (-not $Silent) {
        Show-Notification "LRCLIB Server" "The server was stopped."
    }
}

function Restart-LrclibServer {
    Stop-LrclibServer -Silent
    Start-LrclibServer
}

function Open-Directory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
    Start-Process -FilePath "explorer.exe" -ArgumentList @($Path)
}

$createdNew = $false
$mutex = [System.Threading.Mutex]::new(
    $true,
    "Local\Adolar-LRCLIB-Server-Tray",
    [ref]$createdNew
)

if (-not $createdNew) {
    [System.Windows.Forms.MessageBox]::Show(
        "The LRCLIB tray application is already running.",
        "LRCLIB Server",
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
    $mutex.Dispose()
    exit 0
}

$script:NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
$script:NotifyIcon.Icon = [System.Drawing.SystemIcons]::Information
$script:NotifyIcon.Text = "LRCLIB Server"
$script:NotifyIcon.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip

$script:StatusItem = New-Object System.Windows.Forms.ToolStripMenuItem
$script:StatusItem.Text = "Status: stopped"
$script:StatusItem.Enabled = $false
$menu.Items.Add($script:StatusItem) | Out-Null
$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) |
    Out-Null

$script:StartItem = New-Object System.Windows.Forms.ToolStripMenuItem
$script:StartItem.Text = "Start server"
$script:StartItem.add_Click({ Start-LrclibServer })
$menu.Items.Add($script:StartItem) | Out-Null

$script:RestartItem = New-Object System.Windows.Forms.ToolStripMenuItem
$script:RestartItem.Text = "Restart server"
$script:RestartItem.add_Click({ Restart-LrclibServer })
$menu.Items.Add($script:RestartItem) | Out-Null

$script:StopItem = New-Object System.Windows.Forms.ToolStripMenuItem
$script:StopItem.Text = "Stop server"
$script:StopItem.add_Click({ Stop-LrclibServer })
$menu.Items.Add($script:StopItem) | Out-Null

$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) |
    Out-Null

$openServerItem = New-Object System.Windows.Forms.ToolStripMenuItem
$openServerItem.Text = "Open server directory"
$openServerItem.add_Click({ Open-Directory $ServerDirectory })
$menu.Items.Add($openServerItem) | Out-Null

$openLogsItem = New-Object System.Windows.Forms.ToolStripMenuItem
$openLogsItem.Text = "Open logs"
$openLogsItem.add_Click({ Open-Directory $script:LogDirectory })
$menu.Items.Add($openLogsItem) | Out-Null

$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) |
    Out-Null

$exitItem = New-Object System.Windows.Forms.ToolStripMenuItem
$exitItem.Text = "Exit and stop server"
$menu.Items.Add($exitItem) | Out-Null

$script:NotifyIcon.ContextMenuStrip = $menu
$script:NotifyIcon.add_DoubleClick({
    if (Test-ServerRunning) {
        Open-Directory $script:LogDirectory
    }
    else {
        Start-LrclibServer
    }
})

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1500
$timer.add_Tick({
    $running = Test-ServerRunning

    if ($script:LastKnownRunning -and -not $running -and
        -not $script:StoppingServer) {
        $script:ServerProcess = $null
        Remove-ProcessIdentity
        Show-Notification `
            "LRCLIB Server stopped" `
            "The server exited unexpectedly. Check the logs." `
            ([System.Windows.Forms.ToolTipIcon]::Error)
    }

    $script:LastKnownRunning = $running
    Update-TrayState
})

$exitItem.add_Click({
    $timer.Stop()
    Stop-LrclibServer -Silent
    $script:NotifyIcon.Visible = $false
    [System.Windows.Forms.Application]::Exit()
})

try {
    Restore-ServerProcess
    Update-TrayState
    $script:LastKnownRunning = Test-ServerRunning
    $timer.Start()

    if ($AutoStart -and -not (Test-ServerRunning)) {
        Start-LrclibServer
    }

    [System.Windows.Forms.Application]::Run()
}
finally {
    $timer.Stop()
    $timer.Dispose()
    $script:NotifyIcon.Visible = $false
    $script:NotifyIcon.Dispose()
    $menu.Dispose()
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
