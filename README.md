# Open with VSCodium for Windows

A self-contained PowerShell script that adds **Open with VSCodium** to File Explorer for files, folders, and the background of a folder.

## Install

1. Download `Install-VSCodiumContextMenu.ps1`.
2. Open PowerShell in the folder containing the script.
3. Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-VSCodiumContextMenu.ps1
```

Administrator rights are not required. The entries are installed for the **current Windows user** only.

## Portable or custom installation

The script tries to locate VSCodium automatically. If it cannot find your installation, pass the path to `VSCodium.exe` or its containing folder:

```powershell
.\Install-VSCodiumContextMenu.ps1 -VSCodiumPath "D:\Apps\VSCodium\VSCodium.exe"
```

## Uninstall

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-VSCodiumContextMenu.ps1 -Uninstall
```

The uninstall option removes only the three `Open with VSCodium` registry entries created by this script.

## Windows 11 note

Windows 11 may show traditional registry context-menu entries under **Show more options** (the classic context menu). This script does not install a native Windows 11 modern-menu COM extension.

## Supported entries

- Files: opens the selected file in VSCodium.
- Folders: opens the selected folder in VSCodium.
- Folder background: opens the current folder in VSCodium.

The script writes to `HKEY_CURRENT_USER\Software\Classes`; it does not change machine-wide registry settings.
