# ZenqAddons.ps1 -- Installateur et mise a jour des addons Zenq pour Sku, de Sku
# lui-meme (via son installateur officiel) et des addons tiers courants, pour
# World of Warcraft Classic Anniversary (Burning Crusade) et Classic Era.
#
# Zenq Addons installer / updater -- companion addons for Sku, Sku itself
# (through its official installer) and the usual third-party addons.
#
#   Fenetre (par defaut) : cases a cocher par addon, "Tout cocher / Tout
#   decocher", memoire des choix, annonces au lecteur d'ecran (UIA).
#   Console : ZenqAddons.ps1 -NoGui -Check          (etat)
#             ZenqAddons.ps1 -NoGui -Install Questie,SkuBagnonBridge
#             ZenqAddons.ps1 -NoGui -All             (tout ce qui est coche)
#
# Le catalogue (quels addons, ou les prendre) est un JSON public :
#   https://zenqfr.github.io/sku-addons/catalog.json
# Sources : versions GitHub (releases), fichiers CurseForge (liste publique du
# site, sans cle), et l'installateur officiel de Sku pour Sku et ses paquets.
#
# Reglages : %APPDATA%\ZenqAddons\settings.json   (dossier WoW, version du jeu,
#            cases cochees, options d'annonce)
# Etat     : %APPDATA%\ZenqAddons\installed.json  (version posee par addon)
# Journal  : %APPDATA%\ZenqAddons\journal.log
#
# Windows PowerShell 5.1 (present sur tout Windows 10/11), aucune dependance.

#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$WowPath,
    [string]$Flavor,
    [string]$Catalog,
    [switch]$NoGui,
    [switch]$Check,
    [string[]]$Install,
    [switch]$All,
    [switch]$Reinstall,
    [ValidateSet('fr', 'en')][string]$Lang,
    [switch]$NoSelfUpdate
)

$ErrorActionPreference = 'Stop'
$Script:AppVersion = '1.0.0'
$Script:DefaultCatalogUrl = 'https://zenqfr.github.io/sku-addons/catalog.json'
$Script:SiteUrl = 'https://zenqfr.github.io/sku-addons/'
$Script:DataDir = Join-Path $env:APPDATA 'ZenqAddons'
$Script:SettingsPath = Join-Path $Script:DataDir 'settings.json'
$Script:StatePath = Join-Path $Script:DataDir 'installed.json'
$Script:LogPath = Join-Path $Script:DataDir 'journal.log'
$Script:CatalogCachePath = Join-Path $Script:DataDir 'catalog.json'
$Script:TmpDir = Join-Path $Script:DataDir 'tmp'
$Script:UserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36 ZenqAddons/' + $Script:AppVersion
$Script:GhCache = @{}
$Script:Ui = $null
$Script:Busy = $false
$Script:Statuses = @{}
$Script:Lang = 'fr'

try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (-not $NoGui) {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
}

# ---------------------------------------------------------------------------
# Textes / strings
# ---------------------------------------------------------------------------
$Script:Strings = @{
    fr = @{
        title            = 'Installateur Zenq Addons'
        wowFolder        = 'Dossier World of Warcraft :'
        changeFolder     = '&Dossier WoW...'
        gameVersion      = 'Version du jeu :'
        langButton       = 'English'
        checkAll         = '&Tout cocher'
        uncheckAll       = 'Tout d&écocher'
        refresh          = '&Vérifier les mises à jour'
        installSel       = '&Installer ou mettre à jour la sélection'
        openLog          = 'Ouvrir le &journal'
        close            = '&Fermer'
        optAnnounce      = 'Annoncer la progression au lecteur d''écran'
        optSapi          = 'Lire aussi avec la voix Windows (SAPI)'
        optReinstall     = 'Réinstaller même si à jour'
        logLabel         = 'Journal'
        statusReady      = 'Prêt.'
        notInstalled     = 'non installé, disponible {0}'
        upToDate         = 'à jour ({0})'
        updateAvail      = 'installé {0}, mise à jour {1} disponible'
        installedUnknown = 'installé {0}, version en ligne inconnue ({1})'
        newerLocal       = 'installé {0}, plus récent que la version en ligne {1}'
        checking         = 'vérification...'
        beta             = '(bêta)'
        managedBySku     = 'géré par l''installateur officiel de Sku'
        installedNoVer   = 'installé'
        noWow            = 'Aucun dossier World of Warcraft trouvé. Choisis-le avec le bouton « Dossier WoW... ».'
        badWow           = 'Ce dossier ne contient aucune version du jeu (_anniversary_, _classic_era_...).'
        loadingCatalog   = 'Chargement du catalogue...'
        catalogFailed    = 'Catalogue injoignable ({0}). Copie locale utilisée.'
        catalogNone      = 'Catalogue injoignable et aucune copie locale : vérifie la connexion.'
        checkingAll      = 'Vérification des versions en ligne, {0} addons...'
        checkDone        = 'Vérification terminée : {0} à installer ou mettre à jour, {1} à jour.'
        nothingSelected  = 'Aucun addon coché.'
        nothingToDo      = 'Tout est déjà à jour dans la sélection.'
        installing       = 'Installation {0} sur {1} : {2}'
        downloading      = 'Téléchargement de {0}, {1} Mo'
        extracting       = 'Extraction de {0}...'
        installedOk      = '{0} installé, version {1}.'
        installFailed    = '{0} : échec, {1}'
        summary          = 'Terminé : {0} installés ou mis à jour, {1} échecs, {2} ignorés (déjà à jour).'
        summaryTitle     = 'Résumé'
        needsRestart     = 'Relance World of Warcraft (un nouveau dossier d''addon demande un vrai redémarrage, pas seulement /reload).'
        skuLaunch        = 'L''installateur officiel de Sku est lancé : suis ses instructions, il gère Sku, ses sons et l''outil de connexion.'
        skuDownload      = 'Téléchargement de l''installateur officiel de Sku...'
        skuBadHash       = 'L''installateur de Sku téléchargé ne correspond pas à l''empreinte publiée, il n''est pas lancé.'
        requiresMissing  = '{0} a besoin de {1}, qui n''est ni installé ni coché.'
        zipNoFolder      = 'l''archive ne contient aucun dossier d''addon'
        zipMissingRoot   = 'l''archive ne contient pas le dossier attendu {0}'
        selfUpdateAsk    = 'Une nouvelle version de l''installateur ({0}) est disponible (tu as la {1}). La télécharger et relancer maintenant ?'
        selfUpdateTitle  = 'Mise à jour de l''installateur'
        selfUpdated      = 'Installateur mis à jour, relance en cours.'
        busy             = 'Une opération est en cours, patiente.'
        pathLabel        = '{0} ({1})'
        selectedCount    = '{0} cochés sur {1}.'
        groupCount       = '{0} addons'
        openSite         = '&Site des addons'
        unknownVersion   = 'inconnue'
        removedOld       = 'Ancien dossier {0} remplacé.'
        yes              = 'Oui'
        no               = 'Non'
    }
    en = @{
        title            = 'Zenq Addons Installer'
        wowFolder        = 'World of Warcraft folder:'
        changeFolder     = 'WoW &folder...'
        gameVersion      = 'Game version:'
        langButton       = 'Français'
        checkAll         = 'Check &all'
        uncheckAll       = '&Uncheck all'
        refresh          = 'Check for &updates'
        installSel       = '&Install or update the selection'
        openLog          = 'Open the &log'
        close            = '&Close'
        optAnnounce      = 'Announce progress to the screen reader'
        optSapi          = 'Also speak with the Windows voice (SAPI)'
        optReinstall     = 'Reinstall even when up to date'
        logLabel         = 'Log'
        statusReady      = 'Ready.'
        notInstalled     = 'not installed, available {0}'
        upToDate         = 'up to date ({0})'
        updateAvail      = 'installed {0}, update {1} available'
        installedUnknown = 'installed {0}, online version unknown ({1})'
        newerLocal       = 'installed {0}, newer than the online version {1}'
        checking         = 'checking...'
        beta             = '(beta)'
        managedBySku     = 'managed by the official Sku installer'
        installedNoVer   = 'installed'
        noWow            = 'No World of Warcraft folder found. Pick it with the "WoW folder..." button.'
        badWow           = 'This folder holds no game version (_anniversary_, _classic_era_...).'
        loadingCatalog   = 'Loading the catalog...'
        catalogFailed    = 'Catalog unreachable ({0}). Local copy used.'
        catalogNone      = 'Catalog unreachable and no local copy: check the connection.'
        checkingAll      = 'Checking online versions, {0} addons...'
        checkDone        = 'Check done: {0} to install or update, {1} up to date.'
        nothingSelected  = 'No addon checked.'
        nothingToDo      = 'Everything in the selection is already up to date.'
        installing       = 'Installing {0} of {1}: {2}'
        downloading      = 'Downloading {0}, {1} MB'
        extracting       = 'Extracting {0}...'
        installedOk      = '{0} installed, version {1}.'
        installFailed    = '{0}: failed, {1}'
        summary          = 'Done: {0} installed or updated, {1} failed, {2} skipped (already up to date).'
        summaryTitle     = 'Summary'
        needsRestart     = 'Restart World of Warcraft (a new addon folder needs a real restart, not just /reload).'
        skuLaunch        = 'The official Sku installer is running: follow its steps, it handles Sku, its sounds and the login tool.'
        skuDownload      = 'Downloading the official Sku installer...'
        skuBadHash       = 'The downloaded Sku installer does not match the published checksum; it is not started.'
        requiresMissing  = '{0} needs {1}, which is neither installed nor checked.'
        zipNoFolder      = 'the archive holds no addon folder'
        zipMissingRoot   = 'the archive lacks the expected folder {0}'
        selfUpdateAsk    = 'A newer installer ({0}) is available (you have {1}). Download it and restart now?'
        selfUpdateTitle  = 'Installer update'
        selfUpdated      = 'Installer updated, restarting.'
        busy             = 'An operation is running, please wait.'
        pathLabel        = '{0} ({1})'
        selectedCount    = '{0} checked of {1}.'
        groupCount       = '{0} addons'
        openSite         = 'Addons &site'
        unknownVersion   = 'unknown'
        removedOld       = 'Old folder {0} replaced.'
        yes              = 'Yes'
        no               = 'No'
    }
}

function T([string]$key) {
    $t = $Script:Strings[$Script:Lang]
    if ($t -and $t.ContainsKey($key)) { return $t[$key] }
    $f = $Script:Strings['fr']
    if ($f.ContainsKey($key)) { return $f[$key] }
    return $key
}

function TF([string]$key) { $fmt = T $key; if ($args.Count -gt 0) { return ($fmt -f $args) } ; return $fmt }

function Get-Loc($obj) {
    # A {fr, en} object from the catalog -> the string for the current language.
    if ($null -eq $obj) { return '' }
    if ($obj -is [string]) { return $obj }
    $v = $null
    try { $v = $obj.($Script:Lang) } catch {}
    if (-not $v) { try { $v = $obj.fr } catch {} }
    if (-not $v) { try { $v = $obj.en } catch {} }
    if ($null -eq $v) { return '' }
    return [string]$v
}

# ---------------------------------------------------------------------------
# Journal, reglages, etat
# ---------------------------------------------------------------------------
function Ensure-DataDir { if (-not (Test-Path $Script:DataDir)) { New-Item -ItemType Directory -Path $Script:DataDir | Out-Null } }

function Write-Log([string]$text) {
    try {
        Ensure-DataDir
        $line = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  ' + $text
        Add-Content -Path $Script:LogPath -Value $line -Encoding UTF8
        $fi = Get-Item $Script:LogPath -ErrorAction SilentlyContinue
        if ($fi -and $fi.Length -gt 800KB) {
            $tail = Get-Content $Script:LogPath -Tail 800 -Encoding UTF8
            Set-Content -Path $Script:LogPath -Value $tail -Encoding UTF8
        }
    } catch {}
}

function Read-JsonFile([string]$path) {
    if (-not (Test-Path $path)) { return $null }
    try { return (Get-Content -Path $path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { Write-Log "JSON illisible: $path ($($_.Exception.Message))"; return $null }
}

function Write-JsonFile([string]$path, $obj) {
    Ensure-DataDir
    $json = $obj | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($path, $json, (New-Object Text.UTF8Encoding($false)))
}

function Has-Prop($obj, [string]$name) { return ($null -ne $obj) -and ($obj.PSObject.Properties.Name -contains $name) }

function Set-Prop($obj, [string]$name, $value) { $obj | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force }

function Load-Settings {
    $s = Read-JsonFile $Script:SettingsPath
    if (-not $s) { $s = [pscustomobject]@{} }
    foreach ($p in @('wowRoot', 'flavor', 'lang')) { if (-not (Has-Prop $s $p)) { Set-Prop $s $p $null } }
    if (-not (Has-Prop $s 'announce')) { Set-Prop $s 'announce' $true }
    if (-not (Has-Prop $s 'sapi')) { Set-Prop $s 'sapi' $false }
    if (-not (Has-Prop $s 'reinstall')) { Set-Prop $s 'reinstall' $false }
    if (-not (Has-Prop $s 'selected') -or $null -eq $s.selected) { Set-Prop $s 'selected' ([pscustomobject]@{}) }
    $Script:Settings = $s
}

function Save-Settings { try { Write-JsonFile $Script:SettingsPath $Script:Settings } catch { Write-Log "settings: $($_.Exception.Message)" } }

function Get-Selected([string]$id) {
    if (Has-Prop $Script:Settings.selected $id) { return [bool]$Script:Settings.selected.$id }
    return $null
}

function Set-Selected([string]$id, [bool]$value) { Set-Prop $Script:Settings.selected $id $value }

function Load-State {
    $st = Read-JsonFile $Script:StatePath
    if (-not $st) { $st = [pscustomobject]@{} }
    $Script:State = $st
}

function Get-StateEntry([string]$flavorId, [string]$key) {
    if (-not (Has-Prop $Script:State $flavorId)) { return $null }
    $fl = $Script:State.$flavorId
    if (Has-Prop $fl $key) { return $fl.$key }
    return $null
}

function Set-StateEntry([string]$flavorId, [string]$key, $entry) {
    if (-not (Has-Prop $Script:State $flavorId)) { Set-Prop $Script:State $flavorId ([pscustomobject]@{}) }
    Set-Prop $Script:State.$flavorId $key $entry
    try { Write-JsonFile $Script:StatePath $Script:State } catch { Write-Log "state: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------------------
# Interface : annonces, pompe d'evenements
# ---------------------------------------------------------------------------
function Pump-Ui { if ($Script:Ui) { try { [System.Windows.Forms.Application]::DoEvents() } catch {} } }

function Speak-Sapi([string]$text) {
    try {
        if (-not $Script:Synth) { Add-Type -AssemblyName System.Speech; $Script:Synth = New-Object System.Speech.Synthesis.SpeechSynthesizer }
        $Script:Synth.SpeakAsyncCancelAll()
        [void]$Script:Synth.SpeakAsync($text)
    } catch { Write-Log "SAPI: $($_.Exception.Message)" }
}

function Announce([string]$text, [switch]$Quiet) {
    Write-Log $text
    if ($Script:Ui) {
        $Script:Ui.Status.Text = $text
        $Script:Ui.Log.AppendText($text + "`r`n")
        if (-not $Quiet) {
            if ($Script:Settings.announce) {
                try {
                    $Script:Ui.Form.AccessibilityObject.RaiseAutomationNotification(
                        [System.Windows.Forms.Automation.AutomationNotificationKind]::ActionCompleted,
                        [System.Windows.Forms.Automation.AutomationNotificationProcessing]::MostRecent,
                        $text)
                } catch {}
            }
            if ($Script:Settings.sapi) { Speak-Sapi $text }
        }
        Pump-Ui
    } else {
        Write-Host $text
    }
}

function Show-Message([string]$text, [string]$title, [string]$kind) {
    if ($Script:Ui) {
        $icon = [System.Windows.Forms.MessageBoxIcon]::Information
        if ($kind -eq 'error') { $icon = [System.Windows.Forms.MessageBoxIcon]::Error }
        [void][System.Windows.Forms.MessageBox]::Show($Script:Ui.Form, $text, $title, [System.Windows.Forms.MessageBoxButtons]::OK, $icon)
    } else { Write-Host "$title : $text" }
}

function Ask-YesNo([string]$text, [string]$title) {
    if ($Script:Ui) {
        $r = [System.Windows.Forms.MessageBox]::Show($Script:Ui.Form, $text, $title, [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
        return ($r -eq [System.Windows.Forms.DialogResult]::Yes)
    }
    $a = Read-Host "$text [o/n]"
    return ($a -match '^(o|y)')
}

# ---------------------------------------------------------------------------
# Reseau
# ---------------------------------------------------------------------------
function Invoke-Json([string]$url) {
    return Invoke-RestMethod -Uri $url -UserAgent $Script:UserAgent -TimeoutSec 40 -Headers @{ Accept = 'application/json' }
}

function Invoke-Text([string]$url) {
    $r = Invoke-WebRequest -Uri $url -UserAgent $Script:UserAgent -TimeoutSec 40 -UseBasicParsing
    return [string]$r.Content
}

function Get-RedirectTarget([string]$url) {
    $req = [Net.HttpWebRequest]::Create($url)
    $req.UserAgent = $Script:UserAgent
    $req.AllowAutoRedirect = $false
    $req.Method = 'HEAD'
    $req.Timeout = 20000
    $resp = $null
    try { $resp = $req.GetResponse() } catch [Net.WebException] { $resp = $_.Exception.Response }
    if ($resp) {
        $loc = $resp.Headers['Location']
        $resp.Close()
        return $loc
    }
    return $null
}

function Invoke-Download([string]$url, [string]$dest, [string]$label) {
    if (Test-Path $dest) { Remove-Item -Path $dest -Force }
    $wc = New-Object Net.WebClient
    $wc.Headers['User-Agent'] = $Script:UserAgent
    $task = $wc.DownloadFileTaskAsync($url, $dest)
    $lastMb = -1
    while (-not $task.IsCompleted) {
        $len = 0
        if (Test-Path $dest) { $len = (Get-Item $dest).Length }
        $mb = [math]::Floor($len / 1MB)
        if ($mb -ne $lastMb -and $Script:Ui) {
            $lastMb = $mb
            $Script:Ui.Status.Text = (TF 'downloading' $label $mb)
        }
        Pump-Ui
        Start-Sleep -Milliseconds 150
    }
    $wc.Dispose()
    if ($task.IsFaulted) {
        $ex = $task.Exception
        if ($ex.InnerException) { $ex = $ex.InnerException }
        throw $ex
    }
    if (-not (Test-Path $dest) -or (Get-Item $dest).Length -lt 100) { throw "empty download" }
}

# The release tag through the website redirect (no API call, no rate limit --
# the same trick as Sku's own installer); the API only when asked for assets.
function Get-GitHubLatestTag([string]$repo) {
    $loc = Get-RedirectTarget "https://github.com/$repo/releases/latest"
    if ($loc -and $loc -match '/releases/tag/([^/?#]+)$') { return [Uri]::UnescapeDataString($matches[1]) }
    return $null
}

function Test-UrlExists([string]$url) {
    $req = [Net.HttpWebRequest]::Create($url)
    $req.UserAgent = $Script:UserAgent
    $req.AllowAutoRedirect = $false
    $req.Method = 'HEAD'
    $req.Timeout = 20000
    $resp = $null
    try { $resp = $req.GetResponse() } catch [Net.WebException] { $resp = $_.Exception.Response }
    if (-not $resp) { return $false }
    $code = [int]$resp.StatusCode
    $resp.Close()
    return ($code -ge 200 -and $code -lt 400)
}

function Get-GitHubLatest([string]$repo) {
    if ($Script:GhCache.ContainsKey($repo)) { return $Script:GhCache[$repo] }
    $r = $null
    try {
        $j = Invoke-Json "https://api.github.com/repos/$repo/releases/latest"
        $assets = @()
        foreach ($a in @($j.assets)) { $assets += @{ name = [string]$a.name; url = [string]$a.browser_download_url; size = [long]$a.size } }
        $r = @{ tag = [string]$j.tag_name; assets = $assets; published = [string]$j.published_at; api = $true }
    } catch {
        Write-Log "GitHub API failed for $repo : $($_.Exception.Message)"
        try {
            $loc = Get-RedirectTarget "https://github.com/$repo/releases/latest"
            if ($loc -and $loc -match '/releases/tag/([^/?#]+)$') {
                $r = @{ tag = [Uri]::UnescapeDataString($matches[1]); assets = @(); published = ''; api = $false }
            }
        } catch { Write-Log "GitHub redirect failed for $repo : $($_.Exception.Message)" }
    }
    if ($r) { $r.version = ($r.tag -replace '^[vV](?=\d)', '') }
    $Script:GhCache[$repo] = $r
    return $r
}

function Resolve-GitHubPackage($pkg) {
    # 1. Cheap path: tag from the redirect, asset name from the template, one
    #    HEAD to confirm the file exists. 2. Otherwise the API's asset list.
    $tag = $null
    try { $tag = Get-GitHubLatestTag ([string]$pkg.repo) } catch { Write-Log "GitHub redirect failed for $($pkg.repo): $($_.Exception.Message)" }
    if ($tag) {
        $ver = ($tag -replace '^[vV](?=\d)', '')
        $tn = ([string]$pkg.asset).Replace('{tag}', $tag).Replace('{version}', $ver).Replace('{id}', [string]$pkg.key)
        $turl = "https://github.com/$($pkg.repo)/releases/download/$([Uri]::EscapeDataString($tag))/$([Uri]::EscapeDataString($tn))"
        if (Test-UrlExists $turl) { return @{ version = $ver; tag = $tag; url = $turl; name = $tn; size = 0 } }
        Write-Log "GitHub: templated asset '$tn' not found on $($pkg.repo) $tag, asking the API"
    }
    $rel = Get-GitHubLatest ([string]$pkg.repo)
    if (-not $rel) { throw "GitHub: $($pkg.repo) unreachable" }
    $name = [string]$pkg.asset
    $name = $name.Replace('{tag}', $rel.tag).Replace('{version}', $rel.version).Replace('{id}', [string]$pkg.key)
    $asset = $null
    foreach ($a in $rel.assets) { if ($a.name -ieq $name) { $asset = $a; break } }
    if (-not $asset -and $rel.assets.Count -gt 0) {
        foreach ($a in $rel.assets) { if ($a.name -like '*.zip' -and $a.name -notlike '*macos*') { $asset = $a; break } }
        if ($asset) { Write-Log "asset '$name' not found on $($pkg.repo) $($rel.tag), using '$($asset.name)'" }
    }
    $url = "https://github.com/$($pkg.repo)/releases/download/$([Uri]::EscapeDataString($rel.tag))/$([Uri]::EscapeDataString($name))"
    $size = 0
    if ($asset) { $url = $asset.url; $name = $asset.name; $size = $asset.size }
    return @{ version = $rel.version; tag = $rel.tag; url = $url; name = $name; size = $size }
}

function Resolve-CurseForgePackage($pkg, $flavor) {
    $project = [int]$pkg.project
    $j = Invoke-Json "https://www.curseforge.com/api/v1/mods/$project/files?pageIndex=0&pageSize=30&sort=dateCreated&sortDescending=true"
    $files = @($j.data)
    if ($files.Count -eq 0) { throw "CurseForge: no file for project $project" }
    $prefix = [string]$flavor.gameVersionPrefix
    $cands = @()
    foreach ($f in $files) {
        $ok = $false
        foreach ($gv in @($f.gameVersions)) { if ([string]$gv -like "$prefix*") { $ok = $true; break } }
        if ($ok) { $cands += $f }
    }
    $contains = $null
    if (Has-Prop $pkg 'curseforgeFileContains') { $contains = [string]$pkg.curseforgeFileContains }
    if ($contains) { $cands = @($cands | Where-Object { [string]$_.fileName -like "*$contains*" }) }
    if ($cands.Count -eq 0) { $cands = $files; Write-Log "CurseForge $project : no file for $prefix, taking the newest" }
    $best = $null
    foreach ($f in $cands) { if ([int]$f.releaseType -eq 1) { $best = $f; break } }
    if (-not $best) { $best = $cands[0] }
    return @{
        version = [string]$best.displayName
        url     = "https://www.curseforge.com/api/v1/mods/$project/files/$($best.id)/download"
        name    = [string]$best.fileName
        size    = [long]$best.fileLength
        date    = [string]$best.dateCreated
    }
}

function Resolve-SkuInstaller($pkg) {
    $rel = $null
    $tag = $null
    try { $tag = Get-GitHubLatestTag ([string]$pkg.repo) } catch {}
    if ($tag) { $rel = @{ tag = $tag; version = ($tag -replace '^[vV](?=\d)', '') } }
    else { $rel = Get-GitHubLatest ([string]$pkg.repo) }
    if (-not $rel) { throw "GitHub: $($pkg.repo) unreachable" }
    $meta = $null
    try {
        $txt = Invoke-Text "https://github.com/$($pkg.repo)/releases/latest/download/$($pkg.metadata)"
        $meta = @{}
        foreach ($line in ($txt -split "`n")) { if ($line -match '^\s*([A-Za-z0-9_]+)\s*=\s*(\S+)') { $meta[$matches[1]] = $matches[2] } }
    } catch { Write-Log "Sku installer metadata: $($_.Exception.Message)" }
    $sha = $null; $iv = ''
    if ($meta) { $sha = $meta['sha256']; $iv = $meta['version'] }
    return @{
        version          = $rel.version
        tag              = $rel.tag
        url              = "https://github.com/$($pkg.repo)/releases/latest/download/$($pkg.asset)"
        name             = [string]$pkg.asset
        size             = 0
        sha256           = $sha
        installerVersion = $iv
    }
}

function Resolve-Package($pkg, $flavor) {
    switch ([string]$pkg.type) {
        'github-release' { return Resolve-GitHubPackage $pkg }
        'curseforge'     { return Resolve-CurseForgePackage $pkg $flavor }
        'sku-installer'  { return Resolve-SkuInstaller $pkg }
        default          { throw "unknown package type '$($pkg.type)'" }
    }
}

# ---------------------------------------------------------------------------
# Versions
# ---------------------------------------------------------------------------
function Normalize-Version([string]$v) {
    if (-not $v) { return '' }
    $s = $v.Trim().ToLowerInvariant()
    $s = $s -replace '^[v#]+', ''
    $s = $s -replace '[_\-\s]+', '.'
    $s = $s -replace '\.release$', ''
    $s = $s -replace '\.+', '.'
    return $s.Trim('.')
}

function Test-SameVersion([string]$a, [string]$b) {
    $x = Normalize-Version $a
    $y = Normalize-Version $b
    if (-not $x -or -not $y) { return $false }
    if ($x -eq $y) { return $true }
    if ($x.Contains($y) -or $y.Contains($x)) { return $true }
    $dx = @([regex]::Matches($x, '\d+') | ForEach-Object { $_.Value })
    $dy = @([regex]::Matches($y, '\d+') | ForEach-Object { $_.Value })
    if ($dx.Count -gt 0 -and $dy.Count -gt 0) {
        $tx = $dx[$dx.Count - 1]
        $ty = $dy[$dy.Count - 1]
        if ($tx.Length -ge 4 -and ($dy -contains $tx)) { return $true }
        if ($ty.Length -ge 4 -and ($dx -contains $ty)) { return $true }
        if ($dx.Count -ge 2 -and $dy.Count -ge 2) {
            $jx = ($dx -join '.'); $jy = ($dy -join '.')
            if ($jx -eq $jy) { return $true }
        }
    }
    return $false
}

# -1 local older, 0 same, 1 local newer, $null when the two cannot be compared.
function Compare-Versions([string]$local, [string]$remote) {
    if (Test-SameVersion $local $remote) { return 0 }
    $x = Normalize-Version $local
    $y = Normalize-Version $remote
    $dx = @([regex]::Matches($x, '\d+') | ForEach-Object { [long]$_.Value })
    $dy = @([regex]::Matches($y, '\d+') | ForEach-Object { [long]$_.Value })
    if ($dx.Count -lt 2 -or $dy.Count -lt 2 -or $dx.Count -ne $dy.Count) { return $null }
    for ($i = 0; $i -lt $dx.Count; $i++) {
        if ($dx[$i] -lt $dy[$i]) { return -1 }
        if ($dx[$i] -gt $dy[$i]) { return 1 }
    }
    return 0
}

function Get-TocFile([string]$addonsDir, [string]$folder) {
    $dir = Join-Path $addonsDir $folder
    if (-not (Test-Path $dir)) { return $null }
    return (Get-ChildItem -Path $dir -Filter '*.toc' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
}

function Get-TocVersion([string]$addonsDir, [string]$folder) {
    $dir = Join-Path $addonsDir $folder
    if (-not (Test-Path $dir)) { return $null }
    $tocs = @(Get-ChildItem -Path $dir -Filter '*.toc' -File -ErrorAction SilentlyContinue | Sort-Object {
        $n = $_.BaseName
        if ($n -ieq $folder) { 0 } elseif ($n -match '(?i)[_\-](TBC|BCC)$') { 1 } else { 2 }
    })
    foreach ($t in $tocs) {
        $m = Select-String -Path $t.FullName -Pattern '^\s*##\s*Version\s*:\s*(.+?)\s*$' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($m) { return $m.Matches[0].Groups[1].Value }
    }
    return ''
}

# ---------------------------------------------------------------------------
# Dossier WoW
# ---------------------------------------------------------------------------
function Get-FlavorFolders($catalog, [string]$root) {
    $found = @()
    foreach ($p in $catalog.flavors.PSObject.Properties) {
        $fl = $p.Value
        $dir = Join-Path $root ([string]$fl.folder)
        if ((Test-Path (Join-Path $dir 'Interface')) -or (Test-Path (Join-Path $dir 'WowClassic.exe')) -or (Test-Path (Join-Path $dir 'Wow.exe'))) {
            $found += @{ id = $p.Name; folder = [string]$fl.folder; label = (Get-Loc $fl.label); dir = $dir; prefix = [string]$fl.gameVersionPrefix; obj = $fl }
        }
    }
    return $found
}

function Find-WowRoots($catalog) {
    $cands = New-Object System.Collections.Generic.List[string]
    $add = { param($p) if ($p) { $p = $p.TrimEnd('\', '/'); if ($p -and -not $cands.Contains($p)) { $cands.Add($p) } } }
    foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        try {
            Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.InstallLocation -like '*Warcraft*' } | ForEach-Object { & $add ([string]$_.InstallLocation) }
        } catch {}
    }
    try {
        $cfg = Join-Path $env:APPDATA 'Battle.net\Battle.net.config'
        if (Test-Path $cfg) {
            $j = Get-Content $cfg -Raw | ConvertFrom-Json
            $dip = $null
            try { $dip = $j.Client.Install.DefaultInstallPath } catch {}
            if ($dip) { & $add (Join-Path ([string]$dip) 'World of Warcraft') }
        }
    } catch {}
    try {
        $db = 'C:\ProgramData\Battle.net\Agent\product.db'
        if (Test-Path $db) {
            $txt = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($db))
            foreach ($m in [regex]::Matches($txt, '[A-Za-z]:[\\/][^\x00-\x1f"]{2,120}?World of Warcraft')) { & $add ($m.Value -replace '/', '\') }
        }
    } catch {}
    foreach ($d in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null })) {
        foreach ($sub in @('World of Warcraft', 'Program Files (x86)\World of Warcraft', 'Program Files\World of Warcraft', 'Games\World of Warcraft', 'Jeux\World of Warcraft', 'Blizzard\World of Warcraft')) {
            & $add (Join-Path $d.Root $sub)
        }
    }
    $roots = @()
    Write-Log ("wow candidates: " + ($cands -join " | "))
    foreach ($c in $cands) {
        if (Test-Path $c) {
            $fl = @(Get-FlavorFolders $catalog $c)
            Write-Log ("candidate " + $c + " flavors=" + $fl.Count)
            if ($fl.Count -gt 0) { $roots += @{ root = $c; flavors = $fl } }
        }
    }
    Write-Log ("wow roots: " + $roots.Count)
    return $roots
}

function Resolve-WowRoot([string]$path, $catalog) {
    # Accepts the WoW root, a flavor folder (_anniversary_), or its Interface\AddOns.
    if (-not $path) { return $null }
    $p = $path.TrimEnd('\', '/')
    for ($i = 0; $i -lt 4 -and $p; $i++) {
        if (@(Get-FlavorFolders $catalog $p).Count -gt 0) { return $p }
        $p = Split-Path $p -Parent
    }
    return $null
}

# ---------------------------------------------------------------------------
# Catalogue
# ---------------------------------------------------------------------------
function Load-Catalog([string]$source) {
    $cat = $null
    if ($source -and (Test-Path $source)) {
        $cat = Get-Content -Path $source -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-Log "catalog from file $source"
        return $cat
    }
    $url = $Script:DefaultCatalogUrl
    if ($source) { $url = $source }
    try {
        $txt = Invoke-Text ($url + '?t=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
        $cat = $txt | ConvertFrom-Json
        try { Ensure-DataDir; [IO.File]::WriteAllText($Script:CatalogCachePath, $txt, (New-Object Text.UTF8Encoding($false))) } catch {}
        Write-Log "catalog from $url"
    } catch {
        Write-Log "catalog download failed: $($_.Exception.Message)"
        $cached = Read-JsonFile $Script:CatalogCachePath
        if ($cached) { Announce (TF 'catalogFailed' $_.Exception.Message); $cat = $cached }
        else { throw (T 'catalogNone') }
    }
    return $cat
}

function Get-Packages($addon, [string]$flavorId) {
    $out = @()
    foreach ($p in @($addon.packages)) {
        if ((Has-Prop $p 'flavors') -and $p.flavors -and (@($p.flavors) -notcontains $flavorId)) { continue }
        $out += $p
    }
    return $out
}

function Test-AddonInstalled($addon, [string]$addonsDir) {
    foreach ($f in @($addon.folders)) { if (Test-Path (Join-Path $addonsDir ([string]$f))) { return $true } }
    return $false
}

# ---------------------------------------------------------------------------
# Etat d'un addon (local + en ligne)
# ---------------------------------------------------------------------------
function New-Status($addon) {
    $installed = Test-AddonInstalled $addon $Script:Ctx.addonsDir
    $ver = $null
    if ($installed) { $ver = Get-TocVersion $Script:Ctx.addonsDir ([string]$addon.folders[0]) }
    return @{ id = [string]$addon.id; addon = $addon; installed = $installed; installedVersion = $ver; latest = $null; update = $false; checked = $false; error = $null; packages = @() }
}

function Refresh-Status($st) {
    $addon = $st.addon
    $st.installed = Test-AddonInstalled $addon $Script:Ctx.addonsDir
    $st.installedVersion = $null
    if ($st.installed) { $st.installedVersion = Get-TocVersion $Script:Ctx.addonsDir ([string]$addon.folders[0]) }
    $st.error = $null
    $st.packages = @()
    $st.update = $false
    $st.latest = $null
    if ($addon.infoOnly) { $st.checked = $true; return }
    foreach ($pkg in (Get-Packages $addon $Script:Ctx.flavor.id)) {
        $entry = @{ pkg = $pkg; resolved = $null; recorded = (Get-StateEntry $Script:Ctx.flavor.id ([string]$pkg.key)); needs = $false; error = $null }
        try {
            $entry.resolved = Resolve-Package $pkg $Script:Ctx.flavor.obj
            if (-not $st.latest) { $st.latest = $entry.resolved.version }
            $rootDir = Join-Path $Script:Ctx.addonsDir ([string]$pkg.roots[0])
            $present = Test-Path $rootDir
            if (-not $present) { $entry.needs = $true }
            elseif ($entry.recorded -and $entry.recorded.version) { $entry.needs = -not (Test-SameVersion ([string]$entry.recorded.version) ([string]$entry.resolved.version)) }
            else {
                $local = Get-TocVersion $Script:Ctx.addonsDir ([string]$pkg.roots[0])
                if ([string]$pkg.type -eq 'sku-installer') { $local = $st.installedVersion }
                $cmp = Compare-Versions $local ([string]$entry.resolved.version)
                if ($null -ne $cmp) {
                    $entry.needs = ($cmp -lt 0)
                    if ($cmp -gt 0) { $entry.newerLocal = $true }
                } else {
                    # Not comparable (CurseForge names like "Foo.zip"): the file's
                    # publication date against the installed .toc's own date.
                    $entry.needs = $false
                    $toc = Get-TocFile $Script:Ctx.addonsDir ([string]$pkg.roots[0])
                    if ($toc -and $entry.resolved.date) {
                        try {
                            $remoteDate = [DateTime]::Parse([string]$entry.resolved.date, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
                            if ($remoteDate -gt $toc.LastWriteTimeUtc.AddDays(1)) { $entry.needs = $true }
                        } catch {}
                    }
                }
            }
        } catch {
            $entry.error = $_.Exception.Message
            $st.error = $_.Exception.Message
            Write-Log "resolve $($addon.id)/$($pkg.key): $($entry.error)"
        }
        if ($entry.needs) { $st.update = $true }
        $st.packages += $entry
    }
    $st.checked = $true
}

function Get-StatusText($st) {
    $addon = $st.addon
    $name = [string]$addon.name
    if ([string]$addon.status -eq 'beta') { $name = $name + ' ' + (T 'beta') }
    $iv = $st.installedVersion
    if (-not $iv) { $iv = T 'unknownVersion' }
    if ($addon.infoOnly) {
        if ($st.installed) { return "$name — " + (T 'managedBySku') + ', ' + (T 'installedNoVer') }
        return "$name — " + (T 'managedBySku')
    }
    if (-not $st.checked) {
        if ($st.installed) { return "$name — " + (T 'installedNoVer') + " $iv" }
        return "$name — " + (TF 'notInstalled' '?')
    }
    $lv = $st.latest
    if (-not $lv) { $lv = T 'unknownVersion' }
    if ($st.error -and -not $st.latest) {
        if ($st.installed) { return "$name — " + (TF 'installedUnknown' $iv $st.error) }
        return "$name — " + (TF 'notInstalled' (T 'unknownVersion'))
    }
    if (-not $st.installed) { return "$name — " + (TF 'notInstalled' $lv) }
    if ($st.update) { return "$name — " + (TF 'updateAvail' $iv $lv) }
    foreach ($e in $st.packages) { if ($e.newerLocal) { return "$name — " + (TF 'newerLocal' $iv $lv) } }
    return "$name — " + (TF 'upToDate' $lv)
}

# ---------------------------------------------------------------------------
# Installation
# ---------------------------------------------------------------------------
function Get-ZipRoots([string]$zipPath) {
    $z = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $roots = New-Object System.Collections.Generic.List[string]
        $rootFiles = 0
        foreach ($e in $z.Entries) {
            $parts = $e.FullName -split '[/\\]'
            if ($parts.Count -eq 1) { if ($e.FullName -and -not $e.FullName.EndsWith('/')) { $rootFiles++ }; continue }
            $r = $parts[0]
            if ($r -eq '__MACOSX' -or $r -eq '') { continue }
            if (-not $roots.Contains($r)) { $roots.Add($r) }
        }
        return @{ roots = @($roots); rootFiles = $rootFiles }
    } finally { $z.Dispose() }
}

function Install-ZipPackage($st, $entry) {
    $pkg = $entry.pkg
    $rp = $entry.resolved
    $addon = $st.addon
    if (-not (Test-Path $Script:TmpDir)) { New-Item -ItemType Directory -Path $Script:TmpDir | Out-Null }
    $zip = Join-Path $Script:TmpDir ([IO.Path]::GetFileName([string]$rp.name))
    if (-not $zip.EndsWith('.zip')) { $zip = $zip + '.zip' }
    Announce (TF 'downloading' $addon.name 0) -Quiet
    Invoke-Download ([string]$rp.url) $zip ([string]$addon.name)
    $info = Get-ZipRoots $zip
    if ($info.roots.Count -eq 0) { throw (T 'zipNoFolder') }
    foreach ($req in @($pkg.roots)) { if ($info.roots -notcontains [string]$req) { throw (TF 'zipMissingRoot' $req) } }
    $allowed = New-Object System.Collections.Generic.List[string]
    foreach ($r in @($pkg.roots)) { $allowed.Add([string]$r) }
    if (Has-Prop $pkg 'extraRoots') { foreach ($r in @($pkg.extraRoots)) { $allowed.Add([string]$r) } }
    $prefix = $null
    if (Has-Prop $pkg 'rootPrefix') { $prefix = [string]$pkg.rootPrefix }
    $toInstall = @()
    foreach ($r in $info.roots) {
        if ($allowed.Contains($r) -or ($prefix -and $r.StartsWith($prefix))) { $toInstall += $r }
        else { Write-Log "zip root '$r' ignored for $($pkg.key) (not in roots/prefix)" }
    }
    if ($toInstall.Count -eq 0) { $toInstall = $info.roots }
    Announce (TF 'extracting' $addon.name) -Quiet
    $x = Join-Path $Script:TmpDir ('x_' + [string]$pkg.key)
    if (Test-Path $x) { Remove-Item -Path $x -Recurse -Force }
    New-Item -ItemType Directory -Path $x | Out-Null
    [IO.Compression.ZipFile]::ExtractToDirectory($zip, $x)
    foreach ($r in $toInstall) {
        $src = Join-Path $x $r
        if (-not (Test-Path $src)) { continue }
        $dst = Join-Path $Script:Ctx.addonsDir $r
        if (Test-Path $dst) { Remove-Item -Path $dst -Recurse -Force; Write-Log (TF 'removedOld' $r) }
        Move-Item -Path $src -Destination $dst
        Pump-Ui
    }
    Remove-Item -Path $x -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $zip -Force -ErrorAction SilentlyContinue
    Set-StateEntry $Script:Ctx.flavor.id ([string]$pkg.key) ([pscustomobject]@{ version = [string]$rp.version; date = (Get-Date -Format 'yyyy-MM-dd HH:mm'); roots = @($toInstall); source = [string]$rp.url })
}

function Install-SkuInstaller($st, $entry) {
    $rp = $entry.resolved
    if (-not (Test-Path $Script:TmpDir)) { New-Item -ItemType Directory -Path $Script:TmpDir | Out-Null }
    $exe = Join-Path $Script:DataDir 'SkuInstaller.exe'
    Announce (T 'skuDownload')
    Invoke-Download ([string]$rp.url) $exe 'SkuInstaller.exe'
    if ($rp.sha256) {
        $h = (Get-FileHash -Path $exe -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($h -ne ([string]$rp.sha256).ToLowerInvariant()) { throw (T 'skuBadHash') }
    }
    Start-Process -FilePath $exe
    Announce (T 'skuLaunch')
    Set-StateEntry $Script:Ctx.flavor.id ([string]$entry.pkg.key) ([pscustomobject]@{ version = [string]$rp.version; date = (Get-Date -Format 'yyyy-MM-dd HH:mm'); roots = @('Sku'); source = [string]$rp.url; installerVersion = [string]$rp.installerVersion })
}

function Install-Selection([string[]]$ids) {
    $done = 0; $failed = 0; $skipped = 0; $i = 0
    $newFolder = $false
    $total = $ids.Count
    foreach ($id in $ids) {
        $i++
        $st = $Script:Statuses[$id]
        if (-not $st -or $st.addon.infoOnly) { continue }
        if (-not $st.checked) { Refresh-Status $st }
        $addon = $st.addon
        Announce (TF 'installing' $i $total $addon.name)
        foreach ($req in @($addon.requires)) {
            $reqInstalled = Test-Path (Join-Path $Script:Ctx.addonsDir ([string]$req))
            if (-not $reqInstalled -and ($ids -notcontains [string]$req)) { Announce (TF 'requiresMissing' $addon.name $req) }
        }
        $any = $false
        foreach ($entry in $st.packages) {
            if ($entry.error -or -not $entry.resolved) { $failed++; Announce (TF 'installFailed' $addon.name $entry.error); continue }
            if (-not $entry.needs -and -not $Script:Settings.reinstall) { continue }
            try {
                if (-not (Test-Path (Join-Path $Script:Ctx.addonsDir ([string]$entry.pkg.roots[0])))) { $newFolder = $true }
                if ([string]$entry.pkg.type -eq 'sku-installer') { Install-SkuInstaller $st $entry } else { Install-ZipPackage $st $entry }
                $any = $true
            } catch {
                $failed++
                Announce (TF 'installFailed' $addon.name $_.Exception.Message)
                Write-Log $_.ScriptStackTrace
            }
        }
        if ($any) {
            $done++
            Refresh-Status $st
            Announce (TF 'installedOk' $addon.name $st.installedVersion)
        } elseif (-not $st.update) { $skipped++ }
        if ($Script:Ui) { Update-Row $st }
    }
    $msg = TF 'summary' $done $failed $skipped
    if ($newFolder) { $msg = $msg + ' ' + (T 'needsRestart') }
    Announce $msg
    return $msg
}

# ---------------------------------------------------------------------------
# Contexte (dossier + version du jeu)
# ---------------------------------------------------------------------------
function Set-Context([string]$root, [string]$flavorId) {
    $fls = @(Get-FlavorFolders $Script:Cat $root)
    if ($fls.Count -eq 0) { throw (T 'badWow') }
    $fl = $null
    foreach ($f in $fls) { if ($f.id -eq $flavorId) { $fl = $f } }
    if (-not $fl) { foreach ($f in $fls) { if ($f.id -eq 'anniversary') { $fl = $f } } }
    if (-not $fl) { $fl = $fls[0] }
    $addons = Join-Path $fl.dir 'Interface\AddOns'
    if (-not (Test-Path $addons)) { New-Item -ItemType Directory -Path $addons -Force | Out-Null }
    $Script:Ctx = @{ root = $root; flavor = $fl; flavors = $fls; addonsDir = $addons }
    $Script:Settings.wowRoot = $root
    $Script:Settings.flavor = $fl.id
    Save-Settings
    $Script:Statuses = @{}
    foreach ($a in @($Script:Cat.addons)) { $Script:Statuses[[string]$a.id] = New-Status $a }
    Write-Log "context: $addons"
}

function Initial-Checked($st) {
    $sel = Get-Selected $st.id
    if ($null -ne $sel) { return $sel }
    if ($st.installed) { return $true }
    $a = $st.addon
    if ([string]$a.group -eq 'zenq' -and $a.defaultChecked) { return $true }
    if ([string]$a.id -eq 'Sku') { return $true }
    return $false
}

function Test-SelfUpdate {
    if ($NoSelfUpdate) { return }
    try {
        $remote = [string]$Script:Cat.installer.version
        if (-not $remote) { return }
        if ([version]$remote -le [version]$Script:AppVersion) { return }
        if (-not $PSCommandPath) { return }
        if (-not (Ask-YesNo (TF 'selfUpdateAsk' $remote $Script:AppVersion) (T 'selfUpdateTitle'))) { return }
        $tmp = Join-Path $Script:DataDir 'ZenqAddons.new.ps1'
        Invoke-Download ([string]$Script:Cat.installer.script) $tmp 'ZenqAddons.ps1'
        $head = Get-Content $tmp -TotalCount 3 -Encoding UTF8
        if (-not ($head -join ' ' | Select-String 'ZenqAddons')) { throw 'unexpected content' }
        Copy-Item -Path $tmp -Destination $PSCommandPath -Force
        Remove-Item $tmp -Force
        Announce (T 'selfUpdated')
        Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', ('"' + $PSCommandPath + '"'), '-NoSelfUpdate')
        if ($Script:Ui) { $Script:Ui.Form.Close() }
        exit 0
    } catch { Write-Log "self-update: $($_.Exception.Message)" }
}

# ---------------------------------------------------------------------------
# Fenetre
# ---------------------------------------------------------------------------
function Update-Row($st) {
    $cb = $Script:Ui.Rows[$st.id]
    if (-not $cb) { return }
    $text = Get-StatusText $st
    $cb.Text = $text
    $cb.AccessibleName = $text
    Pump-Ui
}

function Update-SelectedCount {
    $n = 0; $t = 0
    foreach ($cb in $Script:Ui.Rows.Values) { $t++; if ($cb.Checked) { $n++ } }
    $Script:Ui.Count.Text = TF 'selectedCount' $n $t
}

function Refresh-All {
    if ($Script:Busy) { Announce (T 'busy'); return }
    $Script:Busy = $true
    try {
        $Script:GhCache = @{}
        $ids = @($Script:Statuses.Keys)
        Announce (TF 'checkingAll' $ids.Count)
        foreach ($cb in $Script:Ui.Rows.Values) { $cb.Text = ([string]$cb.Tag) + ' — ' + (T 'checking') }
        Pump-Ui
        $upd = 0; $ok = 0
        foreach ($a in @($Script:Cat.addons)) {
            $st = $Script:Statuses[[string]$a.id]
            Refresh-Status $st
            Update-Row $st
            if (-not $a.infoOnly) { if ($st.update) { $upd++ } elseif (-not $st.error) { $ok++ } }
        }
        Announce (TF 'checkDone' $upd $ok)
    } finally { $Script:Busy = $false }
}

function Install-Checked {
    if ($Script:Busy) { Announce (T 'busy'); return }
    $ids = @()
    foreach ($a in @($Script:Cat.addons)) {
        $cb = $Script:Ui.Rows[[string]$a.id]
        if ($cb -and $cb.Checked -and -not $a.infoOnly) { $ids += [string]$a.id }
    }
    if ($ids.Count -eq 0) { Announce (T 'nothingSelected'); return }
    $Script:Busy = $true
    Set-ButtonsEnabled $false
    try {
        $todo = @()
        foreach ($id in $ids) { $st = $Script:Statuses[$id]; if (-not $st.checked) { Refresh-Status $st; Update-Row $st } ; if ($st.update -or $Script:Settings.reinstall -or -not $st.installed) { $todo += $id } }
        if ($todo.Count -eq 0) { Announce (T 'nothingToDo'); Show-Message (T 'nothingToDo') (T 'summaryTitle') 'info'; return }
        $msg = Install-Selection $todo
        Show-Message $msg (T 'summaryTitle') 'info'
    } finally { $Script:Busy = $false; Set-ButtonsEnabled $true }
}

function Set-ButtonsEnabled([bool]$on) {
    foreach ($b in $Script:Ui.Buttons) { $b.Enabled = $on }
    Pump-Ui
}

function Choose-Folder {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = T 'wowFolder'
    $dlg.ShowNewFolderButton = $false
    if ($Script:Ctx -and $Script:Ctx.root) { $dlg.SelectedPath = $Script:Ctx.root }
    if ($dlg.ShowDialog($Script:Ui.Form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $root = Resolve-WowRoot $dlg.SelectedPath $Script:Cat
        if (-not $root) { Show-Message (T 'badWow') (T 'title') 'error'; return }
        Set-Context $root $Script:Settings.flavor
        Rebuild-Ui
    }
}

function Rebuild-Ui {
    $f = $Script:Ui.Form
    $lang = $Script:Lang
    $f.Close()
    $Script:Ui = $null
    Show-Gui
}

function Show-Gui {
    $F = New-Object System.Windows.Forms.Form
    $F.Text = (T 'title') + ' ' + $Script:AppVersion
    $F.StartPosition = 'CenterScreen'
    $F.Size = New-Object System.Drawing.Size(1000, 780)
    $F.MinimumSize = New-Object System.Drawing.Size(760, 560)
    $F.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $F.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi
    $F.KeyPreview = $true

    $root = New-Object System.Windows.Forms.TableLayoutPanel
    $root.Dock = 'Fill'
    $root.ColumnCount = 1
    $root.RowCount = 6
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 150)))
    [void]$root.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
    $F.Controls.Add($root)

    # --- header: folder + flavor + language
    $head = New-Object System.Windows.Forms.FlowLayoutPanel
    $head.Dock = 'Fill'; $head.AutoSize = $true; $head.WrapContents = $true; $head.Padding = '6,6,6,0'
    $lbl = New-Object System.Windows.Forms.Label; $lbl.Text = T 'wowFolder'; $lbl.AutoSize = $true; $lbl.Margin = '3,8,3,3'
    $pathLbl = New-Object System.Windows.Forms.Label; $pathLbl.AutoSize = $true; $pathLbl.Margin = '3,8,12,3'
    $pathLbl.Text = TF 'pathLabel' $Script:Ctx.root $Script:Ctx.flavor.folder
    $btnFolder = New-Object System.Windows.Forms.Button; $btnFolder.Text = T 'changeFolder'; $btnFolder.AutoSize = $true
    $lbl2 = New-Object System.Windows.Forms.Label; $lbl2.Text = T 'gameVersion'; $lbl2.AutoSize = $true; $lbl2.Margin = '12,8,3,3'
    $combo = New-Object System.Windows.Forms.ComboBox; $combo.DropDownStyle = 'DropDownList'; $combo.Width = 260
    $combo.AccessibleName = T 'gameVersion'
    foreach ($fl in $Script:Ctx.flavors) { [void]$combo.Items.Add($fl.label + ' — ' + $fl.folder) }
    for ($i = 0; $i -lt $Script:Ctx.flavors.Count; $i++) { if ($Script:Ctx.flavors[$i].id -eq $Script:Ctx.flavor.id) { $combo.SelectedIndex = $i } }
    $btnLang = New-Object System.Windows.Forms.Button; $btnLang.Text = T 'langButton'; $btnLang.AutoSize = $true; $btnLang.Margin = '12,3,3,3'
    $btnSite = New-Object System.Windows.Forms.Button; $btnSite.Text = T 'openSite'; $btnSite.AutoSize = $true
    $head.Controls.AddRange(@($lbl, $pathLbl, $btnFolder, $lbl2, $combo, $btnLang, $btnSite))
    $root.Controls.Add($head, 0, 0)

    # --- list of addons
    $scroll = New-Object System.Windows.Forms.Panel
    $scroll.Dock = 'Fill'; $scroll.AutoScroll = $true; $scroll.Padding = '6,0,6,0'
    $list = New-Object System.Windows.Forms.FlowLayoutPanel
    $list.FlowDirection = 'TopDown'; $list.WrapContents = $false; $list.AutoSize = $true; $list.AutoSizeMode = 'GrowAndShrink'
    $scroll.Controls.Add($list)
    $root.Controls.Add($scroll, 0, 1)

    $rows = @{}
    $groups = @{}
    foreach ($g in @($Script:Cat.groups)) {
        $gb = New-Object System.Windows.Forms.GroupBox
        $gb.Text = Get-Loc $g.label
        $gb.AutoSize = $true; $gb.AutoSizeMode = 'GrowAndShrink'; $gb.Padding = '10,6,10,6'; $gb.Margin = '3,3,3,10'
        $inner = New-Object System.Windows.Forms.FlowLayoutPanel
        $inner.FlowDirection = 'TopDown'; $inner.WrapContents = $false; $inner.AutoSize = $true; $inner.AutoSizeMode = 'GrowAndShrink'; $inner.Dock = 'Fill'
        $gb.Controls.Add($inner)
        $groups[[string]$g.id] = @{ box = $gb; inner = $inner; count = 0 }
    }
    foreach ($a in @($Script:Cat.addons)) {
        $st = $Script:Statuses[[string]$a.id]
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.AutoSize = $true
        $cb.Tag = [string]$a.name
        $cb.Text = Get-StatusText $st
        $cb.AccessibleName = $cb.Text
        $cb.AccessibleDescription = Get-Loc $a.summary
        $cb.Checked = Initial-Checked $st
        if ($a.infoOnly) { $cb.Enabled = $false; $cb.Checked = $false }
        $cb.Margin = '3,3,3,5'
        $id = [string]$a.id
        $cb.Add_CheckedChanged({ param($s, $e) if (-not $Script:Ui) { return }; foreach ($k in $Script:Ui.Rows.Keys) { if ($Script:Ui.Rows[$k] -eq $s) { Set-Selected $k ([bool]$s.Checked) } }; Save-Settings; Update-SelectedCount }.GetNewClosure())
        $g = $groups[[string]$a.group]
        if (-not $g) { $g = $groups[[string]$Script:Cat.groups[0].id] }
        $g.inner.Controls.Add($cb)
        $g.count++
        $rows[$id] = $cb
        Set-Selected $id ([bool]$cb.Checked)
    }
    foreach ($g in @($Script:Cat.groups)) { $gg = $groups[[string]$g.id]; if ($gg.count -gt 0) { $list.Controls.Add($gg.box) } }
    Save-Settings

    # --- options
    $opts = New-Object System.Windows.Forms.FlowLayoutPanel
    $opts.Dock = 'Fill'; $opts.AutoSize = $true; $opts.WrapContents = $true; $opts.Padding = '6,0,6,0'
    $cbAnn = New-Object System.Windows.Forms.CheckBox; $cbAnn.Text = T 'optAnnounce'; $cbAnn.AutoSize = $true; $cbAnn.Checked = [bool]$Script:Settings.announce
    $cbSapi = New-Object System.Windows.Forms.CheckBox; $cbSapi.Text = T 'optSapi'; $cbSapi.AutoSize = $true; $cbSapi.Checked = [bool]$Script:Settings.sapi
    $cbRe = New-Object System.Windows.Forms.CheckBox; $cbRe.Text = T 'optReinstall'; $cbRe.AutoSize = $true; $cbRe.Checked = [bool]$Script:Settings.reinstall
    $cbAnn.Add_CheckedChanged({ $Script:Settings.announce = [bool]$Script:Ui.OptAnn.Checked; Save-Settings })
    $cbSapi.Add_CheckedChanged({ $Script:Settings.sapi = [bool]$Script:Ui.OptSapi.Checked; Save-Settings })
    $cbRe.Add_CheckedChanged({ $Script:Settings.reinstall = [bool]$Script:Ui.OptRe.Checked; Save-Settings })
    $opts.Controls.AddRange(@($cbAnn, $cbSapi, $cbRe))
    $root.Controls.Add($opts, 0, 2)

    # --- buttons
    $bar = New-Object System.Windows.Forms.FlowLayoutPanel
    $bar.Dock = 'Fill'; $bar.AutoSize = $true; $bar.WrapContents = $true; $bar.Padding = '6,0,6,0'
    $bCheckAll = New-Object System.Windows.Forms.Button; $bCheckAll.Text = T 'checkAll'; $bCheckAll.AutoSize = $true
    $bUncheck = New-Object System.Windows.Forms.Button; $bUncheck.Text = T 'uncheckAll'; $bUncheck.AutoSize = $true
    $bRefresh = New-Object System.Windows.Forms.Button; $bRefresh.Text = T 'refresh'; $bRefresh.AutoSize = $true
    $bInstall = New-Object System.Windows.Forms.Button; $bInstall.Text = T 'installSel'; $bInstall.AutoSize = $true
    $bInstall.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
    $bLog = New-Object System.Windows.Forms.Button; $bLog.Text = T 'openLog'; $bLog.AutoSize = $true
    $bClose = New-Object System.Windows.Forms.Button; $bClose.Text = T 'close'; $bClose.AutoSize = $true
    $count = New-Object System.Windows.Forms.Label; $count.AutoSize = $true; $count.Margin = '12,8,3,3'
    $bar.Controls.AddRange(@($bCheckAll, $bUncheck, $bRefresh, $bInstall, $bLog, $bClose, $count))
    $root.Controls.Add($bar, 0, 3)

    # --- log
    $log = New-Object System.Windows.Forms.TextBox
    $log.Multiline = $true; $log.ReadOnly = $true; $log.ScrollBars = 'Vertical'; $log.Dock = 'Fill'
    $log.AccessibleName = T 'logLabel'
    $log.Margin = '6,3,6,3'
    $root.Controls.Add($log, 0, 4)

    # --- status
    $status = New-Object System.Windows.Forms.Label
    $status.AutoSize = $true; $status.Dock = 'Fill'; $status.Padding = '6,3,6,6'
    $status.Text = T 'statusReady'
    $root.Controls.Add($status, 0, 5)

    $Script:Ui = @{ Form = $F; Rows = $rows; Log = $log; Status = $status; Count = $count; OptAnn = $cbAnn; OptSapi = $cbSapi; OptRe = $cbRe; PathLabel = $pathLbl; List = $list; Scroll = $scroll
        Buttons = @($bCheckAll, $bUncheck, $bRefresh, $bInstall, $btnFolder, $combo, $btnLang) }

    $resize = {
        if (-not $Script:Ui) { return }
        $w = $Script:Ui.Scroll.ClientSize.Width - 30
        if ($w -lt 300) { $w = 300 }
        foreach ($c in $Script:Ui.List.Controls) { $c.MinimumSize = New-Object System.Drawing.Size($w, 0); $c.MaximumSize = New-Object System.Drawing.Size($w, 0) }
    }
    $F.Add_Shown($resize)
    $F.Add_Resize($resize)

    $bCheckAll.Add_Click({ foreach ($cb in $Script:Ui.Rows.Values) { if ($cb.Enabled) { $cb.Checked = $true } } })
    $bUncheck.Add_Click({ foreach ($cb in $Script:Ui.Rows.Values) { if ($cb.Enabled) { $cb.Checked = $false } } })
    $bRefresh.Add_Click({ Refresh-All })
    $bInstall.Add_Click({ Install-Checked })
    $bLog.Add_Click({ if (Test-Path $Script:LogPath) { Start-Process notepad.exe -ArgumentList ('"' + $Script:LogPath + '"') } })
    $bClose.Add_Click({ $Script:Ui.Form.Close() })
    $btnFolder.Add_Click({ if ($Script:Busy) { Announce (T 'busy') } else { Choose-Folder } })
    $btnSite.Add_Click({ Start-Process $Script:SiteUrl })
    $btnLang.Add_Click({
        if ($Script:Busy) { Announce (T 'busy'); return }
        if ($Script:Lang -eq 'fr') { $Script:Lang = 'en' } else { $Script:Lang = 'fr' }
        $Script:Settings.lang = $Script:Lang; Save-Settings
        Rebuild-Ui
    })
    $combo.Add_SelectedIndexChanged({
        if ($Script:Busy) { return }
        $i = $Script:Ui.Combo.SelectedIndex
        if ($i -ge 0 -and $i -lt $Script:Ctx.flavors.Count) {
            $fl = $Script:Ctx.flavors[$i]
            if ($fl.id -ne $Script:Ctx.flavor.id) { Set-Context $Script:Ctx.root $fl.id; Rebuild-Ui }
        }
    })
    $Script:Ui.Combo = $combo
    $F.Add_FormClosed({ Save-Settings })

    Update-SelectedCount
    $F.Add_Shown({
        $Script:Ui.Form.Activate()
        Announce ((T 'title') + ' ' + $Script:AppVersion + '. ' + $Script:Ui.Count.Text)
        Test-SelfUpdate
        Refresh-All
    })
    [void]$F.ShowDialog()
}

# ---------------------------------------------------------------------------
# Console
# ---------------------------------------------------------------------------
function Run-Console {
    $ids = @($Script:Statuses.Keys)
    if ($Check -or (-not $Install -and -not $All)) {
        Write-Host (TF 'checkingAll' $ids.Count)
        foreach ($a in @($Script:Cat.addons)) { $st = $Script:Statuses[[string]$a.id]; Refresh-Status $st; Write-Host ('  ' + (Get-StatusText $st)) }
        return
    }
    $todo = @()
    if ($All) {
        foreach ($a in @($Script:Cat.addons)) { $st = $Script:Statuses[[string]$a.id]; if (-not $a.infoOnly -and (Initial-Checked $st)) { $todo += [string]$a.id } }
    } else {
        foreach ($i in $Install) { foreach ($piece in ($i -split ',')) { $p = $piece.Trim(); if ($p -and $Script:Statuses.ContainsKey($p)) { $todo += $p } elseif ($p) { Write-Host "unknown addon id: $p" } } }
    }
    if ($Reinstall) { $Script:Settings.reinstall = $true }
    foreach ($id in $todo) { Refresh-Status $Script:Statuses[$id] }
    $real = @($todo | Where-Object { $st = $Script:Statuses[$_]; $st.update -or $Script:Settings.reinstall })
    if ($real.Count -eq 0) { Write-Host (T 'nothingToDo'); return }
    [void](Install-Selection $real)
}

# ---------------------------------------------------------------------------
# Demarrage
# ---------------------------------------------------------------------------
try {
    Ensure-DataDir
    Load-Settings
    Load-State
    if ($Lang) { $Script:Lang = $Lang } elseif ($Script:Settings.lang) { $Script:Lang = [string]$Script:Settings.lang } else { $Script:Lang = 'fr'; if ((Get-Culture).TwoLetterISOLanguageName -ne 'fr') { $Script:Lang = 'en' } }
    Write-Log "---- ZenqAddons $Script:AppVersion start (gui=$(-not $NoGui))"
    if ($NoGui) { try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {} } else { Write-Host (T 'loadingCatalog') }
    $Script:Cat = Load-Catalog $Catalog

    $root = $null
    if ($WowPath) { $root = Resolve-WowRoot $WowPath $Script:Cat }
    if (-not $root -and $Script:Settings.wowRoot) { $root = Resolve-WowRoot ([string]$Script:Settings.wowRoot) $Script:Cat }
    if (-not $root) {
        $found = @(Find-WowRoots $Script:Cat)
        if ($found.Count -gt 0) { $root = $found[0].root }
    }
    if (-not $root -and -not $NoGui) {
        [void][System.Windows.Forms.MessageBox]::Show((T 'noWow'), (T 'title'))
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = T 'wowFolder'
        if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $root = Resolve-WowRoot $dlg.SelectedPath $Script:Cat }
    }
    if (-not $root) { throw (T 'noWow') }
    $flavorId = $Flavor
    if (-not $flavorId) { $flavorId = [string]$Script:Settings.flavor }
    Set-Context $root $flavorId

    if ($NoGui) { Run-Console } else { Show-Gui }
    Write-Log '---- end'
} catch {
    $msg = $_.Exception.Message
    Write-Log "FATAL: $msg`n$($_.ScriptStackTrace)"
    if (-not $NoGui) { try { [void][System.Windows.Forms.MessageBox]::Show($msg, (T 'title'), [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) } catch { Write-Host $msg } }
    else { Write-Host "ERREUR : $msg" }
    exit 1
}
