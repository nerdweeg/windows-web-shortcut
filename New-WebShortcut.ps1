<#
.SYNOPSIS
    Creates a desktop shortcut to a website, using the site's favicon as the icon.

.DESCRIPTION
    Prompts for (or accepts) a URL, downloads the site's favicon via Google's
    favicon service, converts it to an .ico file and creates a Windows shortcut
    (.lnk) that opens the URL in the default browser.

    Icons are stored in %LOCALAPPDATA%\WebsiteShortcuts so the shortcut keeps
    its icon after the script has finished.

    If the favicon cannot be downloaded, the shortcut is still created with the
    default icon.

.PARAMETER Url
    The website address. "https://" is added automatically if no scheme is given.
    If omitted, the script prompts for it interactively.

.PARAMETER Name
    The shortcut name. Defaults to the host name without "www." (e.g. "github.com").

.PARAMETER Destination
    Folder to create the shortcut in. Defaults to the current user's desktop.

.PARAMETER IconSize
    Requested favicon size in pixels. Defaults to 64.

.PARAMETER Force
    Overwrite an existing shortcut with the same name without asking.

.EXAMPLE
    .\New-WebShortcut.ps1
    Runs interactively and prompts for the URL and name.

.EXAMPLE
    .\New-WebShortcut.ps1 -Url github.com -Name GitHub
    Creates "GitHub.lnk" on the desktop pointing to https://github.com/.

.EXAMPLE
    .\New-WebShortcut.ps1 -Url https://example.com -Destination "$env:USERPROFILE\Links" -Force
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Url,

    [Parameter(Position = 1)]
    [string]$Name,

    [string]$Destination = [Environment]::GetFolderPath('Desktop'),

    [ValidateSet(16, 32, 48, 64, 128, 256)]
    [int]$IconSize = 64,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Show message boxes only when the script is run interactively (no -Url given),
# so it stays quiet and scriptable when called with parameters.
$interactive = -not $PSBoundParameters.ContainsKey('Url')

function Show-Message {
    param(
        [string]$Text,
        [string]$Title,
        [ValidateSet('Information', 'Error', 'Warning')]
        [string]$Icon = 'Information'
    )
    if (-not $interactive) { return }
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [void][System.Windows.Forms.MessageBox]::Show($Text, $Title, 'OK', $Icon)
    }
    catch {
        # No GUI available (e.g. Server Core); console output is enough.
        Write-Verbose "Could not show message box: $_"
    }
}

function ConvertTo-WebUri {
    param([string]$InputUrl)

    $InputUrl = $InputUrl.Trim()
    if ($InputUrl -notmatch '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
        $InputUrl = "https://$InputUrl"
    }

    $uri = $null
    if (-not [uri]::TryCreate($InputUrl, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin @('http', 'https') -or
        [string]::IsNullOrWhiteSpace($uri.Host)) {
        throw "Invalid URL: '$InputUrl'. Only http and https addresses are supported."
    }
    return $uri
}

function Get-SafeFileName {
    param([string]$Value)

    $invalid = [regex]::Escape(-join [System.IO.Path]::GetInvalidFileNameChars())
    $safe = ($Value -replace "[$invalid]", '_').Trim(' ', '.')
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'Website' }
    return $safe
}

function Save-FaviconAsIco {
    <#
        Downloads the favicon as PNG and wraps it in a single-image ICO container.
        Windows Vista and later support PNG-compressed images inside .ico files.
    #>
    param(
        [uri]$SiteUri,
        [string]$Path,
        [int]$Size
    )

    # Windows PowerShell 5.1 may default to TLS 1.0/1.1.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $faviconUrl = 'https://www.google.com/s2/favicons?domain_url={0}&sz={1}' -f [uri]::EscapeDataString($SiteUri.AbsoluteUri), $Size
    $response = Invoke-WebRequest -Uri $faviconUrl -UseBasicParsing -TimeoutSec 15
    $png = [byte[]]$response.Content

    # Validate the PNG signature and read the real dimensions from the IHDR chunk.
    $pngSignature = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A)
    if ($png.Length -lt 24 -or (Compare-Object $png[0..7] $pngSignature)) {
        throw 'The favicon service did not return a PNG image.'
    }
    $width  = ([int]$png[16] -shl 24) -bor ([int]$png[17] -shl 16) -bor ([int]$png[18] -shl 8) -bor [int]$png[19]
    $height = ([int]$png[20] -shl 24) -bor ([int]$png[21] -shl 16) -bor ([int]$png[22] -shl 8) -bor [int]$png[23]

    # In the ICO directory, 0 means 256 pixels.
    $icoWidth  = if ($width  -ge 256) { 0 } else { $width }
    $icoHeight = if ($height -ge 256) { 0 } else { $height }

    $stream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.BinaryWriter]::new($stream)
    try {
        # ICONDIR
        $writer.Write([uint16]0)            # Reserved
        $writer.Write([uint16]1)            # Type: 1 = icon
        $writer.Write([uint16]1)            # Number of images
        # ICONDIRENTRY
        $writer.Write([byte]$icoWidth)      # Width
        $writer.Write([byte]$icoHeight)     # Height
        $writer.Write([byte]0)              # Colors in palette (0 = none)
        $writer.Write([byte]0)              # Reserved
        $writer.Write([uint16]1)            # Color planes
        $writer.Write([uint16]32)           # Bits per pixel
        $writer.Write([uint32]$png.Length)  # Image data size
        $writer.Write([uint32]22)           # Image data offset (6 + 16)
        # Image data
        $writer.Write($png)
        $writer.Flush()

        [System.IO.File]::WriteAllBytes($Path, $stream.ToArray())
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }
}

try {
    if ($interactive) {
        Write-Host ''
        Write-Host '=== Create website shortcut ===' -ForegroundColor Cyan
        $Url = Read-Host 'Enter URL'
    }
    if ([string]::IsNullOrWhiteSpace($Url)) {
        throw 'No URL was entered.'
    }

    $uri = ConvertTo-WebUri $Url
    $hostName = $uri.Host -replace '^www\.', ''

    if (-not $Name) {
        $Name = $hostName
        if ($interactive) {
            $answer = Read-Host "Shortcut name [$Name]"
            if (-not [string]::IsNullOrWhiteSpace($answer)) { $Name = $answer }
        }
    }
    $Name = Get-SafeFileName $Name

    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) {
        throw "Destination folder does not exist: $Destination"
    }

    $shortcutPath = Join-Path $Destination "$Name.lnk"
    if ((Test-Path -LiteralPath $shortcutPath) -and -not $Force) {
        if (-not $interactive) {
            throw "A shortcut already exists: $shortcutPath (use -Force to overwrite)."
        }
        $overwrite = Read-Host "'$Name.lnk' already exists. Overwrite? (y/N)"
        if ($overwrite -notmatch '^(y|yes)$') {
            Write-Host 'Cancelled.' -ForegroundColor Yellow
            return
        }
    }

    # Download favicon. Failure here is not fatal; the shortcut just gets the default icon.
    $iconDir = Join-Path $env:LOCALAPPDATA 'WebsiteShortcuts'
    New-Item -ItemType Directory -Force -Path $iconDir | Out-Null
    $iconPath = Join-Path $iconDir ((Get-SafeFileName $hostName) + '.ico')

    Write-Host 'Downloading favicon...'
    $hasIcon = $false
    try {
        Save-FaviconAsIco -SiteUri $uri -Path $iconPath -Size $IconSize
        $hasIcon = $true
    }
    catch {
        Write-Warning "Could not download favicon, using the default icon instead. ($($_.Exception.Message))"
    }

    # Create the shortcut.
    $shell = New-Object -ComObject WScript.Shell
    try {
        $shortcut = $shell.CreateShortcut($shortcutPath)
        $shortcut.TargetPath = $uri.AbsoluteUri
        $shortcut.Description = $uri.AbsoluteUri
        if ($hasIcon) { $shortcut.IconLocation = "$iconPath,0" }
        $shortcut.Save()
    }
    finally {
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
    }

    Write-Host ''
    Write-Host 'Done! Shortcut created:' -ForegroundColor Green
    Write-Host $shortcutPath
    Write-Host ''

    Show-Message -Text "A shortcut to $Name has been created:`n$shortcutPath" -Title 'Done'
}
catch {
    Write-Host "Could not create shortcut: $($_.Exception.Message)" -ForegroundColor Red
    Show-Message -Text "Could not create shortcut:`n$($_.Exception.Message)" -Title 'Error' -Icon Error
    exit 1
}
