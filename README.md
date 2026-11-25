# Windows Web Shortcut

A small PowerShell script that creates a desktop shortcut to any website and uses the site's **favicon** as the shortcut icon.

## Features

- Interactive (just double-click) or scriptable with parameters
- Downloads the site's favicon and converts it to `.ico` automatically
- Accepts bare domains such as `github.com` and adds `https://` for you
- Falls back to the default icon if no favicon is available
- Asks before overwriting an existing shortcut (or use `-Force`)
- No dependencies. Works with Windows PowerShell 5.1 and PowerShell 7+

## Usage

### Double-click

1. Download `New-WebShortcut.ps1` and `New-WebShortcut.cmd` into the same folder.
2. Double-click **`New-WebShortcut.cmd`**.
3. Enter a URL and, optionally, a name.

The `.cmd` launcher runs the script with `-ExecutionPolicy Bypass` for that single run, so you don't need to change your system's execution policy.

### From PowerShell

```powershell
# Interactive
.\New-WebShortcut.ps1

# With parameters
.\New-WebShortcut.ps1 -Url github.com -Name GitHub

# Custom folder, overwrite if it exists
.\New-WebShortcut.ps1 -Url https://example.com -Destination "$env:USERPROFILE\Links" -Force
```

| Parameter      | Description                                                  | Default                      |
| -------------- | ------------------------------------------------------------ | ---------------------------- |
| `-Url`         | Website address. Prompts if omitted.                         | *(prompt)*                   |
| `-Name`        | Shortcut name.                                               | Host name without `www.`     |
| `-Destination` | Folder to place the shortcut in.                             | Desktop                      |
| `-IconSize`    | Favicon size: 16, 32, 48, 64, 128 or 256.                    | `64`                         |
| `-Force`       | Overwrite an existing shortcut without asking.               | Off                          |

Run `Get-Help .\New-WebShortcut.ps1 -Full` for full documentation.

If you run the script with `-Url`, no message boxes are shown, so it can be used in other scripts. It returns exit code `1` on failure.

## How it works

1. The favicon is fetched as a PNG from Google's favicon service (`https://www.google.com/s2/favicons`).
2. The PNG is wrapped in an ICO container (Windows Vista and later support PNG images inside `.ico` files) and saved to `%LOCALAPPDATA%\WebsiteShortcuts`.
3. A `.lnk` shortcut is created with `WScript.Shell` that points to the URL and uses that icon.

> **Privacy note:** the domain of the URL is sent to Google to look up the favicon.

## Uninstall

Delete the shortcut, and optionally the icon cache folder `%LOCALAPPDATA%\WebsiteShortcuts`.

## License

[MIT](LICENSE)
