#Requires -Version 7.0

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$DevContainer,
    [ValidateSet('Keep', 'Append', 'Override')]
    [string]$ExistingFileAction = 'Append'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Force) {
    if ($PSBoundParameters.ContainsKey('ExistingFileAction') -and $ExistingFileAction -ne 'Override') {
        throw '-Force cannot be combined with -ExistingFileAction Keep or Append.'
    }

    $ExistingFileAction = 'Override'
}

$ProfileUrl = 'https://raw.githubusercontent.com/wesleycamargo/dotfiles/refs/heads/main/Microsoft.VSCode_profile.ps1'
$GitConfigUrl = 'https://raw.githubusercontent.com/wesleycamargo/dotfiles/refs/heads/main/.gitconfig'
$VSCodeSettingsUrl = 'https://raw.githubusercontent.com/wesleycamargo/dotfiles/refs/heads/main/.vscode/settings.json'

function Set-ManagedFileContent {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Content,
        [Parameter(Mandatory)]
        [string]$Label,
        [Parameter(Mandatory)]
        [ValidateSet('Keep', 'Append', 'Override')]
        [string]$OnExists,
        [switch]$SkipIfExactMatch,
        [switch]$SkipIfContains
    )

    $targetDir = Split-Path -Path $Path -Parent
    if ($targetDir) {
        New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    }

    $newContent = $Content.Trim()
    $isJsonFile = $Path -match '\.json$'

    if (Test-Path $Path) {
        $existingContent = Get-Content -Path $Path -Raw

        if ($SkipIfContains -and $existingContent -and $existingContent.Contains($newContent)) {
            Write-Host "$Label already contains the configuration. Skipping."
            return
        }

        if ($SkipIfExactMatch -and $existingContent -and $existingContent.Trim() -eq $newContent) {
            Write-Host "$Label already matches remote content. Skipping."
            return
        }

        switch ($OnExists) {
            'Keep' {
                Write-Host "$Label already exists. Keeping existing file: $Path"
                return
            }
            'Append' {
                Write-Host "Appending to existing $($Label): $Path"
                
                if ($isJsonFile) {
                    try {
                        $existingJson = $existingContent | ConvertFrom-Json -AsHashtable -ErrorAction Stop
                        $newJson = $newContent | ConvertFrom-Json -AsHashtable -ErrorAction Stop
                        
                        foreach ($key in $newJson.Keys) {
                            $existingJson[$key] = $newJson[$key]
                        }
                        
                        $mergedContent = $existingJson | ConvertTo-Json -Depth 100
                        Set-Content -Path $Path -Value $mergedContent -NoNewline
                        Write-Host "$Label merged successfully: $Path"
                    }
                    catch {
                        Write-Warning "Failed to merge JSON content: $_"
                        Write-Host "Falling back to simple append."
                        Add-Content -Path $Path -Value "`n$Content"
                    }
                }
                else {
                    Add-Content -Path $Path -Value "`n$Content"
                }
                
                Write-Host "$Label configured: $Path"
                return
            }
            'Override' {
                Write-Host "Overriding existing $($Label): $Path"
            }
        }
    }

    Set-Content -Path $Path -Value $Content -NoNewline
    Write-Host "$Label configured: $Path"
}

function Install-OhMyPosh {
    Install-OhMyPoshDependencies

    $existing = Get-Command oh-my-posh -ErrorAction SilentlyContinue

    if ($existing -and -not $Force) {
        Write-Host "Oh My Posh already installed: $($existing.Source)"
        return
    }

    Write-Host 'Installing Oh My Posh...'

    if ($IsWindows) {
        winget install JanDeDobbeleer.OhMyPosh --source winget
    }
    else {
        curl -s https://ohmyposh.dev/install.sh | bash -s
    }
}

function Install-OhMyPoshDependencies {
    Write-Host 'Ensuring Oh My Posh dependencies are installed...'

    if ($IsWindows) {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            throw 'winget is required to install Oh My Posh on Windows but was not found.'
        }

        Write-Host 'Windows dependency checks complete.'
        return
    }

    $packageManagers = @(
        @{ Name = 'apt-get'; Install = 'sudo apt-get update && sudo apt-get install -y curl unzip ca-certificates fontconfig' }
        @{ Name = 'dnf'; Install = 'sudo dnf install -y curl unzip ca-certificates fontconfig' }
        @{ Name = 'yum'; Install = 'sudo yum install -y curl unzip ca-certificates fontconfig' }
        @{ Name = 'pacman'; Install = 'sudo pacman -Sy --noconfirm curl unzip ca-certificates fontconfig' }
        @{ Name = 'zypper'; Install = 'sudo zypper --non-interactive install curl unzip ca-certificates fontconfig' }
        @{ Name = 'apk'; Install = 'sudo apk add --no-cache curl unzip ca-certificates fontconfig' }
    )

    foreach ($manager in $packageManagers) {
        if (Get-Command $manager.Name -ErrorAction SilentlyContinue) {
            Write-Host "Installing dependencies with $($manager.Name)..."
            bash -lc $manager.Install
            Write-Host 'Dependency installation complete.'
            return
        }
    }

    throw 'No supported package manager found. Install curl, unzip, ca-certificates, and fontconfig manually.'
}

function Set-PowerShellProfile {

    if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
        throw 'Oh My Posh was not found after installation.'
    }

    $profilePath = $PROFILE.CurrentUserAllHosts
    $profileDir = Split-Path $profilePath

    New-Item -ItemType Directory -Path $profileDir -Force | Out-Null

    Write-Host "Downloading PowerShell profile from: $ProfileUrl"
    $profileContent = (Invoke-WebRequest -Uri $ProfileUrl).Content

    Set-ManagedFileContent -Path $profilePath -Content $profileContent -Label 'PowerShell profile' -OnExists $ExistingFileAction -SkipIfContains
}

function Set-GitConfig {
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Host 'Git not found. Skipping git config.'
        return
    }

    $gitConfigPath = Join-Path $HOME '.gitconfig'

    Write-Host "Downloading git config from: $GitConfigUrl"
    $gitConfigContent = (Invoke-WebRequest -Uri $GitConfigUrl).Content

    Set-ManagedFileContent -Path $gitConfigPath -Content $gitConfigContent -Label 'Git config' -OnExists $ExistingFileAction -SkipIfExactMatch
}

function Set-VSCodeSettings {
    $vscodeDir = Join-Path $PSScriptRoot '..' '.vscode'
    $settingsPath = Join-Path $vscodeDir 'settings.json'

    New-Item -ItemType Directory -Path $vscodeDir -Force | Out-Null

    Write-Host "Downloading VS Code settings from: $VSCodeSettingsUrl"
    $settingsContent = (Invoke-WebRequest -Uri $VSCodeSettingsUrl).Content

    Set-ManagedFileContent -Path $settingsPath -Content $settingsContent -Label 'VS Code settings' -OnExists $ExistingFileAction -SkipIfExactMatch
}


Write-Host "Existing file action: $ExistingFileAction"
Install-OhMyPosh
Set-PowerShellProfile
Set-GitConfig
Set-VSCodeSettings

npm install -g opencode-ai
npm install -g @fission-ai/openspec
npm install -g @neuralnomads/codenomad

if ($DevContainer) {
    Write-Host 'Devcontainer terminal setup complete.'
}
else {
    Write-Host 'Terminal setup complete.'
}
