#requires -Version 5.1
<#
.SYNOPSIS
    Adds or removes "Open with VSCodium" entries in Windows File Explorer.

.DESCRIPTION
    Installs three per-user Explorer context-menu entries:
      - Files
      - Folders
      - The background of a folder

    The script does not require administrator privileges. It writes only to
    HKEY_CURRENT_USER\Software\Classes, so it affects the current Windows user.

    VSCodium is detected from common installation locations, its running
    process, PATH, App Paths, and uninstall registry entries. Use -VSCodiumPath
    to specify a portable or otherwise non-standard installation.

.PARAMETER VSCodiumPath
    Optional path to VSCodium.exe or the directory containing VSCodium.exe.

.PARAMETER Uninstall
    Removes the three context-menu entries created by this script.

.EXAMPLE
    .\Install-VSCodiumContextMenu.ps1

.EXAMPLE
    .\Install-VSCodiumContextMenu.ps1 -VSCodiumPath "D:\Apps\VSCodium\VSCodium.exe"

.EXAMPLE
    .\Install-VSCodiumContextMenu.ps1 -Uninstall
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string] $VSCodiumPath,

    [Parameter()]
    [switch] $Uninstall
)

$ErrorActionPreference = 'Stop'

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    throw 'This script can only run on Windows.'
}

$registryRoot = [Microsoft.Win32.Registry]::CurrentUser
$contextMenuPaths = @(
    'Software\Classes\*\shell\Open with VSCodium',
    'Software\Classes\Directory\shell\Open with VSCodium',
    'Software\Classes\Directory\Background\shell\Open with VSCodium'
)

function Remove-VSCodiumContextMenu {
    foreach ($registryPath in $contextMenuPaths) {
        # DeleteSubKeyTree(..., $false) does nothing when the key is absent.
        $registryRoot.DeleteSubKeyTree($registryPath, $false)
    }
}

function Get-VSCodiumExecutable {
    param(
        [Parameter()]
        [string] $ExplicitPath
    )

    # An explicit path takes priority and must be valid; do not silently use
    # another VSCodium installation if the user supplied a bad path.
    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath)) {
        $resolvedPath = [Environment]::ExpandEnvironmentVariables($ExplicitPath.Trim().Trim('"'))

        if (Test-Path -LiteralPath $resolvedPath -PathType Container) {
            $resolvedPath = Join-Path $resolvedPath 'VSCodium.exe'
        }

        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
            throw "VSCodium was not found at '$ExplicitPath'. Supply the path to VSCodium.exe or its containing directory."
        }

        if ([IO.Path]::GetFileName($resolvedPath) -ine 'VSCodium.exe') {
            throw "The supplied file is not named VSCodium.exe: '$resolvedPath'."
        }

        return (Get-Item -LiteralPath $resolvedPath).FullName
    }

    $candidates = New-Object 'System.Collections.Generic.List[string]'

    # Adds a possible executable, installation directory, or codium.cmd path.
    # Only VSCodium.exe is ultimately accepted as the Explorer command target.
    function Add-VSCodiumCandidate {
        param([string] $CandidatePath)

        if ([string]::IsNullOrWhiteSpace($CandidatePath)) {
            return
        }

        $candidate = [Environment]::ExpandEnvironmentVariables($CandidatePath.Trim())

        # DisplayIcon registry values can look like: "C:\Path\VSCodium.exe",0
        if ($candidate -match '^"([^"]+)"') {
            $candidate = $Matches[1]
        }
        else {
            $candidate = $candidate -replace ',\s*-?\d+\s*$', ''
        }

        try {
            if (Test-Path -LiteralPath $candidate -PathType Container) {
                [void] $candidates.Add((Join-Path $candidate 'VSCodium.exe'))
                return
            }

            $leafName = [IO.Path]::GetFileName($candidate)

            if ($leafName -ieq 'VSCodium.exe') {
                [void] $candidates.Add($candidate)
                return
            }

            # The official command-line launcher is commonly in <install>\bin.
            if ($leafName -ieq 'codium.cmd' -or $leafName -ieq 'codium.bat') {
                $binDirectory = Split-Path -Parent $candidate
                $installDirectory = Split-Path -Parent $binDirectory
                if ($installDirectory) {
                    [void] $candidates.Add((Join-Path $installDirectory 'VSCodium.exe'))
                }
            }
        }
        catch {
            # Ignore malformed or inaccessible discovery candidates.
        }
    }

    # 1. If VSCodium is already running, its executable path also supports
    #    portable installations that are not registered with Windows.
    foreach ($process in (Get-Process -Name 'VSCodium' -ErrorAction SilentlyContinue)) {
        try {
            Add-VSCodiumCandidate -CandidatePath $process.Path
        }
        catch {
            # The process path may be inaccessible; continue discovery.
        }
    }

    # 2. Look for the command-line launcher on PATH.
    foreach ($command in (Get-Command -Name 'codium', 'codium.cmd' -ErrorAction SilentlyContinue)) {
        if ($command.CommandType -eq 'Application') {
            Add-VSCodiumCandidate -CandidatePath $command.Source
        }
    }

    # 3. Common installer and package-manager locations.
    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    $programFiles = [Environment]::GetFolderPath('ProgramFiles')
    $programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')

    $knownDirectories = @()
    if ($localAppData) {
        $knownDirectories += Join-Path $localAppData 'Programs\VSCodium'
    }
    if ($programFiles) {
        $knownDirectories += Join-Path $programFiles 'VSCodium'
    }
    if ($programFilesX86) {
        $knownDirectories += Join-Path $programFilesX86 'VSCodium'
    }
    if ($env:USERPROFILE) {
        $knownDirectories += Join-Path $env:USERPROFILE 'scoop\apps\vscodium\current'
    }
    if ($env:ProgramData) {
        $knownDirectories += Join-Path $env:ProgramData 'scoop\apps\vscodium\current'
    }

    if ($env:SCOOP) {
        $knownDirectories += Join-Path $env:SCOOP 'apps\vscodium\current'
    }
    if ($env:SCOOP_GLOBAL) {
        $knownDirectories += Join-Path $env:SCOOP_GLOBAL 'apps\vscodium\current'
    }
    if ($env:ProgramW6432) {
        $knownDirectories += Join-Path $env:ProgramW6432 'VSCodium'
    }

    foreach ($directory in $knownDirectories) {
        Add-VSCodiumCandidate -CandidatePath $directory
    }

    # 4. App Paths registry entries, if the installer created them.
    $appPathKeys = @(
        @{ Hive = [Microsoft.Win32.Registry]::CurrentUser; Path = 'Software\Microsoft\Windows\CurrentVersion\App Paths\VSCodium.exe' },
        @{ Hive = [Microsoft.Win32.Registry]::LocalMachine; Path = 'Software\Microsoft\Windows\CurrentVersion\App Paths\VSCodium.exe' },
        @{ Hive = [Microsoft.Win32.Registry]::LocalMachine; Path = 'Software\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\VSCodium.exe' }
    )

    foreach ($entry in $appPathKeys) {
        $key = $null
        try {
            $key = $entry.Hive.OpenSubKey($entry.Path)
            if ($key) {
                Add-VSCodiumCandidate -CandidatePath ([string] $key.GetValue(''))
            }
        }
        catch {
            # Continue if a registry location cannot be read.
        }
        finally {
            if ($key) { $key.Dispose() }
        }
    }

    # 5. Read installer metadata. DisplayIcon and InstallLocation often reveal
    #    custom paths, including per-user and WinGet installations.
    $uninstallKeys = @(
        @{ Hive = [Microsoft.Win32.Registry]::CurrentUser; Path = 'Software\Microsoft\Windows\CurrentVersion\Uninstall' },
        @{ Hive = [Microsoft.Win32.Registry]::LocalMachine; Path = 'Software\Microsoft\Windows\CurrentVersion\Uninstall' },
        @{ Hive = [Microsoft.Win32.Registry]::LocalMachine; Path = 'Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' }
    )

    foreach ($entry in $uninstallKeys) {
        $uninstallRoot = $null
        try {
            $uninstallRoot = $entry.Hive.OpenSubKey($entry.Path)
            if (-not $uninstallRoot) { continue }

            foreach ($subKeyName in $uninstallRoot.GetSubKeyNames()) {
                $appKey = $null
                try {
                    $appKey = $uninstallRoot.OpenSubKey($subKeyName)
                    if (-not $appKey) { continue }

                    $displayName = [string] $appKey.GetValue('DisplayName', '')
                    if ($displayName -match 'VSCodium') {
                        Add-VSCodiumCandidate -CandidatePath ([string] $appKey.GetValue('InstallLocation', ''))
                        Add-VSCodiumCandidate -CandidatePath ([string] $appKey.GetValue('DisplayIcon', ''))
                    }
                }
                catch {
                    # Ignore individual uninstall entries that cannot be read.
                }
                finally {
                    if ($appKey) { $appKey.Dispose() }
                }
            }
        }
        catch {
            # Continue if an uninstall registry location cannot be read.
        }
        finally {
            if ($uninstallRoot) { $uninstallRoot.Dispose() }
        }
    }

    # 6. Check PATH directories directly, including the parent of a \bin path.
    foreach ($pathDirectory in ($env:PATH -split [IO.Path]::PathSeparator)) {
        if ([string]::IsNullOrWhiteSpace($pathDirectory)) { continue }

        Add-VSCodiumCandidate -CandidatePath (Join-Path $pathDirectory 'VSCodium.exe')

        if ([IO.Path]::GetFileName($pathDirectory.TrimEnd([char[]]@('\', '/'))) -ieq 'bin') {
            $installDirectory = Split-Path -Parent $pathDirectory
            if ($installDirectory) {
                Add-VSCodiumCandidate -CandidatePath (Join-Path $installDirectory 'VSCodium.exe')
            }
        }
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            try {
                if ([IO.Path]::GetFileName($candidate) -ieq 'VSCodium.exe') {
                    return (Get-Item -LiteralPath $candidate).FullName
                }
            }
            catch {
                # Try the next candidate if this one is inaccessible.
            }
        }
    }

    throw @'
Could not locate VSCodium.exe automatically.
Run the script again with -VSCodiumPath and provide the path to VSCodium.exe
or the directory containing it. Example:
  .\Install-VSCodiumContextMenu.ps1 -VSCodiumPath "D:\Apps\VSCodium\VSCodium.exe"
'@
}

if ($Uninstall) {
    Remove-VSCodiumContextMenu
    Write-Host 'Removed the Open with VSCodium context-menu entries for the current user.' -ForegroundColor Green
    return
}

$vscodiumExe = Get-VSCodiumExecutable -ExplicitPath $VSCodiumPath

$entries = @(
    @{ RegistryPath = 'Software\Classes\*\shell\Open with VSCodium'; Argument = '%1' },
    @{ RegistryPath = 'Software\Classes\Directory\shell\Open with VSCodium'; Argument = '%1' },
    @{ RegistryPath = 'Software\Classes\Directory\Background\shell\Open with VSCodium'; Argument = '%V' }
)

foreach ($entry in $entries) {
    $verbKey = $null
    $commandKey = $null

    try {
        $verbKey = $registryRoot.CreateSubKey($entry.RegistryPath)
        if (-not $verbKey) {
            throw "Could not create registry key: HKCU\$($entry.RegistryPath)"
        }

        $verbKey.SetValue('', 'Open with VSCodium', [Microsoft.Win32.RegistryValueKind]::String)
        $verbKey.SetValue('Icon', $vscodiumExe, [Microsoft.Win32.RegistryValueKind]::String)

        $commandKey = $verbKey.CreateSubKey('command')
        if (-not $commandKey) {
            throw "Could not create command registry key under: HKCU\$($entry.RegistryPath)"
        }

        # Keep both the executable path and the Explorer-supplied path quoted.
        $commandLine = '"{0}" "{1}"' -f $vscodiumExe, $entry.Argument
        $commandKey.SetValue('', $commandLine, [Microsoft.Win32.RegistryValueKind]::String)
    }
    finally {
        if ($commandKey) { $commandKey.Dispose() }
        if ($verbKey) { $verbKey.Dispose() }
    }
}

Write-Host 'Installed Open with VSCodium for files, folders, and folder backgrounds.' -ForegroundColor Green
Write-Host "VSCodium: $vscodiumExe"
Write-Host 'The entries are installed for the current Windows user only; administrator rights are not required.'
