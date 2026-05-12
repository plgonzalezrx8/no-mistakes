$ErrorActionPreference = "Stop"

$repo = "kunchenguid/no-mistakes"
$installDir = "$env:LOCALAPPDATA\no-mistakes"
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "amd64" }

$release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repo/releases/latest"
$version = $release.tag_name
if (-not $version) {
    throw "Could not determine latest release"
}

$filename = "no-mistakes-$version-windows-$arch.zip"
$url = "https://github.com/$repo/releases/download/$version/$filename"
$checksumsUrl = "https://github.com/$repo/releases/download/$version/checksums.txt"

$tmpDir = New-TemporaryFile | ForEach-Object {
    Remove-Item $_
    New-Item -ItemType Directory -Path $_
}

try {
    $archivePath = "$tmpDir\$filename"
    $checksumsPath = "$tmpDir\checksums.txt"

    Write-Host "Downloading no-mistakes $version for windows/$arch..."
    Invoke-WebRequest -Uri $url -OutFile $archivePath
    Invoke-WebRequest -Uri $checksumsUrl -OutFile $checksumsPath

    $checksumLine = Get-Content $checksumsPath | Where-Object {
        ($_ -split '\s+').Length -ge 2 -and ($_ -split '\s+')[1] -eq $filename
    } | Select-Object -First 1
    if (-not $checksumLine) {
        throw "Checksum not found for $filename"
    }
    $expectedChecksum = ($checksumLine -split '\s+')[0].ToLowerInvariant()
    $actualChecksum = (Get-FileHash -Algorithm SHA256 -Path $archivePath).Hash.ToLowerInvariant()
    if ($actualChecksum -ne $expectedChecksum) {
        throw "Checksum mismatch for $filename: got $actualChecksum, want $expectedChecksum"
    }

    Expand-Archive -Path $archivePath -DestinationPath $tmpDir -Force

    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    Move-Item -Path "$tmpDir\no-mistakes.exe" -Destination "$installDir\no-mistakes.exe" -Force
} finally {
    Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
}

$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$installDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$installDir", "User")
    Write-Host "Added $installDir to user PATH. Restart your terminal."
}

if ($env:NO_MISTAKES_START_DAEMON -eq "1") {
    $restart = Start-Process -FilePath "$installDir\no-mistakes.exe" -ArgumentList @(
        "daemon",
        "restart"
    ) -Wait -PassThru -NoNewWindow
    if ($restart.ExitCode -ne 0) {
        throw "Failed to restart daemon (exit code $($restart.ExitCode))"
    }
} else {
    Write-Host "Daemon not started. Run 'no-mistakes daemon restart' or set NO_MISTAKES_START_DAEMON=1 during install."
}

Write-Host "no-mistakes $version installed to $installDir\no-mistakes.exe"
