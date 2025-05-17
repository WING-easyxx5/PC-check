$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Start-Process PowerShell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

Add-Type -AssemblyName System.Net.Http

# Globale Variablen und Status
$global:scanRunning = $false
$global:webhookSent = $false
$global:scanTimeout = 300 # Timeout in Sekunden (5 Minuten)
$global:scanTimer = $null

# App-Verlauf
$global:appHistory = New-Object System.Collections.ArrayList
$global:historyFile = "$env:APPDATA\TeamAstro\history.json"

# Base64-verschleierter Discord Webhook
$webhookBase = "https://discord.com/api/webhooks/"
$encodedWebhookPart = "MTM3MzAwNDEwMjM2Mjk4ODYzNi9MZm9nYUVOeXJ5eWxNTVp4cjVDWFU3Vk5zdmZPakhtcVJPc3lZOEVxak9XQURJSGVRTGJWNnFYRS15LWRtSWwxMUFPQQ=="
$webhookUrl = $webhookBase + [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($encodedWebhookPart))

# Arrays für Scanergebnisse
$suspiciousProcesses = New-Object System.Collections.ArrayList
$suspiciousAutoStart = New-Object System.Collections.ArrayList
$suspiciousTasks = New-Object System.Collections.ArrayList
$suspiciousGtaFiles = New-Object System.Collections.ArrayList
$systemFiles = New-Object System.Collections.ArrayList
$deletedItems = New-Object System.Collections.ArrayList
$recoveredItems = New-Object System.Collections.ArrayList
$suspiciousConnections = New-Object System.Collections.ArrayList
$roamingFiles = New-Object System.Collections.ArrayList
$scanResults = New-Object System.Collections.ArrayList
$deletedFilesReport = New-Object System.Collections.ArrayList

# UI-Elemente
$tabControls = New-Object System.Collections.ArrayList
$processList = $null
$fileSystemList = $null
$deletedFilesList = $null
$autoStartList = $null
$networkList = $null
$roamingList = $null
$systemList = $null
$historyList = $null

# Scan-Status-Parameter
$scanProgress = 0
$scanSteps = 7
$scanStepProgress = 0

# Blocker-Fenster für sekundäre Bildschirme
$blockerWindows = New-Object System.Collections.ArrayList

# Alle Bildschirme erfassen
$screens = [System.Windows.Forms.Screen]::AllScreens
$primaryScreen = [System.Windows.Forms.Screen]::PrimaryScreen

# Hauptfenster erstellen (zunächst ausgeblendet)
$mainWindow = New-Object System.Windows.Forms.Form
$mainWindow.Text = "TEAM ASTRO"
$mainWindow.Size = New-Object System.Drawing.Size(900, 600)
$mainWindow.StartPosition = "CenterScreen"
$mainWindow.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 30)
$mainWindow.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedSingle
$mainWindow.MaximizeBox = $false
$mainWindow.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
$mainWindow.Visible = $false
$mainWindow.Opacity = 0

# Erstelle Blocker-Fenster für alle Bildschirme außer dem Hauptbildschirm
foreach ($screen in $screens) {
    if ($screen -ne $primaryScreen) {
        $blocker = New-Object System.Windows.Forms.Form
        $blocker.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
        $blocker.StartPosition = [System.Windows.Forms.FormStartPosition]::Manual
        $blocker.Location = $screen.Bounds.Location
        $blocker.Size = $screen.Bounds.Size
        $blocker.BackColor = [System.Drawing.Color]::Black
        $blocker.Opacity = 0.95
        $blocker.TopMost = $true
        $blocker.ShowInTaskbar = $false
        
        $blockerLabel = New-Object System.Windows.Forms.Label
        $blockerLabel.Text = "TEAM ASTRO - BILDSCHIRM GESPERRT"
        $blockerLabel.ForeColor = [System.Drawing.Color]::White
        $blockerLabel.Font = New-Object System.Drawing.Font("Impact", 24)
        $blockerLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $blockerLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
        $blocker.Controls.Add($blockerLabel)
        
        # WING Wasserzeichen hinzufügen
        $watermarkLabel = New-Object System.Windows.Forms.Label
        $watermarkLabel.Text = "WING"
        $watermarkLabel.ForeColor = [System.Drawing.Color]::FromArgb(60, 0, 0, 0) # Sehr leicht sichtbar in Schwarz
        $watermarkLabel.Font = New-Object System.Drawing.Font("Arial Black", 140, [System.Drawing.FontStyle]::Bold)
        $watermarkLabel.Size = New-Object System.Drawing.Size($blocker.Width, 200)
        $watermarkY = [math]::Floor(($blocker.Height - 200) / 2)
        $watermarkLabel.Location = New-Object System.Drawing.Point(0, $watermarkY)
        $watermarkLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
        $watermarkLabel.BackColor = [System.Drawing.Color]::Transparent
        $blocker.Controls.Add($watermarkLabel)
        
        [void]$blockerWindows.Add($blocker)
    }
}

# Splash-Screen erstellen - exakt mittig auf dem Hauptbildschirm
$splashScreen = New-Object System.Windows.Forms.Form
$splashScreen.Size = New-Object System.Drawing.Size(900, 600)
$splashScreen.FormBorderStyle = "None"
$splashScreen.BackColor = [System.Drawing.Color]::FromArgb(15, 15, 20)
$splashScreen.TopMost = $true
$splashScreen.ShowInTaskbar = $false

# Berechne die exakte Mitte des Hauptbildschirms
$screenWidth = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
$screenHeight = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
$xPos = [math]::Floor(($screenWidth - 900) / 2)
$yPos = [math]::Floor(($screenHeight - 600) / 2)
$splashScreen.Location = New-Object System.Drawing.Point($xPos, $yPos)

# Gradient für den Splash-Screen
$gradient = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.Point(0, 0)),
    (New-Object System.Drawing.Point(0, 600)),
    [System.Drawing.Color]::FromArgb(30, 30, 70),
    [System.Drawing.Color]::FromArgb(10, 10, 30))

$splashPanel = New-Object System.Windows.Forms.Panel
$splashPanel.Size = $splashScreen.Size
$splashPanel.BackColor = [System.Drawing.Color]::Transparent
$splashPanel.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.FillRectangle($gradient, 0, 0, $splashPanel.Width, $splashPanel.Height)
    
    $logoFont = New-Object System.Drawing.Font("Impact", 72)
    $textSize = $g.MeasureString("TEAM ASTRO", $logoFont)
    $x = [math]::Floor(($splashPanel.Width - $textSize.Width) / 2)
    $y = [math]::Floor(($splashPanel.Height - $textSize.Height) / 2) - 100
    
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddString("TEAM ASTRO", $logoFont.FontFamily, 1, 72, (New-Object System.Drawing.Point($x, $y)), [System.Drawing.StringFormat]::GenericDefault)
    
    $g.FillPath([System.Drawing.Brushes]::DodgerBlue, $path)
    $g.DrawPath((New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(180, 220, 255), 3)), $path)
    
    # Füge ein kleines WING Wasserzeichen zum Splash-Screen hinzu
    $watermarkFont = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold)
    $watermarkText = "WING"
    $watermarkSize = $g.MeasureString($watermarkText, $watermarkFont)
    $watermarkX = $splashPanel.Width - $watermarkSize.Width - 10
    $watermarkY = $splashPanel.Height - $watermarkSize.Height - 10
    
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(70, 255, 255, 255))
    $g.DrawString($watermarkText, $watermarkFont, $brush, $watermarkX, $watermarkY)
})
$splashScreen.Controls.Add($splashPanel)

# Lade-Text auf dem Splash-Screen
$loadingText = New-Object System.Windows.Forms.Label
$loadingText.Location = New-Object System.Drawing.Point(0, 400)
$loadingText.Size = New-Object System.Drawing.Size(900, 30)
$loadingText.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$loadingText.ForeColor = [System.Drawing.Color]::White
$loadingText.BackColor = [System.Drawing.Color]::Transparent
$loadingText.Font = New-Object System.Drawing.Font("Segoe UI", 12)
$loadingText.Text = "CHEAT SCANNER WIRD GELADEN..."
$splashPanel.Controls.Add($loadingText)

# Fortschritt-Anzeige in Prozent
$percentText = New-Object System.Windows.Forms.Label
$percentText.Location = New-Object System.Drawing.Point(0, 440)
$percentText.Size = New-Object System.Drawing.Size(900, 30)
$percentText.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$percentText.ForeColor = [System.Drawing.Color]::White
$percentText.BackColor = [System.Drawing.Color]::Transparent
$percentText.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$percentText.Text = "0%"
$splashPanel.Controls.Add($percentText)

# Lade-Balken Hintergrund
$loadingBarBg = New-Object System.Windows.Forms.Panel
$loadingBarBg.Size = New-Object System.Drawing.Size(600, 10)
$loadingBarBg.Location = New-Object System.Drawing.Point(150, 480)
$loadingBarBg.BackColor = [System.Drawing.Color]::FromArgb(40, 40, 60)
$splashPanel.Controls.Add($loadingBarBg)

# Lade-Balken Vordergrund
$loadingBar = New-Object System.Windows.Forms.Panel
$loadingBar.Size = New-Object System.Drawing.Size(0, 10)
$loadingBar.Location = New-Object System.Drawing.Point(150, 480)
$loadingBar.BackColor = [System.Drawing.Color]::DodgerBlue
$splashPanel.Controls.Add($loadingBar)

# Sternen-Animation im Hintergrund
$starField = New-Object System.Windows.Forms.PictureBox
$starField.Size = New-Object System.Drawing.Size(900, 400)
$starField.Location = New-Object System.Drawing.Point(0, 0)
$starField.BackColor = [System.Drawing.Color]::Transparent
$splashPanel.Controls.Add($starField)

$stars = @()
for ($i = 0; $i -lt 100; $i++) {
    $stars += @{
        X = Get-Random -Minimum 0 -Maximum 900
        Y = Get-Random -Minimum 0 -Maximum 400
        Size = Get-Random -Minimum 1 -Maximum 4
        Speed = Get-Random -Minimum 1 -Maximum 5
    }
}

$starTimer = New-Object System.Windows.Forms.Timer
$starTimer.Interval = 50
$starTimer.Add_Tick({
    $bitmap = New-Object System.Drawing.Bitmap(900, 400)
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $g.Clear([System.Drawing.Color]::Transparent)
    
    foreach ($star in $stars) {
        $x = $star.X
        $y = $star.Y
        $size = $star.Size
        
        $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(
            (Get-Random -Minimum 200 -Maximum 256),
            (Get-Random -Minimum 200 -Maximum 256),
            (Get-Random -Minimum 200 -Maximum 256)))
        
        $g.FillEllipse($brush, $x, $y, $size, $size)
        
        $star.Y += $star.Speed
        if ($star.Y -gt 400) {
            $star.Y = 0
            $star.X = Get-Random -Minimum 0 -Maximum 900
        }
    }
    
    $starField.Image = $bitmap
})

# Event-Handler für das Schließen des Hauptfensters
$mainWindow.Add_FormClosing({
    $splashScreen.Close()
    $starTimer.Stop()
    
    # Beende den Timeout-Timer, falls er läuft
    if ($global:scanTimer -ne $null) {
        $global:scanTimer.Stop()
        $global:scanTimer.Dispose()
        $global:scanTimer = $null
    }
    
    # Schließe alle Blocker-Fenster
    foreach ($blocker in $blockerWindows) {
        $blocker.Close()
    }
    
    # Beende nur PowerShell-Prozesse, die mit diesem Skript zusammenhängen
    $currentPID = $PID
    Get-Process | Where-Object { 
        $_.Name -like "*powershell*" -and 
        $_.Id -ne $currentPID -and 
        $_.Id -eq [System.Diagnostics.Process]::GetCurrentProcess().Id
    } | Stop-Process -Force
})

# Zeige die Blocker-Fenster für sekundäre Bildschirme
foreach ($blocker in $blockerWindows) {
    $blocker.Show()
}

# Zeige den Splash-Screen
$splashScreen.Show()
$starTimer.Start()

# Funktion zur Aktualisierung des Ladezustands
function Update-LoadingState {
    param (
        [int]$Percent,
        [string]$StatusText
    )
    
    $loadingText.Text = $StatusText
    $percentText.Text = "$Percent%"
    $loadingBar.Width = $Percent * 6
    
    # Stelle sicher, dass der Splashscreen immer TopMost und zentriert bleibt
    $splashScreen.TopMost = $true
    $screenWidth = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
    $screenHeight = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
    $xPos = [math]::Floor(($screenWidth - 900) / 2)
    $yPos = [math]::Floor(($screenHeight - 600) / 2)
    $splashScreen.Location = New-Object System.Drawing.Point($xPos, $yPos)
    
    $splashScreen.Refresh()
}

# Funktion zur Aktualisierung des Scan-Fortschritts
function Update-ScanProgress {
    param(
        [string]$message,
        [int]$step = -1,
        [int]$subStep = -1
    )
    
    if ($step -ge 0) {
        $scanProgress = [math]::Floor(($step / $scanSteps) * 100)
    }
    
    if ($subStep -ge 0) {
        $stepSize = 100 / $scanSteps
        $subStepProgress = ($subStep / 100) * $stepSize
        $scanProgress = [math]::Floor(($step / $scanSteps) * 100) + $subStepProgress
    }
    
    # Speichere den Fortschritt global
    $global:scanProgress = $scanProgress
    
    # Zeige den Fortschritt an
    $loadingText.Text = $message
    $percentText.Text = "$scanProgress%"
    $loadingBar.Width = $scanProgress * 6
    
    # Öffne das Hauptfenster bei 60% im Hintergrund
    if ($scanProgress -ge 60 -and $mainWindow.Visible -eq $false) {
        $mainWindow.Location = $splashScreen.Location
        $mainWindow.Visible = $true
        $mainWindow.Opacity = 0
    }
    
    # Stelle sicher, dass der Splashscreen immer TopMost und zentriert bleibt
    $splashScreen.TopMost = $true
    $screenWidth = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
    $screenHeight = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
    $xPos = [math]::Floor(($screenWidth - 900) / 2)
    $yPos = [math]::Floor(($screenHeight - 600) / 2)
    $splashScreen.Location = New-Object System.Drawing.Point($xPos, $yPos)
    
    $splashScreen.Refresh()
    
    # Prozessiere Windows-Nachrichten, um UI-Updates sicherzustellen
    [System.Windows.Forms.Application]::DoEvents()
}

Update-ScanProgress -message "INITIALISIERE SCANNER..." -step 0

# Hauptpanel mit Gradient-Hintergrund
$mainGradient = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.Point(0, 0)),
    (New-Object System.Drawing.Point(0, 600)),
    [System.Drawing.Color]::FromArgb(30, 30, 60),
    [System.Drawing.Color]::FromArgb(15, 15, 25))

$mainPanel = New-Object System.Windows.Forms.Panel
$mainPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$mainPanel.BackColor = [System.Drawing.Color]::Transparent
$mainPanel.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.FillRectangle($mainGradient, 0, 0, $mainPanel.Width, $mainPanel.Height)
    
    # Füge das WING Wasserzeichen zum Hauptfenster hinzu
    $watermarkFont = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold)
    $watermarkText = "WING"
    $watermarkSize = $g.MeasureString($watermarkText, $watermarkFont)
    $watermarkX = $mainPanel.Width - $watermarkSize.Width - 10
    $watermarkY = $mainPanel.Height - $watermarkSize.Height - 10
    
    $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(50, 0, 0, 0))
    $g.DrawString($watermarkText, $watermarkFont, $brush, $watermarkX, $watermarkY)
})
$mainWindow.Controls.Add($mainPanel)

# Bekannte Cheat-Prozesse und Schlüsselwörter
$knownCheatProcesses = @(
    "Cheat Engine", "CE", "CheatEngine", "AutoHotkey", "AHK", "WeMod", "Artmoney",
    "Extreme Injector", "Process Hacker", "Kiddion", "GTAHaX", "OVInject", "Xenos", 
    "Xenos64", "Process Explorer", "memory.dll", "InjectorGUI", "Osiris", "KateBot", 
    "CheatGear", "1337", "leet", "NenyoCheats", "EulenCheats", "Lena", "Lynx", "Lumia",
    "Phantom", "HamMafia", "BloodLeaks", "Infinity", "Nemesis", "Falcon", "Hyper",
    "Shadow", "Reaper", "Vacuum", "Hydra", "Phoenix", "Viper", "Spectrum", "Eclipse",
    "Impulse", "Paragon", "2Take1", "Ozark", "Disturbed", "Luna", "Cherax", "Stand", 
    "Fragment", "XCheats", "PhantomX", "Menace", "Terror", "Spooky", "Robust", "Midnight"
)

$cheatKeywords = @(
    "cheat", "hack", "inject", "trainer", "mod", "menu", "bypass", "spoof", 
    "unlock", "free", "money", "godmod", "aimbot", "wallhack", "esp", "radar",
    "noclip", "teleport", "unlimited", "modmenu", "script", "ragemp", "gta5",
    "gtav", "1337", "leet", "silent", "aim", "cash", "hax", "gta", "rage",
    "executor", "jector", "lua", "hooking", "memory", "exploit", "undetected", 
    "undetect", "noban", "no-ban", "0ban", "triggerbot", "trigger", "rcs", "recoil",
    "autoshoot", "bullet", "spread", "hitbox", "glow", "skeleton", "menu", "exploit"
)

Update-ScanProgress -message "ERSTELLE BENUTZEROBERFLÄCHE..." -step 1

# Header-Panel mit Logo
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Size = New-Object System.Drawing.Size(900, 80)
$headerPanel.BackColor = [System.Drawing.Color]::Transparent
$headerPanel.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    
    $headerFont = New-Object System.Drawing.Font("Impact", 32)
    $textSize = $g.MeasureString("TEAM ASTRO", $headerFont)
    $x = [math]::Floor(($headerPanel.Width - $textSize.Width) / 2)
    $y = [math]::Floor(($headerPanel.Height - $textSize.Height) / 2)
    
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddString("TEAM ASTRO", $headerFont.FontFamily, 1, 32, (New-Object System.Drawing.Point($x, $y)), [System.Drawing.StringFormat]::GenericDefault)
    
    $g.FillPath([System.Drawing.Brushes]::DodgerBlue, $path)
    $g.DrawPath((New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(180, 220, 255), 2)), $path)
})
$mainPanel.Controls.Add($headerPanel)

Update-ScanProgress -message "ERSTELLE TABS..." -step 2

# Tab-Control für die verschiedenen Ergebniskategorien
$resultTabs = New-Object System.Windows.Forms.TabControl
$resultTabs.Location = New-Object System.Drawing.Point(20, 90)
$resultTabs.Size = New-Object System.Drawing.Size(860, 460)
$resultTabs.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$resultTabs.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 50)
$resultTabs.ForeColor = [System.Drawing.Color]::White
$mainPanel.Controls.Add($resultTabs)

$tabPages = @()
$tabLabels = @(
    "PROZESSE", 
    "DATEISYSTEM", 
    "GELÖSCHTE DATEIEN", 
    "AUTOSTART", 
    "NETZWERK",
    "ROAMING", 
    "SYSTEM",
    "APP-VERLAUF"  # Neuer Tab für den App-Verlauf
)

Update-ScanProgress -message "ERSTELLE LISTEN..." -step 3

# Erstelle TabPages und Listen
foreach ($label in $tabLabels) {
    $tab = New-Object System.Windows.Forms.TabPage
    $tab.Text = $label
    $tab.BackColor = [System.Drawing.Color]::FromArgb(25, 25, 40)
    $tab.ForeColor = [System.Drawing.Color]::White
    $tab.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $resultTabs.Controls.Add($tab)
    $tabPages += $tab
}

foreach ($tab in $tabPages) {
    $listView = New-Object System.Windows.Forms.ListView
    $listView.Location = New-Object System.Drawing.Point(10, 10)
    $listView.Size = New-Object System.Drawing.Size(830, 405)
    $listView.View = [System.Windows.Forms.View]::Details
    $listView.FullRowSelect = $true
    $listView.GridLines = $false
    $listView.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 50)
    $listView.ForeColor = [System.Drawing.Color]::White
    $listView.Font = New-Object System.Drawing.Font("Consolas", 9)
    $listView.Scrollable = $true
    $listView.HideSelection = $false
    $listView.MultiSelect = $false
    
    $tab.Controls.Add($listView)
    [void]$tabControls.Add($listView)
}

# Konfiguriere Spalten für jede Liste
$processList = $tabControls[0]
$processList.Columns.Add("Name", 180)
$processList.Columns.Add("PID", 80)
$processList.Columns.Add("Pfad", 570)

$fileSystemList = $tabControls[1]
$fileSystemList.Columns.Add("Datei", 250)
$fileSystemList.Columns.Add("Typ", 100)
$fileSystemList.Columns.Add("Pfad", 480)

$deletedFilesList = $tabControls[2]
$deletedFilesList.Columns.Add("Datum/Zeit", 180)
$deletedFilesList.Columns.Add("Datei", 350)
$deletedFilesList.Columns.Add("Quelle", 150)
$deletedFilesList.Columns.Add("Pfad", 150)

$autoStartList = $tabControls[3]
$autoStartList.Columns.Add("Name", 200)
$autoStartList.Columns.Add("Typ", 100)
$autoStartList.Columns.Add("Pfad", 530)

$networkList = $tabControls[4]
$networkList.Columns.Add("Prozess", 180)
$networkList.Columns.Add("PID", 80)
$networkList.Columns.Add("Remote IP", 150)
$networkList.Columns.Add("Remote Port", 100)
$networkList.Columns.Add("Status", 100)
$networkList.Columns.Add("Protokoll", 100)

$roamingList = $tabControls[5]
$roamingList.Columns.Add("Name", 350)
$roamingList.Columns.Add("Typ", 150)
$roamingList.Columns.Add("Größe (KB)", 330)

$systemList = $tabControls[6]
$systemList.Columns.Add("Komponente", 200)
$systemList.Columns.Add("Status", 100)
$systemList.Columns.Add("Details", 530)

# Neue App-Verlauf Liste
$historyList = $tabControls[7]
$historyList.Columns.Add("Datum/Zeit", 180)
$historyList.Columns.Add("Ergebnis", 150) 
$historyList.Columns.Add("Verdächtige Elemente", 200)
$historyList.Columns.Add("Details", 300)

Update-ScanProgress -message "ERSTELLE BUTTONS..." -step 4

# Scan-Button
$scanBtn = New-Object System.Windows.Forms.Button
$scanBtn.Location = New-Object System.Drawing.Point(350, 560)
$scanBtn.Size = New-Object System.Drawing.Size(200, 30)
$scanBtn.Text = "SCAN STARTEN"
$scanBtn.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$scanBtn.ForeColor = [System.Drawing.Color]::White
$scanBtn.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$scanBtn.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$scanBtn.FlatAppearance.BorderSize = 0
$mainPanel.Controls.Add($scanBtn)

# Status-Label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(20, 560)
$statusLabel.Size = New-Object System.Drawing.Size(320, 30)
$statusLabel.Text = "Automatischer Scan läuft..."
$statusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$statusLabel.ForeColor = [System.Drawing.Color]::White
$statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$mainPanel.Controls.Add($statusLabel)

Update-ScanProgress -message "DEFINIERE FUNKTIONEN..." -step 5

# Funktionen für den App-Verlauf
function Initialize-AppHistory {
    # Erstelle Verzeichnis falls nicht vorhanden
    $historyDir = Split-Path -Parent $global:historyFile
    if (-not (Test-Path $historyDir)) {
        New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
    }
    
    # Lade gespeicherten Verlauf oder erstelle neuen
    if (Test-Path $global:historyFile) {
        try {
            $history = Get-Content -Path $global:historyFile -Raw | ConvertFrom-Json
            $global:appHistory.Clear()
            foreach ($entry in $history) {
                [void]$global:appHistory.Add($entry)
            }
        } catch {
            # Bei fehlerhaftem Verlauf, setze zurück
            $global:appHistory.Clear()
        }
    }
}

function Save-AppHistory {
    try {
        $historyDir = Split-Path -Parent $global:historyFile
        if (-not (Test-Path $historyDir)) {
            New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
        }
        
        $global:appHistory | ConvertTo-Json -Depth 3 | Set-Content -Path $global:historyFile -Force
    } catch {
        # Fehler beim Speichern, ignorieren
    }
}

function Add-HistoryEntry {
    param (
        [string]$result,
        [int]$suspiciousCount,
        [string]$details
    )
    
    $entry = [PSCustomObject]@{
        DateTime = Get-Date -Format "dd.MM.yyyy HH:mm:ss"
        Result = $result
        SuspiciousCount = $suspiciousCount
        Details = $details
    }
    
    # Füge neuen Eintrag hinzu (begrenze auf 100 Einträge)
    [void]$global:appHistory.Add($entry)
    if ($global:appHistory.Count -gt 100) {
        $global:appHistory.RemoveAt(0)
    }
    
    # Speichere den Verlauf
    Save-AppHistory
    
    # Aktualisiere die Anzeige
    Update-HistoryDisplay
}

function Update-HistoryDisplay {
    $historyList.Items.Clear()
    
    foreach ($entry in $global:appHistory) {
        $item = New-Object System.Windows.Forms.ListViewItem
        $item.Text = $entry.DateTime
        [void]$item.SubItems.Add($entry.Result)
        [void]$item.SubItems.Add($entry.SuspiciousCount.ToString())
        [void]$item.SubItems.Add($entry.Details)
        
        if ($entry.Result -eq "Verdächtig") {
            $item.ForeColor = [System.Drawing.Color]::Red
        } elseif ($entry.Result -eq "Sauber") {
            $item.ForeColor = [System.Drawing.Color]::Green
        }
        
        [void]$historyList.Items.Add($item)
    }
}

# Funktionen zum Hinzufügen von Items zu den Listen
function AddProcessItem($name, $processId, $path, $isSuspicious = $true) {
    [void]$scanResults.Add("PROZESS: $name (PID: $processId) - $path")
    
    $item = New-Object System.Windows.Forms.ListViewItem
    $item.Text = $name
    [void]$item.SubItems.Add("$processId")
    
    $safePath = if ($path -eq $null) { "Unbekannt" } else { "$path" }
    [void]$item.SubItems.Add($safePath)
    
    if ($isSuspicious) {
        $item.ForeColor = [System.Drawing.Color]::Red
    }
    
    [void]$processList.Items.Add($item)
    return $item
}

function AddFileItem($name, $type, $path, $isSuspicious = $true) {
    [void]$scanResults.Add("DATEI: $name ($type) - $path")
    
    $item = New-Object System.Windows.Forms.ListViewItem
    $item.Text = $name
    [void]$item.SubItems.Add("$type")
    
    $safePath = if ($path -eq $null) { "Unbekannt" } else { "$path" }
    [void]$item.SubItems.Add($safePath)
    
    if ($isSuspicious) {
        $item.ForeColor = [System.Drawing.Color]::Red
    }
    
    [void]$fileSystemList.Items.Add($item)
    return $item
}

function AddDeletedItem($name, $source, $path, $time, $isSuspicious = $true) {
    # Formatierter Zeitstempel für den Report
    $timeDisplay = if ($time -is [DateTime]) {
        $time.ToString("dd.MM.yyyy HH:mm:ss")
    } elseif ($time -eq "Innerhalb 24h") {
        $(Get-Date).ToString("dd.MM.yyyy") + " (Innerhalb 24h)"
    } else {
        $time
    }
    
    # Für den gelöschte Dateien Bericht mit Zeitstempel
    [void]$deletedFilesReport.Add("$timeDisplay - $name (Quelle: $source) - $path")
    
    $item = New-Object System.Windows.Forms.ListViewItem
    $item.Text = $timeDisplay
    [void]$item.SubItems.Add($name)
    [void]$item.SubItems.Add($source)
    [void]$item.SubItems.Add($path)
    
    if ($isSuspicious) {
        $item.ForeColor = [System.Drawing.Color]::Red
    }
    
    [void]$deletedFilesList.Items.Insert(0, $item)
    return $item
}

function AddRoamingItem($name, $type, $size, $isSuspicious = $false) {
    [void]$scanResults.Add("ROAMING: $name (Typ: $type, Größe: $size KB)")
    
    $item = New-Object System.Windows.Forms.ListViewItem
    $item.Text = $name
    [void]$item.SubItems.Add("$type")
    [void]$item.SubItems.Add("$size")
    
    if ($isSuspicious) {
        $item.ForeColor = [System.Drawing.Color]::Red
    }
    
    [void]$roamingList.Items.Add($item)
    return $item
}

function AddAutoStartItem($name, $type, $command, $isSuspicious = $true) {
    [void]$scanResults.Add("AUTOSTART: $name ($type) - $command")
    
    $item = New-Object System.Windows.Forms.ListViewItem
    $item.Text = $name
    [void]$item.SubItems.Add("$type")
    [void]$item.SubItems.Add("$command")
    
    if ($isSuspicious) {
        $item.ForeColor = [System.Drawing.Color]::Red
    }
    
    [void]$autoStartList.Items.Add($item)
    return $item
}

function AddNetworkItem($name, $processId, $remoteIP, $remotePort, $status, $protocol, $isSuspicious = $true) {
    [void]$scanResults.Add("NETZWERK: $name (PID: $processId) - Verbunden mit ${remoteIP}:${remotePort} - Status: $status, Protokoll: $protocol")
    
    $statusStr = "$status"
    
    $item = New-Object System.Windows.Forms.ListViewItem
    $item.Text = $name
    [void]$item.SubItems.Add("$processId")
    [void]$item.SubItems.Add("$remoteIP")
    [void]$item.SubItems.Add("$remotePort")
    [void]$item.SubItems.Add($statusStr)
    [void]$item.SubItems.Add("$protocol")
    
    if ($isSuspicious) {
        $item.ForeColor = [System.Drawing.Color]::Red
    }
    
    [void]$networkList.Items.Add($item)
    return $item
}

function AddSystemItem($component, $status, $details, $isSuspicious = $true) {
    [void]$scanResults.Add("SYSTEM: $component - Status: $status - Details: $details")
    
    $statusStr = "$status"
    
    $item = New-Object System.Windows.Forms.ListViewItem
    $item.Text = $component
    [void]$item.SubItems.Add($statusStr)
    [void]$item.SubItems.Add("$details")
    
    if ($isSuspicious) {
        $item.ForeColor = [System.Drawing.Color]::Red
    }
    
    [void]$systemList.Items.Add($item)
    return $item
}

# Hilfsfunktionen zur Erkennung verdächtiger Namen
function IsRandomName($name) {
    return ($name -match "^[a-f0-9]{6,}$" -or $name -match "^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$")
}

function IsSuspiciousName($name) {
    $basename = [System.IO.Path]::GetFileNameWithoutExtension($name).ToLower()
    
    if (IsRandomName $basename) { return $true }
    
    foreach ($keyword in $cheatKeywords) {
        if ($basename -like "*$keyword*") { return $true }
    }
    
    return $false
}

# Scan-Funktionen
function ScanProcesses {
    [void]$scanResults.Add("PROZESS-ANALYSE:")
    [void]$scanResults.Add("---------------")
    
    $runningProcesses = Get-Process | Select-Object -Property Name, Id, Path, Company, Description
    
    foreach ($process in $runningProcesses) {
        $isCheat = $false
        $processName = $process.Name.ToLower()
        
        foreach ($knownCheat in $knownCheatProcesses) {
            if ($processName -like "*$($knownCheat.ToLower())*") {
                $isCheat = $true
                break
            }
        }
        
        if (-not $isCheat) {
            foreach ($keyword in $cheatKeywords) {
                if ($processName -like "*$keyword*") {
                    $isCheat = $true
                    break
                }
            }
        }
        
        if (-not $isCheat -and $process.Path -ne $null) {
            if ($process.Path -like "*\Temp\*" -or 
                $process.Path -like "*\AppData\Local\Temp\*" -or 
                $process.Path -like "*\Users\Public\*") {
                $isCheat = $true
            }
            
            if (-not $isCheat -and (IsRandomName $process.Name)) {
                $isCheat = $true
            }
        }
        
        if ($isCheat) {
            [void]$suspiciousProcesses.Add($process)
            AddProcessItem $process.Name $process.Id.ToString() $process.Path
        }
    }
    
    if ($suspiciousProcesses.Count -eq 0) {
        [void]$scanResults.Add("Keine verdächtigen Prozesse gefunden.")
    }
    
    [void]$scanResults.Add("")
}

function ScanFileSystem {
    [void]$scanResults.Add("DATEISYSTEM-ANALYSE:")
    [void]$scanResults.Add("------------------")
    
    $gtaPaths = @(
        "$env:USERPROFILE\Documents\Rockstar Games\GTA V",
        "${env:ProgramFiles(x86)}\Steam\steamapps\common\Grand Theft Auto V",
        "$env:ProgramFiles\Rockstar Games\Grand Theft Auto V",
        "$env:ProgramFiles\Epic Games\GTAV",
        "D:\Steam\steamapps\common\Grand Theft Auto V",
        "E:\Steam\steamapps\common\Grand Theft Auto V",
        "F:\Steam\steamapps\common\Grand Theft Auto V",
        "D:\Games\Grand Theft Auto V",
        "E:\Games\Grand Theft Auto V",
        "F:\Games\Grand Theft Auto V",
        "C:\Games\Grand Theft Auto V",
        "C:\Program Files\Rockstar Games\Grand Theft Auto V",
        "C:\Program Files (x86)\Rockstar Games\Grand Theft Auto V"
    )
    
    $rageMpPaths = @(
        "$env:LOCALAPPDATA\RAGE MP",
        "$env:USERPROFILE\Documents\RAGE MP",
        "$env:PROGRAMFILES\RAGE MP",
        "${env:PROGRAMFILES(X86)}\RAGE MP",
        "D:\RAGE MP",
        "E:\RAGE MP",
        "F:\RAGE MP",
        "C:\RAGE MP"
    )
    
    $suspiciousExtensions = @(".asi", ".dll", ".lua", ".ini", ".hook", ".exe", ".bytes")
    
    foreach ($path in $gtaPaths) {
        if (Test-Path $path) {
            [void]$scanResults.Add("GTA V Installation gefunden: $path")
            try {
                $files = Get-ChildItem -Path $path -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
                    $ext = [System.IO.Path]::GetExtension($_.Name).ToLower()
                    return $suspiciousExtensions -contains $ext
                }
                
                foreach ($file in $files) {
                    $isSuspicious = $false
                    $fileName = $file.Name.ToLower()
                    
                    if (IsSuspiciousName $fileName) {
                        $isSuspicious = $true
                    } else {
                        $content = $null
                        try {
                            if ($file.Length -lt 1MB) {
                                $content = [System.IO.File]::ReadAllText($file.FullName)
                                foreach ($keyword in $cheatKeywords) {
                                    if ($content -match $keyword) {
                                        $isSuspicious = $true
                                        break
                                    }
                                }
                            }
                        } catch {}
                    }
                    
                    if ($isSuspicious) {
                        [void]$suspiciousGtaFiles.Add($file)
                        AddFileItem $file.Name $file.Extension.Substring(1).ToUpper() $file.FullName
                    }
                }
            } catch {
                # Fehlerbehandlung - ignorieren und weitermachen
                [void]$scanResults.Add("Fehler beim Scannen von $path`: $_")
            }
        }
    }
    
    foreach ($path in $rageMpPaths) {
        if (Test-Path $path) {
            [void]$scanResults.Add("RAGE MP Installation gefunden: $path")
            try {
                $files = Get-ChildItem -Path $path -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
                    $ext = [System.IO.Path]::GetExtension($_.Name).ToLower()
                    return $suspiciousExtensions -contains $ext
                }
                
                foreach ($file in $files) {
                    $isSuspicious = $false
                    $fileName = $file.Name.ToLower()
                    
                    if (IsSuspiciousName $fileName) {
                        $isSuspicious = $true
                    } else {
                        $content = $null
                        try {
                            if ($file.Length -lt 1MB) {
                                $content = [System.IO.File]::ReadAllText($file.FullName)
                                foreach ($keyword in $cheatKeywords) {
                                    if ($content -match $keyword) {
                                        $isSuspicious = $true
                                        break
                                    }
                                }
                            }
                        } catch {}
                    }
                    
                    if ($isSuspicious) {
                        [void]$suspiciousGtaFiles.Add($file)
                        AddFileItem $file.Name $file.Extension.Substring(1).ToUpper() $file.FullName
                    }
                }
            } catch {
                # Fehlerbehandlung - ignorieren und weitermachen
                [void]$scanResults.Add("Fehler beim Scannen von $path`: $_")
            }
        }
    }
    
    $commonHidingPaths = @(
        "$env:APPDATA",
        "$env:LOCALAPPDATA",
        "$env:TEMP",
        "$env:USERPROFILE\AppData\Local\Temp",
        "$env:USERPROFILE\Downloads",
        "$env:USERPROFILE\Documents"
    )
    
    foreach ($path in $commonHidingPaths) {
        if (Test-Path $path) {
            try {
                $files = Get-ChildItem -Path $path -Recurse -File -ErrorAction SilentlyContinue -Force | Where-Object {
                    $ext = [System.IO.Path]::GetExtension($_.Name).ToLower()
                    return ($suspiciousExtensions -contains $ext) -and
                           (($_.Attributes -band [System.IO.FileAttributes]::Hidden) -eq [System.IO.FileAttributes]::Hidden -or
                            (IsRandomName $_.Name))
                }
                
                foreach ($file in $files) {
                    $isSuspicious = $false
                    $fileName = $file.Name.ToLower()
                    
                    if (IsRandomName $fileName) {
                        $isSuspicious = $true
                    }
                    
                    foreach ($keyword in $cheatKeywords) {
                        if ($fileName -like "*$keyword*") {
                            $isSuspicious = $true
                            break
                        }
                    }
                    
                    if (-not $isSuspicious) {
                        $content = $null
                        try {
                            if ($file.Length -lt 1MB) {
                                $content = [System.IO.File]::ReadAllText($file.FullName)
                                foreach ($keyword in $cheatKeywords) {
                                    if ($content -match $keyword) {
                                        $isSuspicious = $true
                                        break
                                    }
                                }
                            }
                        } catch {}
                    }
                    
                    if ($isSuspicious) {
                        [void]$systemFiles.Add($file)
                        AddFileItem $file.Name $file.Extension.Substring(1).ToUpper() $file.FullName
                    }
                }
            } catch {
                # Fehlerbehandlung - ignorieren und weitermachen
                [void]$scanResults.Add("Fehler beim Scannen von $path`: $_")
            }
        }
    }
    
    if ($suspiciousGtaFiles.Count -eq 0 -and $systemFiles.Count -eq 0) {
        [void]$scanResults.Add("Keine verdächtigen Dateien gefunden.")
    }
    
    [void]$scanResults.Add("")
}

function ScanRoaming {
    [void]$scanResults.Add("ROAMING ORDNER ANALYSE:")
    [void]$scanResults.Add("----------------------")
    
    $roamingPath = "$env:APPDATA"
    if (Test-Path $roamingPath) {
        [void]$scanResults.Add("Roaming-Ordner: $roamingPath")
        
        # Nur Dateien und Ordner direkt im Roaming-Verzeichnis anzeigen, keine Rekursion
        try {
            $roamingItems = Get-ChildItem -Path $roamingPath -Force -ErrorAction SilentlyContinue
            
            if ($roamingItems) {
                foreach ($item in $roamingItems) {
                    $itemName = $item.Name
                    $itemType = if ($item.PSIsContainer) { "Ordner" } else { "Datei" }
                    $sizeKB = if ($item.PSIsContainer) { "-" } else { [math]::Round($item.Length / 1KB, 2) }
                    
                    # Auf verdächtige Namen prüfen
                    $isSuspicious = $false
                    foreach ($keyword in $cheatKeywords) {
                        if ($itemName -like "*$keyword*") {
                            $isSuspicious = $true
                            break
                        }
                    }
                    
                    if (IsRandomName $itemName) {
                        $isSuspicious = $true
                    }
                    
                    # Zum roamingFiles hinzufügen
                    [void]$roamingFiles.Add([PSCustomObject]@{
                        Name = $itemName
                        Type = $itemType
                        Size = $sizeKB
                        Path = $item.FullName
                    })
                    
                    # Zur Anzeige hinzufügen
                    AddRoamingItem $itemName $itemType $sizeKB $isSuspicious
                }
            }
        } catch {
            # Fehlerbehandlung - ignorieren und weitermachen
            [void]$scanResults.Add("Fehler beim Scannen des Roaming-Ordners: $_")
        }
    }
    
    [void]$scanResults.Add("")
}

function ScanDeletedFiles {
    [void]$scanResults.Add("GELÖSCHTE DATEIEN ANALYSE:")
    [void]$scanResults.Add("------------------------")
    
    # Header für den speziellen Gelöschte-Dateien-Bericht
    [void]$deletedFilesReport.Add("TEAM ASTRO - GELÖSCHTE DATEIEN BERICHT")
    [void]$deletedFilesReport.Add("=======================================")
    [void]$deletedFilesReport.Add("Computer: $env:COMPUTERNAME")
    [void]$deletedFilesReport.Add("Benutzer: $env:USERNAME")
    [void]$deletedFilesReport.Add("Datum/Zeit: $(Get-Date -Format 'dd.MM.yyyy HH:mm:ss')")
    [void]$deletedFilesReport.Add("")
    [void]$deletedFilesReport.Add("GELÖSCHTE DATEIEN:")
    [void]$deletedFilesReport.Add("----------------")
    
    $oneHourAgo = (Get-Date).AddHours(-1)
    [void]$scanResults.Add("Überprüfe Dateien, die seit $($oneHourAgo.ToString('HH:mm:ss')) gelöscht wurden")
    
    # Alle gelöschten Dateien vom PC sammeln
    try {
        # 1. Papierkorb
        $recBin = (New-Object -ComObject Shell.Application).NameSpace(0xA)
        try {
            foreach ($item in $recBin.Items()) {
                $deletedTime = $recBin.GetDetailsOf($item, 2)
                $itemName = $item.Name
                $itemPath = $recBin.GetDetailsOf($item, 1)
                
                $isSuspicious = $false
                $fileName = $itemName.ToLower()
                $ext = [System.IO.Path]::GetExtension($fileName)
                
                if ($ext -in @(".exe", ".dll", ".asi", ".lua")) {
                    $isSuspicious = $true
                }
                
                if (-not $isSuspicious) {
                    foreach ($keyword in $cheatKeywords) {
                        if ($fileName -like "*$keyword*" -or $itemPath -like "*$keyword*") {
                            $isSuspicious = $true
                            break
                        }
                    }
                }
                
                if (-not $isSuspicious -and (IsRandomName ([System.IO.Path]::GetFileNameWithoutExtension($fileName)))) {
                    $isSuspicious = $true
                }
                
                [void]$deletedItems.Add([PSCustomObject]@{
                    Name = $itemName
                    Path = $itemPath
                    DeletedTime = $deletedTime
                    Source = "Papierkorb"
                })
                AddDeletedItem $itemName "Papierkorb" $itemPath $deletedTime $isSuspicious
            }
        } catch {}
        
        # 2. NTFS Journal auswerten
        try {
            $usnOutput = & fsutil usn readjournal C: csv | Select-Object -First 5000
            
            foreach ($line in $usnOutput) {
                if ($line -match "Delete" -and $line -match '(.*\.(dll|asi|exe|lua))') {
                    $fileName = $matches[1]
                    
                    $isSuspicious = $false
                    $baseName = [System.IO.Path]::GetFileName($fileName).ToLower()
                    
                    foreach ($keyword in $cheatKeywords) {
                        if ($baseName -like "*$keyword*") {
                            $isSuspicious = $true
                            break
                        }
                    }
                    
                    if (-not $isSuspicious -and (IsRandomName ([System.IO.Path]::GetFileNameWithoutExtension($baseName)))) {
                        $isSuspicious = $true
                    }
                    
                    $currentDate = Get-Date
                    
                    [void]$recoveredItems.Add([PSCustomObject]@{
                        Name = $baseName
                        Path = $fileName
                        DeletedTime = $currentDate
                        Source = "NTFS Journal"
                    })
                    AddDeletedItem $baseName "NTFS Journal" $fileName $currentDate $isSuspicious
                }
            }
        } catch {}
        
        # 3. Temp-Ordner durchsuchen
        $tempFolders = @(
            "$env:TEMP",
            "$env:USERPROFILE\AppData\Local\Temp",
            "$env:WINDIR\Temp"
        )
        
        foreach ($folder in $tempFolders) {
            if (Test-Path $folder) {
                try {
                    $deletedTempFiles = Get-ChildItem -Path "$folder\*" -Include "*.bak", "*.old", "*.tmp" -File -ErrorAction SilentlyContinue | 
                        Where-Object { $_.LastWriteTime -gt $oneHourAgo }
                    
                    foreach ($file in $deletedTempFiles) {
                        $content = $null
                        $isSuspicious = $false
                        
                        try {
                            if ($file.Length -lt 1MB) {
                                $content = [System.IO.File]::ReadAllText($file.FullName)
                                foreach ($keyword in $cheatKeywords) {
                                    if ($content -match $keyword) {
                                        $isSuspicious = $true
                                        break
                                    }
                                }
                            }
                        } catch {}
                        
                        [void]$recoveredItems.Add([PSCustomObject]@{
                            Name = $file.Name
                            Path = $file.FullName
                            DeletedTime = $file.LastWriteTime
                            Source = "Temp-Ordner"
                        })
                        AddDeletedItem $file.Name "Temp-Ordner" $file.FullName $file.LastWriteTime $isSuspicious
                    }
                } catch {}
            }
        }
        
        # 4. Prefetch-Dateien auswerten
        try {
            $prefetchPath = "$env:WINDIR\Prefetch"
            if (Test-Path $prefetchPath) {
                $prefetchFiles = Get-ChildItem -Path $prefetchPath -Filter "*.pf" -ErrorAction SilentlyContinue |
                    Where-Object { $_.LastWriteTime -gt $oneHourAgo }
                
                foreach ($file in $prefetchFiles) {
                    $fileName = $file.BaseName
                    $isSuspicious = $false
                    
                    foreach ($keyword in $cheatKeywords) {
                        if ($fileName -like "*$keyword*") {
                            $isSuspicious = $true
                            break
                        }
                    }
                    
                    foreach ($cheatProcess in $knownCheatProcesses) {
                        if ($fileName -like "*$cheatProcess*") {
                            $isSuspicious = $true
                            break
                        }
                    }
                    
                    [void]$recoveredItems.Add([PSCustomObject]@{
                        Name = $file.Name
                        Path = $file.FullName
                        DeletedTime = $file.LastWriteTime
                        Source = "Prefetch"
                    })
                    AddDeletedItem $file.Name "Prefetch" $file.FullName $file.LastWriteTime $isSuspicious
                }
            }
        } catch {}
    } catch {
        # Fehlerbehandlung - Scan fortsetzen
        [void]$scanResults.Add("Fehler beim Scannen gelöschter Dateien: $_")
    }
    
    if ($deletedItems.Count -eq 0 -and $recoveredItems.Count -eq 0) {
        [void]$scanResults.Add("Keine kürzlich gelöschten Dateien in der letzten Stunde gefunden.")
        [void]$deletedFilesReport.Add("Keine kürzlich gelöschten Dateien in der letzten Stunde gefunden.")
    }
    
    [void]$scanResults.Add("")
    [void]$deletedFilesReport.Add("")
}

function ScanRegistry {
    [void]$scanResults.Add("REGISTRY & AUTOSTART ANALYSE:")
    [void]$scanResults.Add("---------------------------")
    
    $autoStartLocations = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run"
    )
    
    try {
        foreach ($location in $autoStartLocations) {
            if (Test-Path $location) {
                $entries = Get-ItemProperty -Path $location -ErrorAction SilentlyContinue
                if ($entries -ne $null) {
                    $properties = $entries.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" }
                    
                    foreach ($prop in $properties) {
                        $entryName = $prop.Name
                        $entryValue = $prop.Value
                        
                        $isSuspicious = $false
                        
                        if ($entryName -match "^[a-zA-Z0-9]{8}$" -or (IsRandomName $entryName)) {
                            $isSuspicious = $true
                        }
                        
                        if (-not $isSuspicious) {
                            foreach ($keyword in $cheatKeywords) {
                                if ($entryName -like "*$keyword*" -or $entryValue -like "*$keyword*") {
                                    $isSuspicious = $true
                                    break
                                }
                            }
                        }
                        
                        if (-not $isSuspicious) {
                            if ($entryValue -like "*\Temp\*" -or 
                                $entryValue -like "*\AppData\Local\Temp\*" -or
                                $entryValue -like "*\Users\Public\*") {
                                $isSuspicious = $true
                            }
                        }
                        
                        if ($isSuspicious) {
                            [void]$suspiciousAutoStart.Add([PSCustomObject]@{
                                Name = $entryName
                                Location = $location
                                Value = $entryValue
                            })
                            
                            $locationName = $location -replace "HKLM:\\", "HKLM\" -replace "HKCU:\\", "HKCU\"
                            AddAutoStartItem $entryName "Registry" "$locationName - $entryValue"
                        }
                    }
                }
            }
        }
        
        $shellExtLocations = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved",
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Approved"
        )
        
        foreach ($location in $shellExtLocations) {
            if (Test-Path $location) {
                $entries = Get-ItemProperty -Path $location -ErrorAction SilentlyContinue
                if ($entries -ne $null) {
                    $properties = $entries.PSObject.Properties | Where-Object { $_.Name -notlike "PS*" }
                    
                    foreach ($prop in $properties) {
                        $entryName = $prop.Name
                        $entryValue = $prop.Value
                        
                        $isSuspicious = $false
                        
                        if ($entryName -match "^{[a-fA-F0-9]{8}-([a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}}$") {
                            foreach ($keyword in $cheatKeywords) {
                                if ($entryValue -like "*$keyword*") {
                                    $isSuspicious = $true
                                    break
                                }
                            }
                        }
                        
                        if ($isSuspicious) {
                            [void]$suspiciousAutoStart.Add([PSCustomObject]@{
                                Name = $entryName
                                Location = $location
                                Value = $entryValue
                            })
                            
                            $locationName = $location -replace "HKLM:\\", "HKLM\" -replace "HKCU:\\", "HKCU\"
                            AddAutoStartItem $entryName "Shell Extension" "$locationName - $entryValue"
                        }
                    }
                }
            }
        }
        
        $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { 
            $_.TaskPath -notlike "\Microsoft\*" -and $_.State -ne "Disabled" 
        }
        
        foreach ($task in $tasks) {
            $isSuspicious = $false
            $taskNameLower = $task.TaskName.ToLower()
            
            if ($taskNameLower -match "^[a-zA-Z0-9]{6,}$" -or (IsRandomName $task.TaskName)) {
                $isSuspicious = $true
            }
            
            if (-not $isSuspicious) {
                foreach ($keyword in $cheatKeywords) {
                    if ($taskNameLower -like "*$keyword*") {
                        $isSuspicious = $true
                        break
                    }
                }
            }
            
            if ($isSuspicious) {
                [void]$suspiciousTasks.Add($task)
                
                $taskDetails = "Pfad: $($task.TaskPath)"
                try {
                    $taskInfo = Get-ScheduledTaskInfo -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue
                    if ($taskInfo) {
                        $taskDetails += ", Letzte Ausführung: $($taskInfo.LastRunTime), Nächste Ausführung: $($taskInfo.NextRunTime)"
                    }
                } catch {}
                
                AddAutoStartItem $task.TaskName "Task" $taskDetails
            }
        }
        
        $services = Get-WmiObject -Class Win32_Service -ErrorAction SilentlyContinue | Where-Object {
            $_.StartMode -eq "Auto" -and $_.State -eq "Running" -and $_.PathName -notlike "*\Windows\*"
        }
        
        foreach ($service in $services) {
            $isSuspicious = $false
            $serviceNameLower = $service.Name.ToLower()
            $displayNameLower = $service.DisplayName.ToLower()
            $pathLower = $service.PathName.ToLower()
            
            if (IsRandomName $serviceNameLower) {
                $isSuspicious = $true
            }
            
            if (-not $isSuspicious) {
                foreach ($keyword in $cheatKeywords) {
                    if ($serviceNameLower -like "*$keyword*" -or $displayNameLower -like "*$keyword*" -or $pathLower -like "*$keyword*") {
                        $isSuspicious = $true
                        break
                    }
                }
            }
            
            if (-not $isSuspicious -and ($pathLower -like "*\temp\*" -or $pathLower -like "*\appdata\local\temp\*")) {
                $isSuspicious = $true
            }
            
            if ($isSuspicious) {
                [void]$suspiciousAutoStart.Add([PSCustomObject]@{
                    Name = $service.Name
                    Location = "Services"
                    Value = $service.PathName
                })
                
                AddAutoStartItem $service.DisplayName "Service" $service.PathName
            }
        }
    } catch {
        # Fehlerbehandlung - Scan fortsetzen
        [void]$scanResults.Add("Fehler beim Scannen der Registry: $_")
    }
    
    if ($suspiciousAutoStart.Count -eq 0 -and $suspiciousTasks.Count -eq 0) {
        [void]$scanResults.Add("Keine verdächtigen Autostart-Einträge gefunden.")
    }
    
    [void]$scanResults.Add("")
}

function ScanNetwork {
    [void]$scanResults.Add("NETZWERK ANALYSE:")
    [void]$scanResults.Add("----------------")
    
    try {
        $connections = Get-NetTCPConnection -ErrorAction SilentlyContinue | 
            Where-Object { $_.State -eq "Established" }
        
        $suspiciousPorts = @(1337, 6666, 8888, 9999, 1338, 1444, 6969, 1111, 2222, 3333, 4444, 5555, 7777)
        
        foreach ($conn in $connections) {
            $isSuspicious = $false
            
            if ($conn.RemotePort -in $suspiciousPorts) {
                $isSuspicious = $true
            }
            
            $remoteIP = $conn.RemoteAddress
            $dnsResolve = $null
            try {
                $dnsResolve = [System.Net.Dns]::GetHostEntry($remoteIP).HostName
                if ($dnsResolve) {
                    $domain = $dnsResolve.ToLower()
                    foreach ($keyword in $cheatKeywords) {
                        if ($domain -like "*$keyword*") {
                            $isSuspicious = $true
                            break
                        }
                    }
                }
            } catch {}
            
            if (-not $isSuspicious) {
                try {
                    $process = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
                    $procName = if ($process) { $process.Name.ToLower() } else { "unknown" }
                    
                    foreach ($keyword in $cheatKeywords) {
                        if ($procName -like "*$keyword*") {
                            $isSuspicious = $true
                            break
                        }
                    }
                    
                    if (-not $isSuspicious -and $procName -ne "unknown") {
                        foreach ($suspProc in $suspiciousProcesses) {
                            if ($suspProc.Id -eq $conn.OwningProcess) {
                                $isSuspicious = $true
                                break
                            }
                        }
                    }
                } catch {}
            }
            
            if ($isSuspicious) {
                $processName = "Unbekannt"
                try {
                    $process = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
                    if ($process) { $processName = $process.Name }
                } catch {}
                
                [void]$suspiciousConnections.Add($conn)
                
                $dnsInfo = ""
                if ($dnsResolve) {
                    $dnsInfo = " ($dnsResolve)"
                }
                
                AddNetworkItem $processName $conn.OwningProcess.ToString() "$($conn.RemoteAddress)$dnsInfo" $conn.RemotePort $conn.State "TCP"
            }
        }
        
        $udpStats = Get-NetUDPEndpoint -ErrorAction SilentlyContinue
        foreach ($stat in $udpStats) {
            if ($stat.LocalPort -in $suspiciousPorts) {
                try {
                    $process = Get-Process -Id $stat.OwningProcess -ErrorAction SilentlyContinue
                    $processName = if ($process) { $process.Name } else { "Unbekannt" }
                    
                    [void]$suspiciousConnections.Add($stat)
                    AddNetworkItem $processName $stat.OwningProcess.ToString() "0.0.0.0" $stat.LocalPort "Listening" "UDP"
                } catch {}
            }
        }
    } catch {
        # Fehlerbehandlung - Scan fortsetzen
        [void]$scanResults.Add("Fehler beim Scannen des Netzwerks: $_")
    }
    
    if ($suspiciousConnections.Count -eq 0) {
        [void]$scanResults.Add("Keine verdächtigen Netzwerkverbindungen gefunden.")
    }
    
    [void]$scanResults.Add("")
}

function ScanSystem {
    [void]$scanResults.Add("SYSTEM ANALYSE:")
    [void]$scanResults.Add("--------------")
    
    try {
        $anticheatServices = @("BEService", "EasyAntiCheat", "PunkBuster", "BattlEye", "Vanguard")
        
        foreach ($service in $anticheatServices) {
            $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
            
            if ($svc) {
                AddSystemItem "Anti-Cheat Service" $svc.Status "$($svc.Name) - $($svc.DisplayName)" ($svc.Status -ne "Running")
            }
        }
        
        try {
            $memory = Get-WmiObject Win32_OperatingSystem
            $memoryUsage = [math]::Round(($memory.TotalVisibleMemorySize - $memory.FreePhysicalMemory) / 1024, 2)
            
            if ($memoryUsage -gt 4096) {
                AddSystemItem "Memory Usage" "Hoch" "$memoryUsage MB RAM in Verwendung" $false
            } else {
                AddSystemItem "Memory Usage" "Normal" "$memoryUsage MB RAM in Verwendung" $false
            }
        } catch {}
        
        try {
            $gameProcesses = Get-Process -Name GTA5, GTAV, GTAVLauncher -ErrorAction SilentlyContinue
            
            if ($gameProcesses) {
                $runningGames = $gameProcesses | ForEach-Object { "$($_.Name) (PID: $($_.Id))" }
                AddSystemItem "GTA 5 Prozesse" "Aktiv" ($runningGames -join ", ") $false
            } else {
                AddSystemItem "GTA 5 Prozesse" "Inaktiv" "Keine GTA 5 Prozesse gefunden" $false
            }
        } catch {}
        
        try {
            $rageProcess = Get-Process -Name ragemp_v, ragemp_game -ErrorAction SilentlyContinue
            
            if ($rageProcess) {
                $runningRage = $rageProcess | ForEach-Object { "$($_.Name) (PID: $($_.Id))" }
                AddSystemItem "RAGE MP Prozesse" "Aktiv" ($runningRage -join ", ") $false
            } else {
                AddSystemItem "RAGE MP Prozesse" "Inaktiv" "Keine RAGE MP Prozesse gefunden" $false
            }
        } catch {}
        
        $writeableSystemDirs = @(
            "$env:WINDIR\System32",
            "$env:WINDIR\SysWOW64"
        )
        
        foreach ($dir in $writeableSystemDirs) {
            if (Test-Path $dir) {
                try {
                    $testFile = "$dir\test_permission_$([Guid]::NewGuid().ToString()).tmp"
                    [io.file]::WriteAllText($testFile, "test")
                    [io.file]::Delete($testFile)
                    AddSystemItem "System-Ordner" "Beschreibbar" "$dir ist beschreibbar!" $true
                } catch {
                    AddSystemItem "System-Ordner" "Geschützt" "$dir ist nicht beschreibbar" $false
                }
            }
        }
        
        try {
            $firewallRules = Get-NetFirewallRule -Enabled True -Direction Outbound -ErrorAction SilentlyContinue | 
                Where-Object { $_.Name -notlike "MPSRULE*" }
            
            foreach ($rule in $firewallRules) {
                $isSuspicious = $false
                $ruleName = $rule.Name.ToLower()
                $displayName = $rule.DisplayName.ToLower()
                
                if (IsRandomName $ruleName) {
                    $isSuspicious = $true
                }
                
                if (-not $isSuspicious) {
                    foreach ($keyword in $cheatKeywords) {
                        if ($ruleName -like "*$keyword*" -or $displayName -like "*$keyword*") {
                            $isSuspicious = $true
                            break
                        }
                    }
                }
                
                if ($isSuspicious) {
                    AddSystemItem "Firewall-Regel" "Verdächtig" "$($rule.DisplayName) - $($rule.Description)" $true
                }
            }
        } catch {}
        
        try {
            $lastBootTime = (Get-WmiObject Win32_OperatingSystem).LastBootUpTime
            $uptime = (Get-Date) - [System.Management.ManagementDateTimeConverter]::ToDateTime($lastBootTime)
            
            if ($uptime.TotalMinutes -lt 30) {
                AddSystemItem "System Uptime" "Kurz" "System wurde vor $([math]::Round($uptime.TotalMinutes)) Minuten neu gestartet" $true
            } else {
                AddSystemItem "System Uptime" "Normal" "System läuft seit $([math]::Round($uptime.TotalHours)) Stunden" $false
            }
        } catch {}
    } catch {
        # Fehlerbehandlung - Scan fortsetzen
        [void]$scanResults.Add("Fehler beim Scannen des Systems: $_")
    }
    
    [void]$scanResults.Add("")
}

function SendToDiscord {
    param (
        [System.Collections.ArrayList]$results
    )
    
    # Verhindere mehrfaches Senden
    if ($global:webhookSent) {
        return
    }
    
    Update-ScanProgress -message "Ergebnisse werden an Discord gesendet..." -step 6 -subStep 80
    
    # Erstelle die Hauptergebnisdatei (ohne gelöschte Dateien)
    $tempFile = [System.IO.Path]::GetTempFileName()
    $mainResults = New-Object System.Collections.ArrayList
    
    foreach ($line in $results) {
        # Kopiere nur Zeilen, die keine gelöschten Dateien betreffen
        if (-not ($line -like "*GELÖSCHTE DATEI:*" -or $line -like "*GELÖSCHTE DATEIEN ANALYSE:*" -or $line -like "*------------------------*")) {
            [void]$mainResults.Add($line)
        }
    }
    
    $mainResults | Out-File -FilePath $tempFile -Encoding utf8
    
    # Erstelle die spezielle Gelöschte-Dateien-Datei
    $deletedTempFile = [System.IO.Path]::GetTempFileName()
    $deletedFilesReport | Out-File -FilePath $deletedTempFile -Encoding utf8
    
    try {
        $client = New-Object System.Net.Http.HttpClient
        $content = New-Object System.Net.Http.MultipartFormDataContent
        
        $computerName = $env:COMPUTERNAME
        $userName = $env:USERNAME
        $currentDate = Get-Date -Format 'dd.MM.yyyy HH:mm:ss'
        $messageText = "TEAM ASTRO - GTA 5 RAGE MP Scan Ergebnisse`nComputer: $computerName`nBenutzer: $userName`nZeit: $currentDate`nWING"
        $stringContent = New-Object System.Net.Http.StringContent $messageText
        $content.Add($stringContent, "content")
        
        # Füge die Hauptergebnisdatei hinzu
        $fileBytes = [System.IO.File]::ReadAllBytes($tempFile)
        $fileContent = New-Object System.Net.Http.ByteArrayContent -ArgumentList @(,$fileBytes)
        $fileContent.Headers.ContentDisposition = New-Object System.Net.Http.Headers.ContentDispositionHeaderValue "form-data"
        $fileContent.Headers.ContentDisposition.Name = "file"
        $fileContent.Headers.ContentDisposition.FileName = "TEAM_ASTRO_Scan_Results.txt"
        $fileContent.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue "text/plain"
        $content.Add($fileContent, "file", "TEAM_ASTRO_Scan_Results.txt")
        
        # Füge die Gelöschte-Dateien-Datei hinzu
        $deletedFileBytes = [System.IO.File]::ReadAllBytes($deletedTempFile)
        $deletedFileContent = New-Object System.Net.Http.ByteArrayContent -ArgumentList @(,$deletedFileBytes)
        $deletedFileContent.Headers.ContentDisposition = New-Object System.Net.Http.Headers.ContentDispositionHeaderValue "form-data"
        $deletedFileContent.Headers.ContentDisposition.Name = "file2"
        $deletedFileContent.Headers.ContentDisposition.FileName = "TEAM_ASTRO_Deleted_Files.txt"
        $deletedFileContent.Headers.ContentType = New-Object System.Net.Http.Headers.MediaTypeHeaderValue "text/plain"
        $content.Add($deletedFileContent, "file2", "TEAM_ASTRO_Deleted_Files.txt")
        
        Update-ScanProgress -message "Sende Daten an Discord..." -step 6 -subStep 90
        
        $response = $client.PostAsync($webhookUrl, $content).Result
        
        if ($response.IsSuccessStatusCode) {
            Update-ScanProgress -message "Ergebnisse erfolgreich gesendet!" -step 6 -subStep 90
            $statusLabel.Text = "Ergebnisse an Discord gesendet!"
            $global:webhookSent = $true
        } else {
            Update-ScanProgress -message "Fehler beim Senden: " + $response.StatusCode -step 6 -subStep 90
            $statusLabel.Text = "Fehler beim Senden an Discord: " + $response.StatusCode
        }
    } catch {
        Update-ScanProgress -message "Fehler beim Senden: " + $_.Exception.Message -step 6 -subStep 90
        $statusLabel.Text = "Fehler beim Senden an Discord: " + $_.Exception.Message
    } finally {
        if (Test-Path $tempFile) {
            Remove-Item $tempFile -Force
        }
        if (Test-Path $deletedTempFile) {
            Remove-Item $deletedTempFile -Force
        }
    }
}

function StartScanTimeout {
    # Erstelle einen Timer für den Timeout
    $global:scanTimer = New-Object System.Windows.Forms.Timer
    $global:scanTimer.Interval = 1000  # 1 Sekunde
    $global:scanTimer.Tag = 0  # Vergangene Zeit in Sekunden
    
    $global:scanTimer.Add_Tick({
        $elapsed = $global:scanTimer.Tag
        $elapsed++
        $global:scanTimer.Tag = $elapsed
        
        # Wenn der Timeout erreicht ist, beende den Scan
        if ($elapsed -ge $global:scanTimeout) {
            $global:scanTimer.Stop()
            
            $mainWindow.Invoke([Action]{
                $statusLabel.Text = "Der Scan wurde aufgrund eines Timeouts beendet."
                FinishScan "Timeout" 0 "Der Scan konnte nicht abgeschlossen werden (Timeout nach $global:scanTimeout Sekunden)."
                
                # Aktiviere den Scan-Button wieder
                $scanBtn.Enabled = $true
                $global:scanRunning = $false
            })
        }
    })
    
    $global:scanTimer.Start()
}

function FinishScan {
    param (
        [string]$result,
        [int]$suspiciousCount,
        [string]$details
    )
    
    # Stoppe den Timeout-Timer, falls er läuft
    if ($global:scanTimer -ne $null) {
        $global:scanTimer.Stop()
        $global:scanTimer.Dispose()
        $global:scanTimer = $null
    }
    
    # Füge einen Eintrag zum App-Verlauf hinzu
    Add-HistoryEntry -result $result -suspiciousCount $suspiciousCount -details $details
    
    # Bereite das Hauptfenster vor und positioniere es genau an der gleichen Stelle wie der Splashscreen
    $mainWindow.Location = $splashScreen.Location
    $mainWindow.Visible = $true
    $mainWindow.Opacity = 1.0
    
    # Schließe den Splashscreen erst nach einer Verzögerung
    Start-Sleep -Milliseconds 1500
    $splashScreen.Close()
    $starTimer.Stop()
    
    # Bringe das Hauptfenster in den Vordergrund
    $mainWindow.BringToFront()
    $mainWindow.TopMost = $true
    Start-Sleep -Milliseconds 100
    $mainWindow.TopMost = $false
    $mainWindow.Activate()
    
    # Setze den Scan-Status zurück
    $global:scanRunning = $false
}

function RunScan {
    # Verhindere mehrfache Ausführung
    if ($global:scanRunning) {
        return
    }
    
    $global:scanRunning = $true
    $scanBtn.Enabled = $false
    $statusLabel.Text = "Scan läuft..."
    $scanResults.Clear()
    $deletedFilesReport.Clear()
    
    # Starte den Timeout-Timer
    StartScanTimeout
    
    # Stelle sicher, dass der Splashscreen immer mittig bleibt und TopMost ist
    $splashScreen.TopMost = $true
    $screenWidth = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
    $screenHeight = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
    $xPos = [math]::Floor(($screenWidth - 900) / 2)
    $yPos = [math]::Floor(($screenHeight - 600) / 2)
    $splashScreen.Location = New-Object System.Drawing.Point($xPos, $yPos)
    $splashScreen.Refresh()
    
    # Stelle sicher, dass das Hauptfenster komplett im Hintergrund vorbereitet wird
    $mainWindow.Opacity = 0
    $mainWindow.Visible = $false
    $mainWindow.Location = $splashScreen.Location
    
    $computerName = $env:COMPUTERNAME
    $userName = $env:USERNAME
    $currentDate = Get-Date -Format 'dd.MM.yyyy HH:mm:ss'
    
    Update-ScanProgress -message "Sammle Systeminformationen..." -step 6 -subStep 5
    
    $osInfo = Get-WmiObject Win32_OperatingSystem
    $cpuInfo = Get-WmiObject Win32_Processor
    $memoryInfo = [math]::Round($osInfo.TotalVisibleMemorySize / 1MB, 2)
    $ipAddress = (Get-NetIPAddress | Where-Object {$_.AddressFamily -eq 'IPv4' -and $_.PrefixOrigin -ne 'WellKnown'}).IPAddress
    
    [void]$scanResults.Add("TEAM ASTRO - GTA 5 RAGE MP CHEAT SCANNER")
    [void]$scanResults.Add("========================================")
    [void]$scanResults.Add("SYSTEM INFORMATIONEN:")
    [void]$scanResults.Add("Computer: $computerName")
    [void]$scanResults.Add("Benutzer: $userName")
    [void]$scanResults.Add("Datum/Zeit: $currentDate")
    [void]$scanResults.Add("Betriebssystem: $($osInfo.Caption) $($osInfo.Version)")
    [void]$scanResults.Add("CPU: $($cpuInfo.Name)")
    [void]$scanResults.Add("RAM: $memoryInfo GB")
    [void]$scanResults.Add("IP-Adresse: $ipAddress")
    [void]$scanResults.Add("")
    
    foreach ($tabControl in $tabControls) {
        $tabControl.Items.Clear()
    }
    
    $suspiciousProcesses.Clear()
    $suspiciousAutoStart.Clear()
    $suspiciousTasks.Clear()
    $suspiciousGtaFiles.Clear()
    $systemFiles.Clear()
    $deletedItems.Clear()
    $recoveredItems.Clear()
    $suspiciousConnections.Clear()
    $roamingFiles.Clear()
    
    # Führe die Scan-Funktionen aus
    try {
        Update-ScanProgress -message "Scanne Prozesse..." -step 6 -subStep 10
        ScanProcesses
        
        Update-ScanProgress -message "Scanne Dateisystem..." -step 6 -subStep 25
        ScanFileSystem
        
        # Bei erreichen von 60% Fortschritt öffnet sich das Hauptfenster im Hintergrund
        Update-ScanProgress -message "Scanne gelöschte Dateien..." -step 6 -subStep 40
        ScanDeletedFiles
        
        Update-ScanProgress -message "Scanne Registry..." -step 6 -subStep 50
        ScanRegistry
        
        Update-ScanProgress -message "Scanne Netzwerk..." -step 6 -subStep 60
        ScanNetwork
        
        Update-ScanProgress -message "Scanne Roaming-Ordner..." -step 6 -subStep 70
        ScanRoaming
        
        Update-ScanProgress -message "Scanne System..." -step 6 -subStep 75
        ScanSystem
        
        [void]$scanResults.Add("")
        [void]$scanResults.Add("Scan abgeschlossen.")
        
        # Zähle verdächtige Elemente
        $totalSuspicious = $suspiciousProcesses.Count + 
                           $suspiciousGtaFiles.Count + 
                           $systemFiles.Count + 
                           $suspiciousAutoStart.Count + 
                           $suspiciousTasks.Count + 
                           $suspiciousConnections.Count
        
        # Bestimme das Scan-Ergebnis
        $scanResult = "Sauber"
        $scanDetails = "Keine verdächtigen Elemente gefunden."
        
        if ($totalSuspicious -gt 0) {
            $scanResult = "Verdächtig"
            $scanDetails = "Gefundene verdächtige Elemente: " +
                          "Prozesse ($($suspiciousProcesses.Count)), " +
                          "Dateien ($($suspiciousGtaFiles.Count + $systemFiles.Count)), " +
                          "Autostart ($($suspiciousAutoStart.Count + $suspiciousTasks.Count)), " +
                          "Netzwerk ($($suspiciousConnections.Count))"
        }
        
        # Sende Ergebnisse an Discord
        $statusLabel.Text = "Scan abgeschlossen. Sende Ergebnisse..."
        SendToDiscord $scanResults
        
        # Schließe den Scan ab
        FinishScan $scanResult $totalSuspicious $scanDetails
        
        # Aktiviere den Scan-Button wieder
        $scanBtn.Enabled = $true
    } catch {
        # Fehlerbehandlung
        [void]$scanResults.Add("FEHLER BEIM SCAN: $_")
        $statusLabel.Text = "Fehler beim Scan: $_"
        
        # Schließe den Scan ab, auch bei Fehler
        FinishScan "Fehler" 0 "Scan-Fehler: $_"
        $scanBtn.Enabled = $true
    } finally {
        # Setze den Scan-Status zurück, falls nicht bereits geschehen
        $global:scanRunning = $false
    }
}

Update-ScanProgress -message "ERSTELLE EVENT-HANDLER..." -step 6 -subStep 5

$scanBtn.Add_Click({
    if (-not $global:scanRunning) {
        RunScan
    }
})

foreach ($listView in $tabControls) {
    $listView.Add_MouseClick({
        $item = $_.Item
        if ($item -ne $null) {
            $itemText = $item.Text
            $subItems = $item.SubItems | ForEach-Object { $_.Text }
            
            $info = New-Object System.Text.StringBuilder
            $info.AppendLine("Details:")
            
            for ($i = 0; $i -lt $subItems.Count; $i++) {
                $columnName = "Spalte $i"
                if ($i -lt $listView.Columns.Count) {
                    $columnName = $listView.Columns[$i].Text
                }
                $info.AppendLine("$columnName`: $($subItems[$i])")
            }
            
            [System.Windows.Forms.MessageBox]::Show($info.ToString(), "Item Details", 
                [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
    })
}

# Initialisiere den App-Verlauf
Initialize-AppHistory
Update-HistoryDisplay

# Stelle sicher, dass der Splashscreen immer in der Mitte des Hauptbildschirms erscheint
$screenWidth = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
$screenHeight = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
$xPos = [math]::Floor(($screenWidth - 900) / 2)
$yPos = [math]::Floor(($screenHeight - 600) / 2)
$splashScreen.Location = New-Object System.Drawing.Point($xPos, $yPos)

# Starte Scan-Vorbereitungen
Update-ScanProgress -message "SCAN WIRD VORBEREITET..." -step 6 -subStep 8

# Starte den Scan automatisch
if (-not $global:scanRunning) {
    RunScan
}
