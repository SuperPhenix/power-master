<#
.SYNOPSIS
    Ultimate-Win11-Setup.ps1 - Script de configuration "tout-en-un" pour un poste Windows 11 professionnel neuf.

.DESCRIPTION
    Script interactif (menu) OU automatisable (switchs en ligne de commande) qui couvre :

      1.  Pre-requis & securite d'execution (elevation, ExecutionPolicy, point de restauration, backup registre)
      2.  Debloat : suppression des applications pre-installees (Xbox, Solitaire, Teams perso, Cortana...)
      3.  Confidentialite / telemetrie : reduction maximale de la collecte de donnees
      4.  Windows Update : report des mises a jour, reboot controle, heures actives
      5.  Performances : plan d'alimentation, effets visuels, demarrage, Game Mode
      6.  Explorateur / Shell : extensions, fichiers caches, barre des taches (Win11), menu contextuel classique
      7.  Reseau : RDP, DNS, desactivation SMBv1, profils reseau, pare-feu
      8.  Securite : UAC, Defender (cloud + dossier controle), BitLocker, comptes, verrouillage
      9.  Outils pro : installation d'applications via Winget (VS Code, Git, 7-Zip, PowerToys, Chrome...)
      10. Developpement : WSL2, Hyper-V, Sandbox, mode developpeur, chemins longs, Terminal
      11. Maintenance : nettoyage, DISM/SFC, purge temp, tache planifiee hebdomadaire
      12. Rapport final + journal complet (transcript)

.NOTES
    - A executer depuis un PowerShell ELEVE (le script demande l'elevation tout seul).
    - Compatible Windows PowerShell 5.1 et PowerShell 7+.
    - Chaque section est idempotente : relancer le script ne casse rien.
    - Mode "DryRun" disponible pour previsualiser sans rien appliquer.

.EXAMPLE
    # Menu interactif
    .\Ultimate-Win11-Setup.ps1

.EXAMPLE
    # Tout appliquer sauf la suppression d'apps
    .\Ultimate-Win11-Setup.ps1 -All -SkipDebloat

.EXAMPLE
    # Previsualisation sans modification
    .\Ultimate-Win11-Setup.ps1 -All -DryRun

.EXAMPLE
    # Installer une liste d'applications specifique
    .\Ultimate-Win11-Setup.ps1 -RunApps -AppList "Git.Git","Microsoft.VisualStudioCode","7zip.7zip"
#>

[CmdletBinding()]
param(
    [switch]$All,
    [switch]$RunDebloat,
    [switch]$RunPrivacy,
    [switch]$RunUpdate,
    [switch]$RunPerformance,
    [switch]$RunShell,
    [switch]$RunNetwork,
    [switch]$RunSecurity,
    [switch]$RunApps,
    [switch]$RunDev,
    [switch]$RunMaintenance,
    [switch]$SkipDebloat,
    [switch]$SkipApps,
    [string[]]$AppList,
    [string]$DnsServers = "1.1.1.1,1.0.0.1",
    [string]$LogDir = "$env:ProgramData\UltimateWin11Setup\Logs",
    [switch]$DryRun,
    [switch]$NoRestorePoint,
    [switch]$NoRestartPrompt
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# ============================================================
#  CONSTANTES & ETAT GLOBAL
# ============================================================
$Script:AppliedActions = New-Object System.Collections.Generic.List[string]
$Script:SkippedActions = New-Object System.Collections.Generic.List[string]
$Script:FailedActions  = New-Object System.Collections.Generic.List[string]
$Script:IsDryRun       = [bool]$DryRun
$Script:BoundParams    = $PSBoundParameters
$Script:SourceUrls     = @(
    'https://raw.githubusercontent.com/SuperPhenix/power-master/main/Ultimate-Win11-Setup.ps1',
    'https://raw.githubusercontent.com/SuperPhenix/power-master/vibe/ultimate-win11-setup-488f29/Ultimate-Win11-Setup.ps1'
)
$Script:IsIexMode      = [string]::IsNullOrEmpty($PSCommandPath)

$Script:Title = @'
  _   _ _   _        _  _____ ___ _   _ _____ _     ___  _   _
 | | | | | | |      | |/ /_ _|_ _| \ | | ____| |   / _ \| \ | |
 | | | | |_| | _____| ' / | | | ||  \| |  _| | |  | | | |  \| |
 | |_| |  _  |_____| . \ | | | || |\  | |___| |__| |_| | |\  |
  \___/|_| |_|     |_|\_\___|___|_| \_|_____|_____\___/|_| \_|
            Windows 11 Pro Workstation Setup - Ultimate Edition
'@

# ============================================================
#  HELPERS
# ============================================================
function Write-Section {
    param([string]$Name)
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Cyan
    Write-Host ("  {0}" -f $Name) -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor Cyan
}

function Write-Step {
    param([string]$Message)
    Write-Host ("  [ ] {0}" -f $Message) -ForegroundColor White
}

function Write-Ok {
    param([string]$Message)
    Write-Host ("  [OK] {0}" -f $Message) -ForegroundColor Green
    $Script:AppliedActions.Add($Message) | Out-Null
}

function Write-Skip {
    param([string]$Message)
    Write-Host ("  [--] {0}" -f $Message) -ForegroundColor DarkGray
    $Script:SkippedActions.Add($Message) | Out-Null
}

function Write-Fail {
    param([string]$Message)
    Write-Host ("  [!!] {0}" -f $Message) -ForegroundColor Red
    $Script:FailedActions.Add($Message) | Out-Null
}

function Invoke-Logged {
    param(
        [scriptblock]$Action,
        [string]$Description
    )
    if ($Script:IsDryRun) {
        Write-Skip ("(DryRun) {0}" -f $Description)
        return
    }
    try {
        & $Action
        Write-Ok $Description
    }
    catch {
        Write-Fail ("{0} -> {1}" -f $Description, $_.Exception.Message)
    }
}

function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        [object]$Value,
        [string]$Type = 'DWord',
        [string]$Description
    )
    Invoke-Logged -Description $Description -Action {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        if ($Name -eq '(Default)') {
            Set-Item -Path $Path -Value $Value
        }
        else {
            New-ItemProperty -Path $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
        }
    }
}

function Test-IsAdmin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SelfCommand {
    foreach ($u in $Script:SourceUrls) {
        try {
            Invoke-WebRequest -Uri $u -Method Head -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop | Out-Null
            return $u
        }
        catch { }
    }
    return $Script:SourceUrls[0]
}

function Assert-Elevation {
    if (Test-IsAdmin) { return $true }
    Write-Host "Elevation administrateur requise. Relancement du script eleve..." -ForegroundColor Yellow
    if ($Script:IsIexMode) {
        $url = Get-SelfCommand
        Start-Process -FilePath 'powershell.exe' -Verb RunAs `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm '$url' | iex`""
    }
    else {
        $argPairs = @()
        foreach ($key in $Script:BoundParams.Keys) {
            $v = $Script:BoundParams[$key]
            if ($v -is [switch] -and $v.IsPresent) { $argPairs += "-$key" }
            elseif ($v -is [array]) { $argPairs += "-$key"; $argPairs += (($v | ForEach-Object { '"{0}"' -f $_ }) -join ',') }
            else { $argPairs += "-$key"; $argPairs += ('"{0}"' -f $v) }
        }
        $argString = $argPairs -join ' '
        Start-Process -FilePath 'powershell.exe' -Verb RunAs `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $argString"
    }
    return $false
}

function Initialize-Logging {
    if (-not (Test-Path $LogDir)) {
        New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
    }
    $stamp   = Get-Date -Format 'yyyyMMdd_HHmmss'
    $logFile = Join-Path $LogDir ("Setup_{0}.log" -f $stamp)
    Start-Transcript -Path $logFile -Append | Out-Null
    Write-Host "Journal : $logFile" -ForegroundColor DarkGray
    return $logFile
}

function New-SafetyNet {
    if ($NoRestorePoint) { Write-Skip "Point de restauration (desactive par parametre)"; return }

    Invoke-Logged -Description "Creation d'un point de restauration systeme 'UltimateWin11Setup'" -Action {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "UltimateWin11Setup" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
    }
}

function Backup-RegistryKeys {
    if ($Script:IsDryRun) { Write-Skip "(DryRun) Backup registre"; return }
    Invoke-Logged -Description "Sauvegarde des clefs de registre sensibles" -Action {
        $backupDir = "$env:ProgramData\UltimateWin11Setup\RegistryBackup"
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
        $keys = @(
            'HKLM\SOFTWARE\Policies\Microsoft\Windows',
            'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies',
            'HKLM\SOFTWARE\Policies\Microsoft\WindowsStore',
            'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
        )
        foreach ($k in $keys) {
            $file = Join-Path $backupDir (($k -replace '[\\:]', '_') + '.reg')
            & reg.exe export $k $file /y 2>$null | Out-Null
        }
    }
}

# ============================================================
#  1. DEBLOAT
# ============================================================
function Invoke-Debloat {
    Write-Section "1. DEBLOAT - Suppression des applications pre-installees"

    $bloatPatterns = @(
        "Microsoft.549981C3F5F10"
        "Microsoft.BingNews"
        "Microsoft.BingWeather"
        "Microsoft.BingFinance"
        "Microsoft.BingSports"
        "Microsoft.BingSearch"
        "Microsoft.GamingApp"
        "Microsoft.GetHelp"
        "Microsoft.Getstarted"
        "Microsoft.Messaging"
        "Microsoft.Microsoft3DViewer"
        "Microsoft.MicrosoftOfficeHub"
        "Microsoft.MicrosoftSolitaireCollection"
        "Microsoft.MicrosoftStickyNotes"
        "Microsoft.MixedReality.Portal"
        "Microsoft.News"
        "Microsoft.Office.OneNote"
        "Microsoft.OneConnect"
        "Microsoft.People"
        "Microsoft.Print3D"
        "Microsoft.SkypeApp"
        "Microsoft.Todos"
        "Microsoft.Wallet"
        "Microsoft.Whiteboard"
        "Microsoft.WindowsFeedbackHub"
        "Microsoft.WindowsMaps"
        "Microsoft.WindowsSoundRecorder"
        "Microsoft.YourPhone"
        "Microsoft.ZuneMusic"
        "Microsoft.ZuneVideo"
        "MicrosoftTeams"
        "Clipchamp.Clipchamp"
        "Disney.37853FC22B2CE"
        "SpotifyAB.SpotifyMusic"
        "king.com.*"
        "CandyCrush*"
        "Facebook*"
        "Twitter*"
        "Instagram*"
        "TikTok*"
        "Netflix*"
        "AdobeSystemsIncorporated.AdobePhotoshopExpress"
        "DolbyLaboratories.DolbyAccess"
        "MicrosoftCorporationII.MicrosoftFamily"
        "MicrosoftCorporationII.QuickAssist"
        "Minecraft*"
    )

    if ($Script:IsDryRun) {
        Write-Skip ("(DryRun) Suppression de {0} familles d'applications bloatware" -f $bloatPatterns.Count)
    }
    else {
        $removedCount = 0
        foreach ($pattern in $bloatPatterns) {
            $packages = Get-AppxPackage -AllUsers -Name $pattern -ErrorAction SilentlyContinue
            foreach ($pkg in $packages) {
                try {
                    Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                    $removedCount++
                    Write-Ok ("App supprimee : {0}" -f $pkg.Name)
                }
                catch {
                    Write-Fail ("Suppression {0} -> {1}" -f $pkg.Name, $_.Exception.Message)
                }
            }
            $provisioned = Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -like $pattern }
            foreach ($prov in $provisioned) {
                try {
                    Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
                    $removedCount++
                    Write-Ok ("App provisionnee supprimee (nouveaux comptes) : {0}" -f $prov.DisplayName)
                }
                catch {
                    Write-Fail ("Suppression provisionnee {0} -> {1}" -f $prov.DisplayName, $_.Exception.Message)
                }
            }
        }
        if ($removedCount -eq 0) {
            Write-Skip "Aucune application bloatware a supprimer (deja propre)"
        }
    }

    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent' -Name 'DisableWindowsConsumerFeatures' -Value 1 `
        -Description "Desactivation des experiences grand public (apps suggerees auto-installees)"
    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'ContentDeliveryAllowed' -Value 0 `
        -Description "Desactivation du Content Delivery Manager"
    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'OemPreInstalledAppsEnabled' -Value 0 `
        -Description "Desactivation des apps OEM pre-installees"
    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'PreInstalledAppsEnabled' -Value 0 `
        -Description "Desactivation des apps pre-installees"
    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SilentInstalledAppsEnabled' -Value 0 `
        -Description "Desactivation de l'installation silencieuse d'apps"
    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SubscribedContent-338388Enabled' -Value 0 `
        -Description "Desactivation des suggestions de l'ecran de verrouillage"
    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' -Name 'SubscribedContent-338389Enabled' -Value 0 `
        -Description "Desactivation des apps suggerees dans les parametres"
}

# ============================================================
#  2. CONFIDENTIALITE / TELEMETRIE
# ============================================================
function Invoke-Privacy {
    Write-Section "2. CONFIDENTIALITE - Telemetrie, publicite, suivi"

    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -Value 0 `
        -Description "Telemetrie Windows reduite au minimum"
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection' -Name 'AllowTelemetry' -Value 0 `
        -Description "Telemetrie (cle secondaire)"
    Invoke-Logged -Description "Arret et desactivation du service DiagTrack (telemetrie)" -Action {
        Stop-Service -Name 'DiagTrack' -Force -ErrorAction SilentlyContinue
        Set-Service -Name 'DiagTrack' -StartupType Disabled
    }
    Invoke-Logged -Description "Arret et desactivation du service dmwappushservice" -Action {
        Stop-Service -Name 'dmwappushservice' -Force -ErrorAction SilentlyContinue
        Set-Service -Name 'dmwappushservice' -StartupType Disabled -ErrorAction SilentlyContinue
    }

    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' -Name 'Enabled' -Value 0 `
        -Description "Desactivation de l'ID publicitaire"
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo' -Name 'DisabledByGroupPolicy' -Value 1 `
        -Description "ID publicitaire bloque par strategie"

    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy' -Name 'TailoredExperiencesWithDiagnosticDataEnabled' -Value 0 `
        -Description "Desactivation des experiences personnalisees"
    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement' -Name 'ScoobeSystemSettingEnabled' -Value 0 `
        -Description "Desactivation des suggestions 'Finir la configuration'"
    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Start_IrisRecommendations' -Value 0 `
        -Description "Desactivation des recommandations dans le menu Demarrer"

    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'EnableActivityFeed' -Value 0 `
        -Description "Desactivation de la chronologie / historique d'activite"
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'PublishUserActivities' -Value 0 `
        -Description "Non-publication de l'activite utilisateur vers Microsoft"
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'UploadUserActivities' -Value 0 `
        -Description "Non-upload de l'activite utilisateur"

    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors' -Name 'DisableLocation' -Value 1 `
        -Description "Desactivation de la localisation"
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' -Name 'LetAppsAccessLocation' -Value 2 `
        -Description "Refus de l'acces a la localisation pour les applications"

    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization' -Name 'RestrictImplicitInkCollection' -Value 1 `
        -Description "Desactivation de la reconnaissance manuscrite automatique"
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\InputPersonalization' -Name 'RestrictImplicitTextCollection' -Value 1 `
        -Description "Desactivation de la collecte de texte automatique"
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Name 'AllowCortana' -Value 0 `
        -Description "Desactivation de Cortana"
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -Name 'ConnectedSearchUseWeb' -Value 0 `
        -Description "Recherche du menu Demarrer : pas de resultat web Bing"
    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'BingSearchEnabled' -Value 0 `
        -Description "Bing desactive dans la recherche"
    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'CortanaConsent' -Value 0 `
        -Description "Consentement Cortana retire"

    Set-RegistryValue -Path 'HKLM:\Software\Microsoft\PolicyManager\default\WiFi\AllowWiFiHotSpotReporting' -Name 'Value' -Value 0 `
        -Description "Desactivation du rapport de hotspots Wi-Fi"
    Set-RegistryValue -Path 'HKLM:\Software\Microsoft\PolicyManager\default\WiFi\AllowAutoConnectToWiFiSenseHotspots' -Name 'Value' -Value 0 `
        -Description "Desactivation de la connexion auto aux hotspots Wi-Fi Sense"

    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Siuf\Rules' -Name 'NumberOfSIUFInPeriod' -Value 0 `
        -Description "Desactivation des demandes de feedback Windows"
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' -Name 'AITEnable' -Value 0 `
        -Description "Desactivation de l'Application Impact Telemetry"
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppCompat' -Name 'DisableUAR' -Value 1 `
        -Description "Desactivation de l'enregistreur d'etapes (Steps Recorder)"

    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'NoAutorun' -Value 1 `
        -Description "Desactivation de l'Autorun pour les medias amovibles"
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers' -Name 'DisableAutoplay' -Value 1 `
        -Description "Desactivation de la lecture automatique"
}

# ============================================================
#  3. WINDOWS UPDATE
# ============================================================
function Invoke-WindowsUpdate {
    Write-Section "3. WINDOWS UPDATE - Controle des mises a jour et des redemarrages"

    $wu = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    Set-RegistryValue -Path $wu -Name 'NoAutoRebootWithLoggedOnUsers' -Value 1 `
        -Description "Pas de redemarrage automatique quand un utilisateur est connecte"
    Set-RegistryValue -Path $wu -Name 'AUOptions' -Value 3 `
        -Description "Mises a jour : telechargement auto, installation manuelle"

    $wuRoot = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    Set-RegistryValue -Path $wuRoot -Name 'DeferFeatureUpdates' -Value 1 `
        -Description "Report des mises a jour de fonctionnalites"
    Set-RegistryValue -Path $wuRoot -Name 'DeferFeatureUpdatesPeriodInDays' -Value 60 `
        -Description "Report des feature updates : 60 jours"
    Set-RegistryValue -Path $wuRoot -Name 'DeferQualityUpdates' -Value 1 `
        -Description "Report des mises a jour de qualite (correctifs)"
    Set-RegistryValue -Path $wuRoot -Name 'DeferQualityUpdatesPeriodInDays' -Value 7 `
        -Description "Delai de report des quality updates : 7 jours"
    Set-RegistryValue -Path $wuRoot -Name 'SetActiveHours' -Value 1 `
        -Description "Definition des heures actives (8h - 20h)"
    Set-RegistryValue -Path $wuRoot -Name 'ActiveHoursStart' -Value 8 `
        -Description "Debut des heures actives"
    Set-RegistryValue -Path $wuRoot -Name 'ActiveHoursEnd' -Value 20 `
        -Description "Fin des heures actives"
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config' -Name 'DODownloadMode' -Value 0 `
        -Description "Desactivation du Delivery Optimization (partage P2P des mises a jour)"

    Invoke-Logged -Description "Lancement d'une detection Windows Update" -Action {
        & "$env:SystemRoot\System32\UsoClient.exe" StartScan 2>$null
    }
}

# ============================================================
#  4. PERFORMANCES
# ============================================================
function Invoke-Performance {
    Write-Section "4. PERFORMANCE - Alimentation, effets visuels, reactivite"

    Invoke-Logged -Description "Activation du plan d'alimentation 'Performances elevees'" -Action {
        $highPerf = & powercfg.exe /list 2>$null | Select-String 'High performance|Performances elevees'
        if ($highPerf) {
            $guid = ($highPerf.ToString() -split '\s+') | Where-Object { $_ -match '^[0-9a-fA-F-]{36}$' } | Select-Object -First 1
            if ($guid) { & powercfg.exe /setactive $guid }
        }
        else {
            & powercfg.exe /duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
            & powercfg.exe /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c 2>$null
        }
    }
    Invoke-Logged -Description "Desactivation de l'hibernation (libere hiberfil.sys)" -Action {
        & powercfg.exe /hibernate off 2>$null
    }

    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' -Name 'VisualFXSetting' -Value 2 `
        -Description "Effets visuels regles sur 'performances'"
    Set-RegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'MenuShowDelay' -Value 0 `
        -Description "Delai d'affichage des menus reduit a 0 ms"
    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' -Name 'StartupDelayInMSec' -Value 0 `
        -Description "Suppression du delai artificiel de demarrage des applications"

    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AllowAutoGameMode' -Value 1 `
        -Description "Activation du Game Mode"
    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\GameBar' -Name 'AutoGameModeEnabled' -Value 1 `
        -Description "Game Mode automatique active"

    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl' -Name 'Win32PrioritySeparation' -Value 38 `
        -Description "Optimisation de la repartition CPU (programmes au premier plan)"

    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'NetworkThrottlingIndex' -Value 0xFFFFFFFF -Type QWord `
        -Description "Suppression de la limitation reseau multimedia"
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile' -Name 'SystemResponsiveness' -Value 10 `
        -Description "Reserve CPU multimedia reduite a 10%"
}

# ============================================================
#  5. EXPLORATEUR / SHELL
# ============================================================
function Invoke-Shell {
    Write-Section "5. EXPLORATEUR & SHELL - Confort d'utilisation professionnel"

    $adv = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-RegistryValue -Path $adv -Name 'HideFileExt' -Value 0 `
        -Description "Affichage des extensions de fichiers"
    Set-RegistryValue -Path $adv -Name 'Hidden' -Value 1 `
        -Description "Affichage des fichiers et dossiers caches"
    Set-RegistryValue -Path $adv -Name 'ShowSuperHidden' -Value 0 `
        -Description "Masquage des fichiers systeme proteges (securite)"
    Set-RegistryValue -Path $adv -Name 'LaunchTo' -Value 1 `
        -Description "Explorateur ouvert sur 'Ce PC' par defaut"
    Set-RegistryValue -Path $adv -Name 'TaskbarAl' -Value 0 `
        -Description "Barre des taches alignee a gauche"
    Set-RegistryValue -Path $adv -Name 'TaskbarDa' -Value 0 `
        -Description "Suppression du bouton Widgets de la barre des taches"
    Set-RegistryValue -Path $adv -Name 'TaskbarMn' -Value 0 `
        -Description "Suppression du bouton Chat (Teams perso) de la barre des taches"
    Set-RegistryValue -Path $adv -Name 'ShowCopilotButton' -Value 0 `
        -Description "Suppression du bouton Copilot de la barre des taches"
    Set-RegistryValue -Path $adv -Name 'Start_ShowRecentDocs' -Value 0 `
        -Description "Pas de documents recents dans le Demarrer (confidentialite)"
    Set-RegistryValue -Path $adv -Name 'Start_TrackDocs' -Value 0 `
        -Description "Arret du suivi des documents ouverts"
    Set-RegistryValue -Path $adv -Name 'DontUsePowerShellOnWinX' -Value 0 `
        -Description "Menu Win+X : PowerShell au lieu de l'invite de commandes"
    Set-RegistryValue -Path $adv -Name 'UseCompactMode' -Value 1 `
        -Description "Mode compact de l'Explorateur (plus de densite)"
    Set-RegistryValue -Path $adv -Name 'ShowTaskViewButton' -Value 0 `
        -Description "Suppression du bouton Affichage des taches"

    Set-RegistryValue -Path 'HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32' -Name '(Default)' -Value '' -Type String `
        -Description "Restauration du menu contextuel classique (style Windows 10)"

    Set-RegistryValue -Path $adv -Name 'SnapAssist' -Value 0 `
        -Description "Desactivation des suggestions Snap Assist"
    Set-RegistryValue -Path 'HKCU:\Control Panel\Desktop' -Name 'WindowArrangementActive' -Value 0 `
        -Description "Desactivation de l'arrangement auto des fenetres en bord d'ecran"

    Set-RegistryValue -Path $adv -Name 'Start_AccountNotifications' -Value 0 `
        -Description "Desactivation des notifications de compte Microsoft dans le Demarrer"
    Set-RegistryValue -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' -Name 'ConfirmFileDelete' -Value 0 `
        -Description "Suppression sans boite de confirmation (Corbeille)"

    if (-not $Script:IsDryRun) {
        Invoke-Logged -Description "Redemarrage de l'Explorateur Windows (application visuelle immediate)" -Action {
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-Skip "(DryRun) Redemarrage de l'Explorateur"
    }
}

# ============================================================
#  6. RESEAU
# ============================================================
function Invoke-Network {
    Write-Section "6. RESEAU - RDP, DNS, protocoles, pare-feu"

    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0 `
        -Description "Activation du Bureau a distance (RDP)"
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Value 1 `
        -Description "RDP avec authentification NLA (securise)"
    Invoke-Logged -Description "Regles de pare-feu pour le Bureau a distance" -Action {
        Enable-NetFirewallRule -DisplayGroup 'Bureau a distance' -ErrorAction SilentlyContinue
        Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
    }

    Invoke-Logged -Description ("Configuration des DNS sur toutes les cartes actives : {0}" -f $DnsServers) -Action {
        $dns = $DnsServers -split ','
        Get-NetAdapter | Where-Object Status -eq 'Up' | ForEach-Object {
            Set-DnsClientServerAddress -InterfaceIndex $_.ifIndex -ServerAddresses $dns -ErrorAction Stop
        }
    }

    Invoke-Logged -Description "Passage des cartes reseau filaires en profil Prive" -Action {
        Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -eq 'Public' -and $_.InterfaceAlias -notmatch 'Wi-Fi' } |
            Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue
    }

    Invoke-Logged -Description "Desactivation de SMBv1 (vulnerabilites WannaCry/NotPetya)" -Action {
        Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue
        Set-SmbServerConfiguration -EnableSMB1Protocol $false -Confirm:$false -ErrorAction SilentlyContinue
    }
    Invoke-Logged -Description "Activation du chiffrement et de la signature SMB" -Action {
        Set-SmbServerConfiguration -EncryptData $true -Confirm:$false -ErrorAction SilentlyContinue
        Set-SmbServerConfiguration -RequireSecuritySignature $true -Confirm:$false -ErrorAction SilentlyContinue
    }

    Invoke-Logged -Description "Activation du pare-feu Windows sur les 3 profils" -Action {
        Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
    }
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' -Name 'EnableMulticast' -Value 0 `
        -Description "Desactivation du multicast LLMNR (anti-pillage d'identifiants)"

    Invoke-Logged -Description "Desactivation de NetBIOS sur TCP/IP" -Action {
        $adapters = Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True"
        foreach ($adapter in $adapters) {
            Invoke-CimMethod -InputObject $adapter -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = 2 } -ErrorAction SilentlyContinue | Out-Null
        }
    }

    Invoke-Logged -Description "Purge du cache DNS" -Action {
        Clear-DnsClientCache -ErrorAction SilentlyContinue
    }
}

# ============================================================
#  7. SECURITE
# ============================================================
function Invoke-Security {
    Write-Section "7. SECURITE - UAC, Defender, BitLocker, comptes"

    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'ConsentPromptBehaviorAdmin' -Value 5 `
        -Description "UAC : elevation avec consentement sur bureau securise"
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'ConsentPromptBehaviorUser' -Value 3 `
        -Description "UAC : utilisateur standard -> demande d'identifiants admin"
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'PromptOnSecureDesktop' -Value 1 `
        -Description "UAC : bascule sur bureau securise pour les elevations"

    Invoke-Logged -Description "Activation de la protection cloud Defender (niveau eleve)" -Action {
        Set-MpPreference -MAPSReporting Advanced -ErrorAction Stop
        Set-MpPreference -SubmitSamplesConsent 1 -ErrorAction SilentlyContinue
    }
    Invoke-Logged -Description "Activation de la protection contre les PUA" -Action {
        Set-MpPreference -PUAProtection Enabled -ErrorAction SilentlyContinue
    }
    Invoke-Logged -Description "Activation de la protection reseau" -Action {
        Set-MpPreference -EnableNetworkProtection Enabled -ErrorAction SilentlyContinue
    }
    Invoke-Logged -Description "Activation du controle des dossiers proteges (anti-ransomware)" -Action {
        Set-MpPreference -EnableControlledFolderAccess Enabled -ErrorAction SilentlyContinue
        Add-MpPreference -ControlledFolderAccessProtectedFolders "$env:USERPROFILE\Documents","$env:USERPROFILE\Pictures" -ErrorAction SilentlyContinue
    }
    Invoke-Logged -Description "Planification d'une analyse rapide Defender quotidienne (02h00)" -Action {
        Set-MpPreference -ScanScheduleQuickScanTime 120 -ErrorAction SilentlyContinue
    }

    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -Name 'SmartScreenEnabled' -Value 'RequireAdmin' -Type String `
        -Description "SmartScreen actif pour les executables"

    Invoke-Logged -Description "Verification de l'etat BitLocker" -Action {
        $bitlocker = Get-BitLockerVolume -ErrorAction SilentlyContinue | Where-Object { $_.MountPoint -eq "$env:SystemDrive\" }
        if ($bitlocker -and $bitlocker.ProtectionStatus -eq 'Off') {
            Write-Host "       -> BitLocker desactive sur $env:SystemDrive\ (pensez a l'activer + sauvegarder la clef)" -ForegroundColor Yellow
        }
        elseif ($bitlocker) {
            Write-Host "       -> BitLocker actif sur $env:SystemDrive\" -ForegroundColor Green
        }
    }

    Invoke-Logged -Description "Desactivation du compte Invite" -Action {
        Disable-LocalUser -Name 'Guest' -ErrorAction SilentlyContinue
    }
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'dontdisplaylastusername' -Value 1 `
        -Description "Ecran de connexion : pas d'affichage du dernier utilisateur"
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'InactivityTimeoutSecs' -Value 900 `
        -Description "Verrouillage automatique de la session apres 15 min d'inactivite"
    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name 'ShutdownWithoutLogon' -Value 0 `
        -Description "Pas de bouton Arreter sur l'ecran de connexion"

    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'ProtectionMode' -Value 1 `
        -Description "Activation du mode protege du noyau"
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'RestrictAnonymous' -Value 1 `
        -Description "Restriction des sessions anonymes (SMB/LSA)"
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -Name 'LmCompatibilityLevel' -Value 5 `
        -Description "Authentification NTLMv2 uniquement (refus LM/NTLMv1)"
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' -Name 'UseLogonCredential' -Value 0 `
        -Description "WDigest : identifiants non stockes en clair en memoire (anti-Mimikatz)"
}

# ============================================================
#  8. APPLICATIONS PRO (WINGET)
# ============================================================
$DefaultAppList = @(
    @{ Id = 'Microsoft.PowerToys';                 Name = 'PowerToys' }
    @{ Id = 'Microsoft.WindowsTerminal';           Name = 'Windows Terminal' }
    @{ Id = 'Microsoft.VisualStudioCode';          Name = 'Visual Studio Code' }
    @{ Id = 'Git.Git';                             Name = 'Git' }
    @{ Id = '7zip.7zip';                           Name = '7-Zip' }
    @{ Id = 'Notepad++.Notepad++';                 Name = 'Notepad++' }
    @{ Id = 'Google.Chrome';                       Name = 'Google Chrome' }
    @{ Id = 'Mozilla.Firefox';                     Name = 'Mozilla Firefox' }
    @{ Id = 'VideoLAN.VLC';                        Name = 'VLC Media Player' }
    @{ Id = 'Adobe.Acrobat.Reader.64-bit';         Name = 'Adobe Acrobat Reader' }
    @{ Id = 'Zoom.Zoom';                           Name = 'Zoom' }
    @{ Id = 'Microsoft.Teams';                     Name = 'Microsoft Teams (pro)' }
    @{ Id = 'TheDocumentFoundation.LibreOffice';   Name = 'LibreOffice' }
    @{ Id = 'SumatraPDF.SumatraPDF';               Name = 'Sumatra PDF' }
    @{ Id = 'Greenshot.Greenshot';                 Name = 'Greenshot (captures)' }
    @{ Id = 'Bitwarden.Bitwarden';                 Name = 'Bitwarden (gestionnaire de mdp)' }
    @{ Id = 'WiresharkFoundation.Wireshark';       Name = 'Wireshark' }
    @{ Id = 'Python.Python.3.12';                  Name = 'Python 3.12' }
    @{ Id = 'OpenVPNTechnologies.OpenVPNConnect';  Name = 'OpenVPN Connect' }
)

function Invoke-Apps {
    Write-Section "8. APPLICATIONS - Installation via Winget"

    Invoke-Logged -Description "Verification de Winget" -Action {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            throw "Winget introuvable. Installez 'App Installer' depuis le Microsoft Store puis relancez."
        }
    }

    if ($Script:IsDryRun) { Write-Skip "(DryRun) Installation des applications"; return }

    $apps = @()
    if ($AppList) {
        foreach ($id in $AppList) { $apps += @{ Id = $id; Name = $id } }
    }
    else {
        $apps = $DefaultAppList
    }

    foreach ($app in $apps) {
        Write-Step ("Installation de {0}..." -f $app.Name)
        try {
            & winget install --id $app.Id --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>$null
            if ($LASTEXITCODE -eq 0) { Write-Ok ("Installe : {0}" -f $app.Name) }
            elseif ($LASTEXITCODE -eq -1978335189) { Write-Skip ("Deja installe : {0}" -f $app.Name) }
            else { Write-Fail ("Echec d'installation : {0} (code {1})" -f $app.Name, $LASTEXITCODE) }
        }
        catch {
            Write-Fail ("Echec d'installation : {0} -> {1}" -f $app.Name, $_.Exception.Message)
        }
    }

    Invoke-Logged -Description "Mise a jour de toutes les applications Winget" -Action {
        & winget upgrade --all --silent --accept-package-agreements --accept-source-agreements 2>$null
    }
}

# ============================================================
#  9. DEVELOPPEMENT
# ============================================================
function Invoke-Dev {
    Write-Section "9. DEVELOPPEMENT - WSL2, Hyper-V, Sandbox, outils"

    $features = @(
        @{ Name = 'Microsoft-Windows-Subsystem-Linux';       Desc = 'Sous-systeme Windows pour Linux' }
        @{ Name = 'VirtualMachinePlatform';                  Desc = 'Plateforme de machine virtuelle' }
        @{ Name = 'Microsoft-Hyper-V-All';                   Desc = 'Hyper-V complet' }
        @{ Name = 'Containers';                              Desc = 'Conteneurs Windows' }
        @{ Name = 'Microsoft-Hyper-V-Management-PowerShell'; Desc = 'Cmdlets PowerShell Hyper-V' }
        @{ Name = 'Windows-Sandbox';                         Desc = 'Windows Sandbox' }
        @{ Name = 'NetFx3';                                  Desc = '.NET Framework 3.5' }
        @{ Name = 'TelnetClient';                            Desc = 'Client Telnet' }
    )
    foreach ($f in $features) {
        $state = (Get-WindowsOptionalFeature -Online -FeatureName $f.Name -ErrorAction SilentlyContinue).State
        if ($state -eq 'Enabled') {
            Write-Skip ("Deja active : {0}" -f $f.Desc)
        }
        else {
            Invoke-Logged -Description ("Activation de la fonctionnalite Windows : {0}" -f $f.Desc) -Action {
                Enable-WindowsOptionalFeature -Online -FeatureName $f.Name -All -NoRestart -ErrorAction Stop | Out-Null
            }
        }
    }

    Set-RegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name 'AllowDevelopmentWithoutDevLicense' -Value 1 `
        -Description "Activation du Mode Developpeur"
    Set-RegistryValue -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -Value 1 `
        -Description "Activation des chemins de plus de 260 caracteres"

    Invoke-Logged -Description "Configuration de WSL en version 2 par defaut" -Action {
        & wsl.exe --set-default-version 2 2>$null
    }
    Invoke-Logged -Description "Mise a jour du noyau WSL" -Action {
        & wsl.exe --update 2>$null
    }
    Invoke-Logged -Description "Installation de la distribution Ubuntu (WSL)" -Action {
        $distros = & wsl.exe --list --quiet 2>$null
        if (-not $distros) {
            & wsl.exe --install -d Ubuntu --no-launch 2>$null
        }
    }

    Invoke-Logged -Description "Configuration globale Git (longpaths, autocrlf, main)" -Action {
        $git = Get-Command git -ErrorAction SilentlyContinue
        if ($git) {
            & git config --global core.longpaths true
            & git config --global core.autocrlf input
            & git config --global init.defaultBranch main
        }
        else {
            Write-Host "       -> Git pas encore disponible, configuration reportee" -ForegroundColor Yellow
        }
    }

    Invoke-Logged -Description "Installation de Chocolatey (gestionnaire de paquets)" -Action {
        if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
            Set-ExecutionPolicy Bypass -Scope Process -Force
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
            & ([ScriptBlock]::Create((Invoke-WebRequest 'https://community.chocolatey.org/install.ps1' -UseBasicParsing).Content))
        }
    }
}

# ============================================================
#  10. MAINTENANCE
# ============================================================
function Invoke-Maintenance {
    Write-Section "10. MAINTENANCE - Nettoyage, sante systeme, tache planifiee"

    Invoke-Logged -Description "Purge des fichiers temporaires utilisateur et systeme" -Action {
        Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$env:SystemRoot\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$env:LOCALAPPDATA\Microsoft\Windows\INetCache\*" -Recurse -Force -ErrorAction SilentlyContinue
    }
    Invoke-Logged -Description "Purge de la Corbeille" -Action {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    }
    Invoke-Logged -Description "Reparation du composant store (DISM RestoreHealth)" -Action {
        & dism.exe /Online /Cleanup-Image /RestoreHealth 2>$null
    }
    Invoke-Logged -Description "Verification des fichiers systeme (SFC)" -Action {
        & sfc.exe /scannow 2>$null
    }
    Invoke-Logged -Description "Nettoyage de disque (Cleanmgr silencieux)" -Action {
        & cleanmgr.exe /sagerun:1 2>$null
    }

    Invoke-Logged -Description "Creation d'une tache planifiee de maintenance hebdomadaire (dimanche 03h00)" -Action {
        $url = Get-SelfCommand
        $dl  = 'irm ''' + $url + ''' -OutFile $env:TEMP\UltimateWin11Setup.ps1'
        $run = '& $env:TEMP\UltimateWin11Setup.ps1 -RunMaintenance -NoRestorePoint -NoRestartPrompt'
        $arg = '-NoProfile -ExecutionPolicy Bypass -Command "' + $dl + '; ' + $run + '"'
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
        $trigger    = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 03:00
        $settings   = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries
        $principal  = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName 'UltimateWin11Setup-WeeklyMaintenance' `
            -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force -ErrorAction Stop | Out-Null
    }

    Invoke-Logged -Description "Actualisation des strategies de groupe" -Action {
        & gpupdate.exe /force 2>$null
    }
}

# ============================================================
#  MENU INTERACTIF
# ============================================================
function Show-Menu {
    Clear-Host
    Write-Host $Script:Title -ForegroundColor Cyan

    if ($Script:IsDryRun) {
        Write-Host "  MODE ACTUEL : DRYRUN - previsualisation, aucune modification ne sera appliquee" -ForegroundColor Yellow
    }
    else {
        Write-Host "  MODE ACTUEL : NORMAL - les modifications seront appliquees" -ForegroundColor Green
    }

    $line = "  " + ("-" * 66)

    Write-Host ""
    Write-Host $line
    Write-Host "   SECTIONS A LA CARTE" -ForegroundColor Cyan
    Write-Host $line
    Write-Host "   [1]  Debloat           Xbox, Solitaire, Teams perso, Cortana... dehors"
    Write-Host "   [2]  Confidentialite   Telemetrie, pub, suivi : tout au minimum"
    Write-Host "   [3]  Windows Update    Report 60j, pas de reboot force, heures actives"
    Write-Host "   [4]  Performance       Hautes perfs, hibernation off, menus instantanes"
    Write-Host "   [5]  Shell             Taskbar a gauche, Widgets/Copilot off, menu Win10"
    Write-Host "   [6]  Reseau            RDP, DNS, SMBv1 off, pare-feu, LLMNR/NetBIOS off"
    Write-Host "   [7]  Securite          UAC, Defender, BitLocker, NTLMv2, verrouillage"
    Write-Host "   [8]  Applications      19 outils pro via Winget (VS Code, Git, 7-Zip...)"
    Write-Host "   [9]  Developpement     WSL2, Hyper-V, Sandbox, mode dev, Chocolatey"
    Write-Host "   [10] Maintenance       Purge, DISM/SFC, tache planifiee hebdomadaire"

    Write-Host ""
    Write-Host $line
    Write-Host "   ACTIONS RAPIDES" -ForegroundColor Cyan
    Write-Host $line
    Write-Host "   [A]  TOUT appliquer (recommande pour un poste neuf)" -ForegroundColor White
    Write-Host "   [D]  Previsualiser TOUT sans rien modifier (DryRun)"
    Write-Host "   [P]  Basculer le mode DryRun (previsualisation on/off)"
    Write-Host "   [Q]  Quitter"
    Write-Host ""
    $choice = Read-Host "  Votre choix"
    return $choice
}

function Invoke-All {
    Invoke-Debloat
    Invoke-Privacy
    Invoke-WindowsUpdate
    Invoke-Performance
    Invoke-Shell
    Invoke-Network
    Invoke-Security
    Invoke-Apps
    Invoke-Dev
    Invoke-Maintenance
}

# ============================================================
#  RAPPORT FINAL
# ============================================================
function Show-Summary {
    param([switch]$Section)

    if ($Section) {
        Write-Section "SECTION TERMINEE"
    }
    else {
        Write-Section "RAPPORT FINAL"
    }
    Write-Host ("  Appliquees : {0}" -f $Script:AppliedActions.Count) -ForegroundColor Green
    Write-Host ("  Ignorees   : {0}" -f $Script:SkippedActions.Count) -ForegroundColor DarkGray
    Write-Host ("  Echecs     : {0}" -f $Script:FailedActions.Count) -ForegroundColor Red

    if ($Script:FailedActions.Count -gt 0) {
        Write-Host ""
        Write-Host "  Echecs detailles :" -ForegroundColor Red
        foreach ($f in $Script:FailedActions) {
            Write-Host ("    - {0}" -f $f) -ForegroundColor Red
        }
    }

    Write-Host ""
    Write-Host ("  Journal complet : {0}" -f $Script:LogFile) -ForegroundColor Cyan
    Write-Host ""

    if ($Section) {
        Read-Host "  Appuyez sur Entree pour revenir au menu"
        return
    }

    if (-not $NoRestartPrompt -and -not $Script:IsDryRun) {
        $restart = Read-Host "Un redemarrage est recommande. Redemarrer maintenant ? (o/N)"
        if ($restart -match '^[oOyY]') {
            Restart-Computer -Force
        }
    }
}

# ============================================================
#  MAIN
# ============================================================
function Main {
    Clear-Host
    Write-Host $Script:Title -ForegroundColor Cyan
    Write-Host ""

    if ($Script:IsDryRun) {
        Write-Host "  *** MODE DRYRUN : aucune modification ne sera appliquee ***" -ForegroundColor Yellow
        Write-Host ""
    }

    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Host "PowerShell 5.1 minimum requis." -ForegroundColor Red
        return
    }

    if (-not (Assert-Elevation)) { return }
    $Script:LogFile = Initialize-Logging
    New-SafetyNet
    Backup-RegistryKeys

    if ($All) {
        if (-not $SkipDebloat) { Invoke-Debloat }
        Invoke-Privacy
        Invoke-WindowsUpdate
        Invoke-Performance
        Invoke-Shell
        Invoke-Network
        Invoke-Security
        if (-not $SkipApps) { Invoke-Apps }
        Invoke-Dev
        Invoke-Maintenance
    }
    elseif ($RunDebloat -or $RunPrivacy -or $RunUpdate -or $RunPerformance -or $RunShell -or `
            $RunNetwork -or $RunSecurity -or $RunApps -or $RunDev -or $RunMaintenance) {
        if ($RunDebloat)      { Invoke-Debloat }
        if ($RunPrivacy)      { Invoke-Privacy }
        if ($RunUpdate)       { Invoke-WindowsUpdate }
        if ($RunPerformance)  { Invoke-Performance }
        if ($RunShell)        { Invoke-Shell }
        if ($RunNetwork)      { Invoke-Network }
        if ($RunSecurity)     { Invoke-Security }
        if ($RunApps)         { Invoke-Apps }
        if ($RunDev)          { Invoke-Dev }
        if ($RunMaintenance)  { Invoke-Maintenance }
    }
    else {
        while ($true) {
            $choice = (Show-Menu).Trim().ToLower()
            if     ($choice -eq 'q')  { break }
            elseif ($choice -eq 'a')  { Invoke-All; Show-Summary }
            elseif ($choice -eq 'd')  { $Script:IsDryRun = $true; Invoke-All; Show-Summary }
            elseif ($choice -eq 'p')  { $Script:IsDryRun = -not $Script:IsDryRun }
            elseif ($choice -eq '1')  { Invoke-Debloat; Show-Summary -Section }
            elseif ($choice -eq '2')  { Invoke-Privacy; Show-Summary -Section }
            elseif ($choice -eq '3')  { Invoke-WindowsUpdate; Show-Summary -Section }
            elseif ($choice -eq '4')  { Invoke-Performance; Show-Summary -Section }
            elseif ($choice -eq '5')  { Invoke-Shell; Show-Summary -Section }
            elseif ($choice -eq '6')  { Invoke-Network; Show-Summary -Section }
            elseif ($choice -eq '7')  { Invoke-Security; Show-Summary -Section }
            elseif ($choice -eq '8')  { Invoke-Apps; Show-Summary -Section }
            elseif ($choice -eq '9')  { Invoke-Dev; Show-Summary -Section }
            elseif ($choice -eq '10') { Invoke-Maintenance; Show-Summary -Section }
            else {
                Write-Host "  Choix invalide." -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    }

    Write-Host "Au revoir !" -ForegroundColor Cyan
    try { Stop-Transcript | Out-Null } catch { }
}

Main
