# build.ps1 -- compile ZenqAddonsInstaller.exe with the C# compiler shipped in
# every Windows (.NET Framework 4.x), no SDK needed.
#   powershell -ExecutionPolicy Bypass -File installer\src\build.ps1
$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot
$installer = Split-Path $src -Parent
$out = Join-Path $installer 'ZenqAddonsInstaller.exe'
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { throw 'csc.exe (.NET Framework 4.x) not found' }
$sma = [System.Management.Automation.PSObject].Assembly.Location

# Icon: an amber disc with a Z, generated on the spot (no binary in the repo).
$ico = Join-Path $src 'zenq.ico'
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap(64, 64)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'AntiAliasGridFit'
$g.Clear([System.Drawing.Color]::Transparent)
$g.FillEllipse((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(232, 168, 95))), 2, 2, 60, 60)
$font = New-Object System.Drawing.Font('Segoe UI', 34, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$fmt = New-Object System.Drawing.StringFormat; $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
$g.DrawString('Z', $font, (New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(28, 23, 18))), (New-Object System.Drawing.RectangleF(0, 0, 64, 64)), $fmt)
$g.Dispose()
$icon = [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
$fs = [IO.File]::Create($ico); $icon.Save($fs); $fs.Close()
$bmp.Dispose()

# The script is embedded as a resource; copy it next to the sources for csc.
Copy-Item (Join-Path $installer 'ZenqAddons.ps1') (Join-Path $src 'ZenqAddons.ps1') -Force

& $csc /nologo /target:winexe /platform:anycpu /optimize+ `
    /out:"$out" `
    /win32manifest:"$(Join-Path $src 'app.manifest')" `
    /win32icon:"$ico" `
    /resource:"$(Join-Path $src 'ZenqAddons.ps1')",ZenqAddons.ps1 `
    /r:"$sma" /r:System.Windows.Forms.dll /r:System.Drawing.dll `
    "$(Join-Path $src 'Program.cs')"
if ($LASTEXITCODE -ne 0) { throw "csc failed ($LASTEXITCODE)" }
Remove-Item (Join-Path $src 'ZenqAddons.ps1') -Force
Remove-Item $ico -Force
$fi = Get-Item $out
"built $($fi.FullName) ($([math]::Round($fi.Length / 1KB)) Ko) with $csc"
