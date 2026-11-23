#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Offline, [switch]$PrepareToolsOnly)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.IO.Compression.FileSystem

$version = '4.3'
$release = "$version-stable"
$releaseUrl = "https://github.com/godotengine/godot-builds/releases/download/$release"
$toolDir = Join-Path $PSScriptRoot ".godot\build-tools\$release"
$siblingCache = Join-Path (Split-Path -Parent $PSScriptRoot) "test-game\.godot\build-tools\$release"
$templateDir = Join-Path $toolDir "editor_data\export_templates\$version.stable"
$editorName = "Godot_v${release}_win64.exe"
$consoleName = "Godot_v${release}_win64_console.exe"
$editor = Join-Path $toolDir $consoleName
$stage = Join-Path $PSScriptRoot '.godot\windows-export'
$output = Join-Path $PSScriptRoot 'build'
$exeName = 'Stomp and Scurry - LAN.exe'
$stagedExe = Join-Path $stage $exeName
$exePath = Join-Path $output $exeName
$launcherName = 'Stomp and Scurry Launcher - LAN.exe'
$launcherProject = Join-Path $PSScriptRoot 'launcher\app'
$stagedLauncher = Join-Path $stage $launcherName
$engineError = '(?i)(SCRIPT ERROR:|(^|\s)ERROR:|Parse Error|Failed to load script)'

function Get-CachedDownload([string]$Name) {
    $local = Join-Path $toolDir $Name
    if (Test-Path -LiteralPath $local -PathType Leaf) { return $local }
    $sibling = Join-Path $siblingCache $Name
    if (Test-Path -LiteralPath $sibling -PathType Leaf) {
        Write-Host "Using cached $Name from test-game."
        return $sibling
    }
    if ($Offline) {
        throw "Offline build requires $Name in either project's build-tools cache. Run without -Offline to download it."
    }
    $partial = "$local.partial"
    Write-Host "Downloading $Name ..."
    try {
        Invoke-WebRequest -Uri "$releaseUrl/$Name" -OutFile $partial -UseBasicParsing -TimeoutSec 3600
        Move-Item -LiteralPath $partial -Destination $local -Force
    } finally {
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
    }
    return $local
}

function Get-VerifiedArchive([string]$Name) {
    $manifest = Get-CachedDownload 'SHA512-SUMS.txt'
    $pattern = '^([a-fA-F0-9]{128})\s+\*?' + [regex]::Escape($Name) + '$'
    $expectedHash = $null
    foreach ($line in Get-Content -LiteralPath $manifest) {
        if ($line.Trim() -match $pattern) { $expectedHash = $Matches[1]; break }
    }
    if (-not $expectedHash) { throw "Missing official checksum for $Name." }
    $archive = Get-CachedDownload $Name
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA512).Hash -ne $expectedHash) {
        if ($archive -eq (Join-Path $toolDir $Name)) {
            Remove-Item -LiteralPath $archive -Force
        }
        throw "SHA512 verification failed for $archive. Restore a clean copy of the archive and retry."
    }
    return $archive
}

function Expand-BuildEntries([string]$ArchivePath, [hashtable]$Entries) {
    $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        foreach ($name in $Entries.Keys) {
            $entry = $archive.GetEntry($name)
            if ($null -eq $entry) { throw "Missing $name in $ArchivePath." }
            $destination = $Entries[$name]
            $temporary = "$destination.partial"
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $temporary, $true)
            Move-Item -LiteralPath $temporary -Destination $destination -Force
        }
    } finally {
        $archive.Dispose()
    }
}

function Invoke-GodotEditor([string]$Step, [string[]]$Arguments) {
    Write-Host $Step
    $log = Join-Path $stage ($Step.Replace(' ', '-') + '.log')
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $messages = @(& $editor @Arguments 2>&1)
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    $messages | Out-File -FilePath $log -Encoding utf8
    $messages | ForEach-Object { Write-Host "$_" }
    if ($code -ne 0 -or ($messages -match $engineError)) {
        throw "$Step failed (exit code $code). See $log."
    }
}

function Test-PackagedStartup([string]$Executable) {
    Write-Host 'Checking Windows executable startup ...'
    $smokeDir = Join-Path $stage 'smoke-test'
    New-Item -ItemType Directory -Path $smokeDir -Force | Out-Null
    $log = Join-Path $smokeDir (([IO.Path]::GetFileNameWithoutExtension($Executable)) + '-startup.log')
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
    $argsForGame = "--headless --quit-after 10 --log-file `"$log`""
    $process = Start-Process -FilePath $Executable -WorkingDirectory $smokeDir -ArgumentList $argsForGame -PassThru
    try {
        if (-not $process.WaitForExit(30000)) {
            $process.Kill()
            throw 'The packaged game did not exit within 30 seconds.'
        }
        if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $log -PathType Leaf)) {
            throw "The packaged game did not start successfully (exit code $($process.ExitCode)). See $smokeDir."
        }
        if (Select-String -LiteralPath $log -Pattern $engineError -Quiet) {
            throw "The packaged game reported an error. See $log."
        }
    } finally {
        $process.Dispose()
    }
}

try {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::Is64BitOperatingSystem) {
        throw 'This build script requires 64-bit Windows.'
    }
    New-Item -ItemType Directory -Path $toolDir, $templateDir, $stage, $output -Force | Out-Null
    if (-not (Test-Path -LiteralPath $editor -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $toolDir $editorName) -PathType Leaf)) {
        $archive = Get-VerifiedArchive "Godot_v${release}_win64.exe.zip"
        $entries = @{}
        $entries[$editorName] = Join-Path $toolDir $editorName
        $entries[$consoleName] = $editor
        Expand-BuildEntries $archive $entries
    }
    Set-Content -LiteralPath (Join-Path $toolDir '_sc_') -Value '' -Encoding ascii

    $templates = @{}
    foreach ($name in @('windows_debug_x86_64.exe', 'windows_release_x86_64.exe')) {
        $destination = Join-Path $templateDir $name
        if (-not (Test-Path -LiteralPath $destination -PathType Leaf)) {
            $templates["templates/$name"] = $destination
        }
    }
    if ($templates.Count -gt 0) {
        Expand-BuildEntries (Get-VerifiedArchive "Godot_v${release}_export_templates.tpz") $templates
    }

    if ($PrepareToolsOnly) { return }
    if (Test-Path -LiteralPath $stagedExe) { Remove-Item -LiteralPath $stagedExe -Force }
    Invoke-GodotEditor 'Import project' @('--headless', '--path', $PSScriptRoot, '--editor', '--import')
    Invoke-GodotEditor 'Export Windows release' @('--headless', '--path', $PSScriptRoot,
        '--export-release', 'Windows Desktop', $stagedExe)
    if (-not (Test-Path -LiteralPath $stagedExe -PathType Leaf)) { throw 'Godot did not create the executable.' }
    Test-PackagedStartup $stagedExe
    $manifest = Join-Path $output 'launcher-release.json'
    $launcherPath = Join-Path $output $launcherName
    $updaterPath = Join-Path $launcherProject 'updater.gd'
    $versionLine = Select-String -LiteralPath $updaterPath -Pattern '^const VERSION := (\d+)$' | Select-Object -First 1
    if (-not $versionLine) { throw 'Could not find the embedded launcher version.' }
    $launcherVersion = [int]$versionLine.Matches[0].Groups[1].Value
    $reuseLauncher = $false
    if ((Test-Path -LiteralPath $launcherPath -PathType Leaf) -and (Test-Path -LiteralPath $manifest -PathType Leaf)) {
        try {
            $previous = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
            $hasLauncherMetadata = $previous.PSObject.Properties.Name -contains 'launcher_version' -and
                $previous.PSObject.Properties.Name -contains 'launcher_hash'
            if ($hasLauncherMetadata -and $previous.launcher_version -eq $launcherVersion) {
                $reuseLauncher = (Get-FileHash -LiteralPath $launcherPath -Algorithm SHA256).Hash -eq $previous.launcher_hash
            }
        } catch {
            $reuseLauncher = $false
        }
    }
    if ($reuseLauncher) {
        Write-Host "Reusing launcher version $launcherVersion."
    } else {
        if (Test-Path -LiteralPath $stagedLauncher) { Remove-Item -LiteralPath $stagedLauncher -Force }
        Invoke-GodotEditor 'Import launcher' @('--headless', '--path', $launcherProject, '--editor', '--import')
        Invoke-GodotEditor 'Export Windows launcher' @('--headless', '--path', $launcherProject,
            '--export-release', 'Windows Desktop', $stagedLauncher)
        if (-not (Test-Path -LiteralPath $stagedLauncher -PathType Leaf)) { throw 'Godot did not create the launcher.' }
        Test-PackagedStartup $stagedLauncher
        Copy-Item -LiteralPath $stagedLauncher -Destination $launcherPath -Force
    }
    Copy-Item -LiteralPath $stagedExe -Destination $exePath -Force
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'GODOT-NOTICES.txt') -Destination $output -Force
    @'
Stomp & Scurry

Open Stomp and Scurry - LAN.exe on 64-bit Windows and select Play solo or Host LAN.
Use WASD or the arrow keys to move the ant away from the shoe's shadow.
The spider chases the ant in both modes. Run over a yellow lightning bolt
for five seconds of extra speed, or a blue shield that lasts 15 seconds
and blocks one hit.
Press Space for an escape jump. The ant moves slower for 1.7 seconds
after landing and can jump again once it recovers.
Watch for 32-meteor showers, spider rushes, sideways winds, and slowing
snail trails in both modes. The snail has its own timer and can overlap
other events. Slime lasts six seconds and slows the ant
to 25% speed.
Each stomp you dodge earns a point. The shoe speeds up as you play.
Press Esc to pause or resume and M to toggle sound.

LAN play (two to four computers on the same network)
One player selects Host LAN. The others enter the host's local IPv4 address and
select Join LAN. Everyone chooses Ant or Shoe and presses Ready. The round
starts when all players are ready and there is at least one of each role.
Shoes aim with the mouse and left-click to stomp. A caught ant becomes a
green zombie ant. Use WASD or the arrow keys to chase and touch live ants.
The round ends when the last live ant turns. The host can reopen the lobby.
The shoe player can click a diamond to power the next stomp. The orange clock
makes it land faster and the purple arrows make it wider. The green Area
Denial pickup blocks the stomp's footprint for eight seconds.
If Windows Firewall asks, allow the game on private networks (UDP port 24567).

The executable contains the game data. See GODOT-NOTICES.txt for engine licenses.
'@ | Set-Content -LiteralPath (Join-Path $output 'README.txt') -Encoding utf8
    $nextManifest = "$manifest.partial"
    @{
        file = $exeName
        build = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToLowerInvariant()
        launcher_version = $launcherVersion
        launcher_hash = (Get-FileHash -LiteralPath $launcherPath -Algorithm SHA256).Hash.ToLowerInvariant()
    } |
        ConvertTo-Json -Compress | Set-Content -LiteralPath $nextManifest -Encoding ascii
    if (Test-Path -LiteralPath $manifest -PathType Leaf) {
        [IO.File]::Replace($nextManifest, $manifest, [NullString]::Value)
    } else {
        [IO.File]::Move($nextManifest, $manifest)
    }
    Write-Host "Built and checked $exePath" -ForegroundColor Green
} catch {
    Write-Host "Build failed. $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
