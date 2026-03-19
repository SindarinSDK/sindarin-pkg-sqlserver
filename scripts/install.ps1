# Sindarin SQL Server Libraries Installer for Windows
# Downloads and extracts the latest sindarin-pkg-sqlserver libs to ./libs/windows

$ErrorActionPreference = "Stop"

$REPO = "SindarinSDK/sindarin-pkg-sqlserver"
$INSTALL_DIR = Join-Path (Get-Location) "libs\windows"

function Write-Status {
    param(
        [string]$Message,
        [string]$Type = "Info"
    )

    $color = switch ($Type) {
        "Info" { "Cyan" }
        "Success" { "Green" }
        "Warning" { "Yellow" }
        "Error" { "Red" }
        default { "White" }
    }

    Write-Host $Message -ForegroundColor $color
}

function Get-LatestWindowsRelease {
    Write-Status "Fetching latest release information..."

    $apiUrl = "https://api.github.com/repos/$REPO/releases/latest"

    try {
        $release = Invoke-RestMethod -Uri $apiUrl -Headers @{ "User-Agent" = "sindarin-installer" }

        $asset = $release.assets | Where-Object { $_.name -like "*windows-x64*.zip" } | Select-Object -First 1

        if (-not $asset) {
            throw "No Windows release asset found"
        }

        return @{
            Url = $asset.browser_download_url
            Name = $asset.name
            Version = $release.tag_name
        }
    }
    catch {
        Write-Status "Failed to fetch release info: $_" -Type "Error"
        exit 1
    }
}

function Install-SqlServerLibs {
    param(
        [hashtable]$Release
    )

    # Check package cache first
    $cacheDir = Join-Path (Join-Path $HOME ".sn-cache") "downloads"
    $cachedZip = Join-Path $cacheDir $Release.Name

    if (Test-Path $cachedZip) {
        Write-Status "Using cached $($Release.Name)"
    }
    else {
        Write-Status "Downloading $($Release.Name)..."

        if (-not (Test-Path $cacheDir)) {
            New-Item -ItemType Directory -Path $cacheDir | Out-Null
        }

        try {
            Invoke-WebRequest -Uri $Release.Url -OutFile $cachedZip -UseBasicParsing
        }
        catch {
            Write-Status "Download failed: $_" -Type "Error"
            if (Test-Path $cachedZip) {
                Remove-Item -Force $cachedZip -ErrorAction SilentlyContinue
            }
            exit 1
        }
    }

    $tempDir = Join-Path $env:TEMP "sindarin-sqlserver-install"

    if (Test-Path $tempDir) {
        Remove-Item -Recurse -Force $tempDir
    }
    New-Item -ItemType Directory -Path $tempDir | Out-Null

    try {
        Write-Status "Extracting to $INSTALL_DIR..."

        if (Test-Path $INSTALL_DIR) {
            Remove-Item -Recurse -Force $INSTALL_DIR
        }
        New-Item -ItemType Directory -Path $INSTALL_DIR | Out-Null

        $extractDir = Join-Path $tempDir "extracted"
        Expand-Archive -Path $cachedZip -DestinationPath $extractDir -Force

        $contents = Get-ChildItem -Path $extractDir
        if ($contents.Count -eq 1 -and $contents[0].PSIsContainer) {
            $innerDir = $contents[0].FullName
            Get-ChildItem -Path $innerDir | Move-Item -Destination $INSTALL_DIR
        }
        else {
            Get-ChildItem -Path $extractDir | Move-Item -Destination $INSTALL_DIR
        }

        Write-Status "Successfully installed sindarin-sqlserver $($Release.Version) to $INSTALL_DIR" -Type "Success"
    }
    catch {
        Write-Status "Installation failed: $_" -Type "Error"
        exit 1
    }
    finally {
        if (Test-Path $tempDir) {
            Remove-Item -Recurse -Force $tempDir -ErrorAction SilentlyContinue
        }
    }
}

# Main execution
Write-Status "Sindarin SQL Server Libraries Installer" -Type "Info"
Write-Status "========================================" -Type "Info"

$release = Get-LatestWindowsRelease
Install-SqlServerLibs -Release $release

Write-Status ""
Write-Status "Installation complete!" -Type "Success"
