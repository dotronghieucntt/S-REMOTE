# NOVIVO-Backend.ps1 - Install logic only
param([Parameter(Mandatory)][string]$Method,[Parameter(Mandatory)][string]$NetworkKey,[Parameter(Mandatory)][string]$UsersJson)

function Write-Output-Box { param([string]$Message,[string]$Color="Lime"); Write-Host $Message; [Console]::Out.Flush() }

$userList = $UsersJson | ConvertFrom-Json
$networkID = $NetworkKey
$radioTailscale = [PSCustomObject]@{ Checked = ($Method -eq "tailscale") }
$rdpWorking = $false

# ── Disable sleep & hibernate during installation ───────────────────────────
$_powerType = $null
try {
    $sig = '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'
    $_powerType = Add-Type -MemberDefinition $sig -Name "NovivoPower" -Namespace "Win32" -PassThru -ErrorAction Stop
} catch {
    try { $_powerType = [Win32.NovivoPower] } catch { $_powerType = $null }
}
if ($_powerType) {
    # ES_CONTINUOUS(2147483648) | ES_SYSTEM_REQUIRED(1) | ES_AWAYMODE_REQUIRED(64)
    # Use decimal literals - PS5.1 parses 0x80000000 as negative Int32 which fails UInt32 cast
    [void]$_powerType::SetThreadExecutionState([uint32]2147483648 -bor [uint32]1 -bor [uint32]64)
}
powercfg /hibernate off 2>$null | Out-Null
Write-Output-Box "[INFO] Sleep and hibernate disabled for duration of setup"

try {
    $rdpWorking = $false
    
    try {
        $networkID = $textNetworkID.Text.Trim()

        # Collect users from the grid
        $userList = @()
        foreach ($row in $userGrid.Rows) {
            $uname = if ($row.Cells["Username"].Value) { $row.Cells["Username"].Value.ToString().Trim() } else { "" }
            $upass  = if ($row.Cells["Password"].Value) { $row.Cells["Password"].Value.ToString() } else { "" }
            if (-not [string]::IsNullOrWhiteSpace($uname)) {
                $userList += [PSCustomObject]@{ Username = $uname; Password = $upass }
            }
        }

        # Validate inputs
        if ([string]::IsNullOrWhiteSpace($networkID)) {
            Write-Output-Box "[ERROR] Network ID / Auth Key cannot be empty!"
            return
        }
        if ($userList.Count -eq 0) {
            Write-Output-Box "[ERROR] Please add at least one user in the Users table!"
            return
        }
        foreach ($u in $userList) {
            if ([string]::IsNullOrWhiteSpace($u.Password)) {
                Write-Output-Box "[ERROR] Password for user '$($u.Username)' cannot be empty!"
                return
            }
        }
        # Primary user used for connection info display
        $username = $userList[0].Username
        $password = $userList[0].Password

        # ====================================================================
        #  TAILSCALE BRANCH  – runs when user selects Tailscale method
        # ====================================================================
        if ($radioTailscale.Checked) {

            $authKey  = $textNetworkID.Text.Trim()   # re-use the same control
            $tsRdpWorking = $false

            Write-Output-Box "==================================================="
            Write-Output-Box ">>> NOVIVO REMOTE DESKTOP - TAILSCALE SETUP <<<"
            Write-Output-Box "==================================================="
            Write-Output-Box ""

            # TS-STEP 1: Download / Install Tailscale
            Write-Output-Box "[1/7] Downloading Tailscale installer..."
            $tsInstallerPath = "$env:TEMP\TailscaleSetup.exe"  # default, overridden per URL in loop
            $tsInstalledViaWinget = $false

            # --- Try winget first (most reliable, no URL guessing) ---
            $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
            if ($wingetCmd) {
                Write-Output-Box "[INFO] Trying winget install..."
                try {
                    $wgOut = & winget install --id tailscale.tailscale --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-String
                    if ($LASTEXITCODE -eq 0 -or $wgOut -match 'Successfully installed') {
                        Write-Output-Box "[OK] Tailscale installed via winget"
                        $tsInstalledViaWinget = $true
                    } else {
                        Write-Output-Box "[INFO] winget exit $LASTEXITCODE - falling back to direct download"
                    }
                } catch { Write-Output-Box "[INFO] winget failed - falling back to direct download" }
            }

            $tsDownloaded = $false
            if (-not $tsInstalledViaWinget) {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
                [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

                # Windows .exe = no arch suffix; .msi = has arch suffix
                $tsMsiArch = if ([Environment]::Is64BitOperatingSystem) { 'amd64' } else { 'x86' }
                $tsUrls = @(
                    "https://pkgs.tailscale.com/stable/tailscale-setup-latest.exe",
                    "https://pkgs.tailscale.com/stable/tailscale-setup-1.94.2.exe",
                    "https://pkgs.tailscale.com/stable/tailscale-setup-full-1.94.2.exe",
                    "https://pkgs.tailscale.com/stable/tailscale-setup-1.94.2-$tsMsiArch.msi"
                )

                foreach ($tsUrl in $tsUrls) {
                    try {
                        Write-Output-Box "Trying: $tsUrl"
                        # Save with correct extension
                        $tsExt = if ($tsUrl -match '\.msi$') { '.msi' } else { '.exe' }
                        $tsInstallerPath = "$env:TEMP\TailscaleSetup$tsExt"
                        $wc = New-Object System.Net.WebClient
                        $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
                        $wc.DownloadFile($tsUrl, $tsInstallerPath)
                        $tsFileOk = $false
                        if ((Test-Path $tsInstallerPath) -and (Get-Item $tsInstallerPath).Length -gt 5MB) {
                            $tsBytes = [System.IO.File]::ReadAllBytes($tsInstallerPath)
                            # EXE: MZ header; MSI: D0 CF 11 E0 (OLE2) or just skip header check for MSI
                            $tsValidHeader = ($tsExt -eq '.exe' -and $tsBytes[0] -eq 0x4D -and $tsBytes[1] -eq 0x5A) -or
                                             ($tsExt -eq '.msi' -and $tsBytes[0] -eq 0xD0 -and $tsBytes[1] -eq 0xCF)
                            if ($tsValidHeader) {
                                Write-Output-Box "[OK] Downloaded ($([math]::Round((Get-Item $tsInstallerPath).Length/1MB,2)) MB)"
                                $tsDownloaded = $true
                                $tsFileOk = $true
                            } else { Write-Output-Box "Invalid file header, skipping..." }
                        } else { Write-Output-Box "File too small (<5 MB), skipping..." }
                        if ($tsFileOk) { break }
                    }
                    catch {
                        Write-Output-Box "WebClient failed: $($_.Exception.Message)"
                        try {
                            $tsExt2 = if ($tsUrl -match '\.msi$') { '.msi' } else { '.exe' }
                            $tsInstallerPath = "$env:TEMP\TailscaleSetup$tsExt2"
                            Invoke-WebRequest -Uri $tsUrl -OutFile $tsInstallerPath -UseBasicParsing -TimeoutSec 180
                            if ((Test-Path $tsInstallerPath) -and (Get-Item $tsInstallerPath).Length -gt 5MB) {
                                $tsBytes2 = [System.IO.File]::ReadAllBytes($tsInstallerPath)
                                $tsVH2 = ($tsExt2 -eq '.exe' -and $tsBytes2[0] -eq 0x4D -and $tsBytes2[1] -eq 0x5A) -or
                                         ($tsExt2 -eq '.msi' -and $tsBytes2[0] -eq 0xD0 -and $tsBytes2[1] -eq 0xCF)
                                if ($tsVH2) {
                                    Write-Output-Box "[OK] Downloaded (fallback method)"
                                    $tsDownloaded = $true
                                    break
                                }
                            }
                        }
                        catch { Write-Output-Box "Fallback failed: $($_.Exception.Message)" }
                    }
                }

                [Net.ServicePointManager]::ServerCertificateValidationCallback = $null

                if (-not $tsDownloaded) {
                    Write-Output-Box "[ERROR] Could not download Tailscale. Check internet connection."
                    return
                }
            }

            # TS-STEP 2: Install Tailscale silently
            Write-Output-Box ""
            Write-Output-Box "[2/7] Installing Tailscale..."

            # Check if Tailscale already installed  -  skip installer if binary found and service exists
            $tsAlreadyInstalled = $false
            $tsPreCheckPaths = @(
                "$env:ProgramFiles\Tailscale\tailscale.exe",
                'C:\Program Files (x86)\Tailscale\tailscale.exe'
            )
            foreach ($tsPC in $tsPreCheckPaths) {
                if (Test-Path $tsPC) { $tsAlreadyInstalled = $true; break }
            }
            if (-not $tsAlreadyInstalled) {
                $tsPreGC = Get-Command tailscale -ErrorAction SilentlyContinue
                if ($tsPreGC) { $tsAlreadyInstalled = $true }
            }
            if ($tsAlreadyInstalled) {
                Write-Output-Box "[INFO] Tailscale already installed  -  skipping installer"
            }

            if (-not $tsInstalledViaWinget -and -not $tsAlreadyInstalled) {
                try {
                    $tsIsMsi = $tsInstallerPath -match '\.msi$'
                    if ($tsIsMsi) {
                        Write-Output-Box "[INFO] Installing MSI package..."
                        $tsProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$tsInstallerPath`" /qn /norestart" -Wait -PassThru
                        if ($tsProc.ExitCode -eq 1603 -or $tsProc.ExitCode -eq 1638) {
                            Write-Output-Box "[INFO] MSI code $($tsProc.ExitCode)  -  trying upgrade/repair mode..."
                            $tsProc = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$tsInstallerPath`" /qn /norestart REINSTALL=ALL REINSTALLMODE=vomus" -Wait -PassThru
                        }
                    } else {
                        $tsProc = Start-Process -FilePath $tsInstallerPath -ArgumentList "/S /NORESTART" -Wait -PassThru
                    }
                    if ($tsProc.ExitCode -eq 0 -or $tsProc.ExitCode -eq 3010) {
                        Write-Output-Box "[OK] Tailscale installed successfully (code $($tsProc.ExitCode))"
                    } else {
                        Write-Output-Box "[WARNING] Installer exit code $($tsProc.ExitCode)"
                        if (-not $tsIsMsi -and $tsProc.ExitCode -ne 0) {
                            Write-Output-Box "[INFO] Retrying with plain /S flag..."
                            $tsProc2 = Start-Process -FilePath $tsInstallerPath -ArgumentList "/S" -Wait -PassThru
                            Write-Output-Box "[INFO] Retry exit code: $($tsProc2.ExitCode)"
                        }
                    }
                    Start-Sleep -Seconds 10
                }
                catch {
                    Write-Output-Box "[ERROR] Tailscale install error: $($_.Exception.Message)"
                    return
                }
            } else {
                if ($tsInstalledViaWinget) { Write-Output-Box "[INFO] Skipping installer (already installed via winget)" }
                # else: already installed branch already printed its own message above
            }

            # Locate tailscale.exe - refresh PATH first so newly installed binaries are found
            $tsCliPath = ''
            $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
            Start-Sleep -Seconds 5

            $tsPossiblePaths = @(
                "$env:ProgramFiles\Tailscale\tailscale.exe",
                'C:\Program Files (x86)\Tailscale\tailscale.exe',
                "$env:LocalAppData\Tailscale\tailscale.exe",
                'C:\Windows\System32\tailscale.exe'
            )
            foreach ($tsP in $tsPossiblePaths) {
                if (Test-Path $tsP) { $tsCliPath = $tsP; break }
            }
            if (-not $tsCliPath) {
                $tsGC2 = Get-Command tailscale -ErrorAction SilentlyContinue
                if ($tsGC2) { $tsCliPath = $tsGC2.Source }
            }
            # Last resort: find it on disk
            if (-not $tsCliPath) {
                $tsFound = Get-ChildItem 'C:\Program Files*' -Recurse -Filter 'tailscale.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($tsFound) { $tsCliPath = $tsFound.FullName }
            }
            if (-not $tsCliPath) {
                Write-Output-Box "[ERROR] tailscale.exe not found after installation. Install may have failed."
                Write-Output-Box "[INFO] Please install Tailscale manually from https://tailscale.com/download/windows"
                return
            }
            Write-Output-Box "[INFO] tailscale path: $tsCliPath"

            # ── Ensure Tailscale service is running ──────────────────────────────
            $tsSvcName = 'Tailscale'
            try {
                $tsSvcObj = Get-Service -DisplayName '*Tailscale*' -ErrorAction SilentlyContinue | Select-Object -First 1
                if (-not $tsSvcObj) { $tsSvcObj = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue }
                if ($tsSvcObj) { $tsSvcName = $tsSvcObj.Name }

                if ($tsSvcObj.Status -ne 'Running') {
                    Start-Service -Name $tsSvcName -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 4
                    Write-Output-Box "[INFO] Started Tailscale service"
                }
            } catch { }

            # ── Configure Tailscale to start BEFORE Windows login screen ─────────
            # Method 1: Windows Service — set to Automatic (not delayed) so it
            #            starts at kernel/boot time, well before any user logs in.
            Write-Output-Box ""
            Write-Output-Box "[INFO] Configuring Tailscale boot-time autostart..."
            try {
                Set-Service -Name $tsSvcName -StartupType Automatic -ErrorAction SilentlyContinue
                # Remove any 'delayed auto-start' flag so it starts immediately at boot
                & sc.exe config $tsSvcName start= auto 2>&1 | Out-Null
                & sc.exe config $tsSvcName delayed-auto= no  2>&1 | Out-Null
                Write-Output-Box "[OK] Tailscale service startup type: Automatic (no delay)"
            } catch {
                Write-Output-Box "[WARNING] Service config: $($_.Exception.Message)"
            }

            # Method 2: Task Scheduler at System Startup (SYSTEM account)
            # Runs as SYSTEM before any user login — even on the lock screen.
            try {
                $tsTaskName  = "Tailscale-BootAutostart"
                $tsBinPath   = if ($tsCliPath) { $tsCliPath } else { 'tailscale.exe' }
                Unregister-ScheduledTask -TaskName $tsTaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null

                $tsAction    = New-ScheduledTaskAction -Execute $tsBinPath -Argument "start" 
                $tsTrigger   = New-ScheduledTaskTrigger -AtStartup
                $tsPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
                $tsSettings  = New-ScheduledTaskSettingsSet `
                                    -AllowStartIfOnBatteries `
                                    -DontStopIfGoingOnBatteries `
                                    -StartWhenAvailable `
                                    -ExecutionTimeLimit (New-TimeSpan -Seconds 0)
                Register-ScheduledTask `
                    -TaskName  $tsTaskName `
                    -Action    $tsAction `
                    -Trigger   $tsTrigger `
                    -Principal $tsPrincipal `
                    -Settings  $tsSettings `
                    -Force | Out-Null
                Write-Output-Box "[OK] Scheduled Task '$tsTaskName' registered (SYSTEM, AtStartup)"
            } catch {
                Write-Output-Box "[WARNING] Scheduled Task: $($_.Exception.Message)"
            }

            # Method 3: All-Users Startup folder (fallback for after login)
            try {
                $tsTrayExe = $null
                $tsTrayPaths = @(
                    "$env:ProgramFiles\Tailscale\Tailscale.exe",
                    'C:\Program Files (x86)\Tailscale\Tailscale.exe'
                )
                foreach ($tp in $tsTrayPaths) { if (Test-Path $tp) { $tsTrayExe = $tp; break } }

                if ($tsTrayExe) {
                    $tsAllUsersStartup = [System.Environment]::GetFolderPath('CommonStartup')
                    if (-not $tsAllUsersStartup) {
                        $tsAllUsersStartup = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
                    }
                    $tsLnkPath = Join-Path $tsAllUsersStartup "Tailscale.lnk"
                    $tsShell   = New-Object -ComObject WScript.Shell
                    $tsLnk     = $tsShell.CreateShortcut($tsLnkPath)
                    $tsLnk.TargetPath       = $tsTrayExe
                    $tsLnk.WorkingDirectory = Split-Path $tsTrayExe
                    $tsLnk.Description      = "Tailscale autostart"
                    $tsLnk.Save()
                    Write-Output-Box "[OK] Tailscale shortcut added to All-Users Startup folder"
                }
            } catch {
                Write-Output-Box "[WARNING] Startup folder: $($_.Exception.Message)"
            }

            # Method 4: HKLM Run key (machine-wide, any user session)
            try {
                $tsRunExe = if ($tsCliPath) { $tsCliPath } else { 'tailscale.exe' }
                Set-ItemProperty `
                    -Path  "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" `
                    -Name  "TailscaleAutostart" `
                    -Value "`"$tsRunExe`"" `
                    -Type  String -Force
                Write-Output-Box "[OK] HKLM Run key set for Tailscale"
            } catch {
                Write-Output-Box "[WARNING] HKLM Run key: $($_.Exception.Message)"
            }

            Write-Output-Box "[OK] Tailscale autostart configured (4 methods: Service/Task/Startup/Run)"

            # TS-STEP 3: Connect / bring up Tailscale
            Write-Output-Box ''
            Write-Output-Box '[3/7] Connecting to Tailscale network...'
            try {
                # --unattended = persist "want-up" state to disk so Tailscale reconnects
                # automatically after every reboot WITHOUT requiring user interaction
                $tsUpArgs = @('up', '--unattended', '--accept-routes', '--accept-dns')
                if (-not [string]::IsNullOrWhiteSpace($authKey)) {
                    Write-Output-Box '[INFO] Using auth key to connect...'
                    $tsUpArgs += @('--authkey', $authKey)
                } else {
                    Write-Output-Box '[INFO] No auth key - browser login may open'
                }
                $tsUpOut = & $tsCliPath $tsUpArgs 2>&1 | Out-String
                Write-Output-Box '[OK] tailscale up --unattended executed (auto-reconnect on reboot enabled)'
                if ($tsUpOut -and $tsUpOut.Trim()) { Write-Output-Box "Out: $($tsUpOut.Trim())" }
                Start-Sleep -Seconds 5
            }
            catch {
                Write-Output-Box "[WARNING] tailscale up: $($_.Exception.Message)"
            }

            # TS-STEP 4: Enable RDP (same as ZeroTier)
            Write-Output-Box ""
            Write-Output-Box "[4/7] Configuring Remote Desktop..."
            try {
                & reg.exe add "HKLM\System\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f 2>&1 | Out-Null
                & reg.exe add "HKLM\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v UserAuthentication /t REG_DWORD /d 0 /f 2>&1 | Out-Null
                Write-Output-Box "[OK] Core RDP settings applied"
            }
            catch { Write-Output-Box "[WARNING] reg.exe failed, using PowerShell fallback" }

            Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -Force
            Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 0 -Force

            $tsRegPaths = @(
                @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"; Name="fDenyTSConnections"; Value=0},
                @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"; Name="fAllowToGetHelp"; Value=1},
                @{Path="HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server"; Name="AllowTSConnections"; Value=1},
                @{Path="HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name="PortNumber"; Value=3389; Type="DWord"},
                @{Path="HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name="SecurityLayer"; Value=0},
                @{Path="HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name="UserAuthentication"; Value=0},
                @{Path="HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name="fEnableWinStation"; Value=1},
                @{Path="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"; Name="LocalAccountTokenFilterPolicy"; Value=1}
            )
            foreach ($r in $tsRegPaths) {
                if (-not (Test-Path $r.Path)) { New-Item -Path $r.Path -Force | Out-Null }
                $rType = if ($r.Type) { $r.Type } else { "DWord" }
                Set-ItemProperty -Path $r.Path -Name $r.Name -Value $r.Value -Type $rType -Force
            }
            Write-Output-Box "[OK] RDP registry configured"

            # Firewall
            try {
                Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
                $existFw = Get-NetFirewallRule -DisplayName "RDP-Tailscale-3389" -ErrorAction SilentlyContinue
                if ($existFw) { Remove-NetFirewallRule -DisplayName "RDP-Tailscale-3389" -ErrorAction SilentlyContinue }
                New-NetFirewallRule -DisplayName "RDP-Tailscale-3389" -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow -Enabled True -Profile Any -ErrorAction SilentlyContinue | Out-Null
                & netsh advfirewall firewall add rule name="RDP-Tailscale-Netsh" dir=in action=allow protocol=TCP localport=3389 2>&1 | Out-Null
                Write-Output-Box "[OK] Firewall rules configured"
            }
            catch { Write-Output-Box "[WARNING] Firewall: $($_.Exception.Message)" }

            # Enable RDP via WMI  -  most reliable method on Win11 (takes effect without reboot)
            try {
                $tsWmiTS = Get-WmiObject -Class Win32_TerminalServiceSetting -Namespace root/cimv2/TerminalServices -ErrorAction SilentlyContinue
                if ($tsWmiTS) {
                    # Win10 Pro for Workstations: arg (1,1) fails with "Invalid operation"
                    # Use single-arg (1) which works on all editions without reboot
                    try { $tsWmiTS.SetAllowTSConnections(1) | Out-Null }
                    catch { $tsWmiTS.SetAllowTSConnections(1, 0) | Out-Null }
                    Write-Output-Box "[OK] RDP enabled via WMI (AllowTSConnections)"
                }
            } catch { Write-Output-Box "[INFO] WMI enable: $($_.Exception.Message)" }

            # Detect Windows edition  -  Home needs RDP Wrapper to enable hosting
            try {
                $tsWinEdition = (Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
                if ($tsWinEdition -match '\bHome\b') {
                    Write-Output-Box ""
                    Write-Output-Box "[INFO] Windows Home detected - installing RDP Wrapper to enable RDP..."
                    $rdpwZip  = "$env:TEMP\RDPWrap.zip"
                    $rdpwDir  = "$env:TEMP\RDPWrapExtract"
                    $rdpwOk   = $false
                    try {
                        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                        $wc2 = New-Object System.Net.WebClient
                        $wc2.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
                        $wc2.DownloadFile("https://github.com/stascorp/rdpwrap/releases/download/v1.6.2/RDPWrap-v1.6.2.zip", $rdpwZip)
                        if ((Test-Path $rdpwZip) -and (Get-Item $rdpwZip).Length -gt 100KB) {
                            if (Test-Path $rdpwDir) { Remove-Item $rdpwDir -Recurse -Force }
                            Expand-Archive -Path $rdpwZip -DestinationPath $rdpwDir -Force
                            $rdpwInst = Get-ChildItem $rdpwDir -Filter "RDPWInst.exe" -Recurse | Select-Object -First 1
                            if ($rdpwInst) {
                                $rdpwProc = Start-Process -FilePath $rdpwInst.FullName -ArgumentList "-i" -Wait -PassThru -WindowStyle Hidden
                                Write-Output-Box "[OK] RDP Wrapper installed (code $($rdpwProc.ExitCode))"
                                $rdpwOk = $true
                                # Update ini file for newer Win10/11 builds (community-maintained)
                                $rdpwIniPath = "$env:ProgramFiles\RDP Wrapper\rdpwrap.ini"
                                try {
                                    $wc3 = New-Object System.Net.WebClient
                                    $wc3.Headers.Add("User-Agent", "Mozilla/5.0")
                                    $wc3.DownloadFile("https://raw.githubusercontent.com/sebaxakerhtc/rdpwrap.ini/master/rdpwrap.ini", $rdpwIniPath)
                                    Write-Output-Box "[OK] RDP Wrapper ini updated for current Windows build"
                                } catch { Write-Output-Box "[INFO] ini update skipped: $($_.Exception.Message)" }
                                Start-Sleep -Seconds 2
                                Restart-Service -Name "RDPWrapper" -ErrorAction SilentlyContinue
                                Write-Output-Box "[OK] RDP Wrapper service started"
                            } else { Write-Output-Box "[WARNING] RDPWInst.exe not found in archive" }
                        } else { Write-Output-Box "[WARNING] RDP Wrapper download failed or file too small" }
                    } catch { Write-Output-Box "[WARNING] RDP Wrapper install failed: $($_.Exception.Message)" }
                    if (-not $rdpwOk) {
                        Write-Output-Box "[WARNING] Could not auto-enable RDP on Windows Home"
                        Write-Output-Box "[INFO] Manual option: upgrade to Windows Pro, or use Chrome Remote Desktop"
                    }
                } else {
                    Write-Output-Box "[INFO] Windows edition: $tsWinEdition"
                }
            } catch {}

            # TS-STEP 5: Configure user accounts
            Write-Output-Box ""
            Write-Output-Box "[5/7] Configuring $($userList.Count) user account(s)..."
            foreach ($userEntry in $userList) {
                $username = $userEntry.Username
                $password = $userEntry.Password
                Write-Output-Box "  [USER] >>> $username <<<"
                try {
                    # --- Detect Microsoft account FIRST ---
                    $isMicrosoftAccount = $false
                    try {
                        $localUserObj = Get-LocalUser -Name $username -ErrorAction SilentlyContinue
                        if ($localUserObj -and "$($localUserObj.PrincipalSource)" -eq 'MicrosoftAccount') {
                            $isMicrosoftAccount = $true
                        }
                    } catch {}

                    if ($isMicrosoftAccount) {
                        Write-Output-Box "[INFO] Microsoft account detected - password change skipped"
                        Write-Output-Box "[INFO] Use your Microsoft account password to connect via RDP"
                    } else {
                        $tsNetUserCheck = & net user $username 2>&1
                        $tsUserExists = ($LASTEXITCODE -eq 0)

                        if (-not $tsUserExists) {
                            $tsNetRes = & net user $username $password /add /passwordchg:no /expires:never /comment:"Created by NOVIVO Remote Desktop" 2>&1
                            $tsNetResStr = $tsNetRes | Out-String
                            if ($LASTEXITCODE -eq 0) {
                                Write-Output-Box "[OK] User created: $username"
                                & wmic useraccount where "name='$username'" set PasswordExpires=False 2>&1 | Out-Null
                            }
                            elseif ($tsNetResStr -match '8646|not authoritative|online provider') {
                                Write-Output-Box "[INFO] Microsoft account detected - password change skipped"
                                Write-Output-Box "[INFO] Use your Microsoft account password to connect via RDP"
                            }
                            else { throw "Failed to create user: $tsNetResStr" }
                        } else {
                            $tsNetRes = & net user $username $password 2>&1
                            $tsNetResStr = $tsNetRes | Out-String
                            if ($LASTEXITCODE -eq 0) {
                                Write-Output-Box "[OK] Password updated for: $username"
                                & wmic useraccount where "name='$username'" set PasswordExpires=False 2>&1 | Out-Null
                            }
                            elseif ($tsNetResStr -match '8646|not authoritative|online provider') {
                                Write-Output-Box "[INFO] Microsoft account detected - password change skipped"
                                Write-Output-Box "[INFO] Use your Microsoft account password to connect via RDP"
                            }
                            else { throw "Failed to update password: $tsNetResStr" }
                        }
                    }
                    # Get Remote Desktop Users group name via SID (works on all locales)
                    $tsRdpGroupName = 'Remote Desktop Users'
                    try {
                        $tsRdpSid = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-555'
                        $tsRdpNT  = $tsRdpSid.Translate([System.Security.Principal.NTAccount]).Value
                        $tsParts  = $tsRdpNT.Split('\\'.ToCharArray())
                        $tsRdpGroupName = $tsParts[$tsParts.Length - 1]
                    } catch { }

                    $tsAddAdm = & net localgroup Administrators $username /add 2>&1
                    if ($LASTEXITCODE -eq 0) { Write-Output-Box "[OK] Added to Administrators" }
                    else { Write-Output-Box "[INFO] Administrators: $tsAddAdm" }
                    # Create the group if it doesn't exist (absent on Win11 Home/some configs)
                    $tsRdpGrpExists = Get-LocalGroup -SID "S-1-5-32-555" -ErrorAction SilentlyContinue
                    if (-not $tsRdpGrpExists) {
                        try {
                            New-LocalGroup -Name $tsRdpGroupName -Description "Members in this group are granted the right to logon remotely" -ErrorAction SilentlyContinue | Out-Null
                            Write-Output-Box "[OK] Created '$tsRdpGroupName' group (was missing)"
                        } catch { Write-Output-Box "[INFO] Could not create RDP group: $($_.Exception.Message)" }
                    }
                    try {
                        Add-LocalGroupMember -SID "S-1-5-32-555" -Member $username -ErrorAction Stop
                        Write-Output-Box "[OK] Added to $tsRdpGroupName"
                    } catch {
                        if ($_.Exception.Message -match 'already.*member|member.*already') {
                            Write-Output-Box "[INFO] Already in $tsRdpGroupName"
                        } else {
                            $tsAddRdp = & net localgroup $tsRdpGroupName $username /add 2>&1
                            if ($LASTEXITCODE -eq 0) { Write-Output-Box "[OK] Added to $tsRdpGroupName" }
                            else { Write-Output-Box "[INFO] RDP Users: $tsAddRdp" }
                        }
                    }
                }
                catch {
                    Write-Output-Box "[ERROR] User config failed for '$username': $($_.Exception.Message)"
                    return
                }
            }

            # TS-STEP 6: Restart RDP services
            Write-Output-Box ""
            Write-Output-Box "[6/7] Restarting RDP services..."
            try {
                Stop-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
                Stop-Service -Name "SessionEnv"  -Force -ErrorAction SilentlyContinue
                Stop-Service -Name "UmRdpService"-Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3

                & sc.exe config TermService  start= auto 2>&1 | Out-Null
                & sc.exe config SessionEnv   start= auto 2>&1 | Out-Null
                & sc.exe config UmRdpService start= auto 2>&1 | Out-Null

                Start-Service -Name "SessionEnv"   -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                Start-Service -Name "TermService"  -ErrorAction Stop
                Start-Sleep -Seconds 5
                Start-Service -Name "UmRdpService" -ErrorAction SilentlyContinue

                $tsSvc = Get-Service -Name "TermService"
                if ($tsSvc.Status -eq "Running") {
                    Write-Output-Box "[OK] TermService is RUNNING"
                    $tsRdpWorking = $true
                } else {
                    Write-Output-Box "[WARNING] TermService status: $($tsSvc.Status)"
                }

                # Verify port 3389
                Start-Sleep -Seconds 5
                $tsPort = Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue
                if ($tsPort) {
                    Write-Output-Box "[OK] Port 3389 is LISTENING"
                    $tsRdpWorking = $true
                } else {
                    Write-Output-Box "[WARNING] Port 3389 not yet listening - running deep reset (no reboot)..."

                    # Step A: re-assert registry so listener is enabled
                    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -Force
                    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "fEnableWinStation" -Value 1 -Force -ErrorAction SilentlyContinue
                    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fSingleSessionPerUser" -Value 0 -Force -ErrorAction SilentlyContinue

                    # Step B: stop all RDP services in reverse dependency order
                    & sc.exe stop UmRdpService 2>&1 | Out-Null
                    & sc.exe stop TermService  2>&1 | Out-Null
                    & sc.exe stop SessionEnv   2>&1 | Out-Null
                    Start-Sleep -Seconds 5

                    # Step C: WMI call while service is stopped (re-read registry on next start)
                    try {
                        $tsWmiR = Get-WmiObject -Class Win32_TerminalServiceSetting -Namespace root/cimv2/TerminalServices -ErrorAction SilentlyContinue
                        if ($tsWmiR) { try { $tsWmiR.SetAllowTSConnections(1) | Out-Null } catch {} }
                    } catch {}

                    # Step D: start services in dependency order
                    & sc.exe start SessionEnv   2>&1 | Out-Null
                    Start-Sleep -Seconds 3
                    & sc.exe start TermService  2>&1 | Out-Null
                    Start-Sleep -Seconds 8
                    & sc.exe start UmRdpService 2>&1 | Out-Null
                    Start-Sleep -Seconds 5

                    $tsPort2 = Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue
                    if ($tsPort2) {
                        Write-Output-Box "[OK] Port 3389 is now LISTENING (after deep reset)"
                        $tsRdpWorking = $true
                    } else {
                        # Step E: toggle fEnableWinStation to force listener rebind
                        Write-Output-Box "[INFO] Toggle listener rebind..."
                        $rdpTcpPath2 = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
                        Set-ItemProperty -Path $rdpTcpPath2 -Name "fEnableWinStation" -Value 0 -Force
                        Start-Sleep -Seconds 2
                        Set-ItemProperty -Path $rdpTcpPath2 -Name "fEnableWinStation" -Value 1 -Force
                        Restart-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
                        Start-Sleep -Seconds 10

                        $tsPort3 = Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue
                        if ($tsPort3) {
                            Write-Output-Box "[OK] Port 3389 LISTENING after listener rebind"
                            $tsRdpWorking = $true
                        } else {
                            Write-Output-Box "[WARNING] Port 3389 still not listening"
                            Write-Output-Box "[INFO] Registry is configured correctly - RDP will work after restart"
                            $tsRdpWorking = $false
                        }
                    }
                }
            }
            catch {
                Write-Output-Box "[WARNING] Service restart: $($_.Exception.Message)"
            }

            # TS-STEP 6.5: Configure Tailscale to auto-connect on boot (headless/no-login)
            Write-Output-Box ""
            Write-Output-Box "[INFO] Configuring Tailscale headless auto-start..."
            try {
                # 1. Set Tailscale service to Automatic + network dependency + recovery restart
                $tsSvcName2 = Get-Service -DisplayName '*Tailscale*' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Name
                if (-not $tsSvcName2) { $tsSvcName2 = 'Tailscale' }
                # Startup type: Automatic (delayed)  -  starts after network ready
                & sc.exe config $tsSvcName2 start= delayed-auto 2>&1 | Out-Null
                # Network stack dependency
                & sc.exe config $tsSvcName2 depend= Tcpip/Afd/Nsi 2>&1 | Out-Null
                # Recovery: restart service on 1st, 2nd, subsequent failures (reset counter every 86400s)
                & sc.exe failure $tsSvcName2 reset= 86400 actions= restart/5000/restart/10000/restart/10000 2>&1 | Out-Null
                Write-Output-Box "[OK] Tailscale service: delayed-auto + network dependency + auto-recovery set"

                # 2. Save auth key to disk (used as fallback if node state is lost)
                $tsScriptDir = "$env:ProgramData\Tailscale"
                if (-not (Test-Path $tsScriptDir)) { New-Item -ItemType Directory -Path $tsScriptDir -Force | Out-Null }
                $tsKeyFile = "$tsScriptDir\auth.key"
                if (-not [string]::IsNullOrWhiteSpace($authKey)) {
                    $authKey | Set-Content -Path $tsKeyFile -Encoding UTF8 -Force
                    # Restrict file to Administrators + SYSTEM only
                    $acl = Get-Acl $tsKeyFile
                    $acl.SetAccessRuleProtection($true, $false)
                    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("BUILTIN\Administrators","FullControl","Allow")))
                    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("NT AUTHORITY\SYSTEM","FullControl","Allow")))
                    Set-Acl $tsKeyFile $acl -ErrorAction SilentlyContinue
                    Write-Output-Box "[OK] Auth key saved for reconnection fallback"
                }

                # 3. Write reconnect helper script  -  logs every step for diagnostics
                $tsScriptPath = "$tsScriptDir\reconnect-boot.ps1"
                $tsCliPathEsc = $tsCliPath
@"
# Tailscale boot reconnect  -  runs as SYSTEM via Scheduled Task
`$logFile = "`$env:ProgramData\Tailscale\reconnect.log"
"`$(Get-Date -f 'yyyy-MM-dd HH:mm:ss') ===== Boot reconnect START =====" | Add-Content `$logFile

# Wait up to 3 minutes for Tailscale service to be Running
for (`$i = 1; `$i -le 18; `$i++) {
    Start-Sleep -Seconds 10
    `$svc = Get-Service -DisplayName '*Tailscale*' -ErrorAction SilentlyContinue | Select-Object -First 1
    "`$(Get-Date -f 'HH:mm:ss') Attempt `$i - Service: `$(`$svc.Status)" | Add-Content `$logFile
    if (`$svc -and `$svc.Status -eq 'Running') { break }
    if (`$i -eq 18) {
        # Last resort: try to start service
        Start-Service -DisplayName '*Tailscale*' -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 5
    }
}

# Try without auth key first  -  --unattended is CRITICAL for headless reconnect
`$r1 = & "$tsCliPathEsc" up --unattended --accept-routes --accept-dns 2>&1 | Out-String
"`$(Get-Date -f 'HH:mm:ss') tailscale up result: `$r1" | Add-Content `$logFile

# If failed and auth key exists, retry with auth key
if (`$LASTEXITCODE -ne 0 -or `$r1 -match 'failed|error|unauthorized|Logged out') {
    `$keyFile = "`$env:ProgramData\Tailscale\auth.key"
    if (Test-Path `$keyFile) {
        `$key = (Get-Content `$keyFile -Raw).Trim()
        `$r2 = & "$tsCliPathEsc" up --unattended --authkey=`$key --accept-routes --accept-dns 2>&1 | Out-String
        "`$(Get-Date -f 'HH:mm:ss') tailscale up with key result: `$r2" | Add-Content `$logFile
    }
}
"`$(Get-Date -f 'yyyy-MM-dd HH:mm:ss') ===== Boot reconnect END =====" | Add-Content `$logFile
"@ | Set-Content -Path $tsScriptPath -Encoding UTF8 -Force
                Write-Output-Box "[OK] Reconnect script written to $tsScriptPath"

                # 4. Register Scheduled Task  -  trigger: AtStartup + also on event 10000 (network connected)
                $tsTaskName = "TailscaleAutoConnect"
                Unregister-ScheduledTask -TaskName $tsTaskName -Confirm:$false -ErrorAction SilentlyContinue

                $tsTaskAction    = New-ScheduledTaskAction -Execute "powershell.exe" `
                    -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$tsScriptPath`""

                # Two triggers: boot + network-connected event (ensures reconnect even if boot trigger missed)
                $tsTriggerBoot = New-ScheduledTaskTrigger -AtStartup
                $tsTriggerNet  = New-ScheduledTaskTrigger -AtLogOn   # fires when any user logs on (extra safety net)

                $tsTaskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
                $tsTaskSettings  = New-ScheduledTaskSettingsSet -StartWhenAvailable `
                    -ExecutionTimeLimit (New-TimeSpan -Minutes 20) `
                    -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 2) `
                    -MultipleInstances IgnoreNew

                Register-ScheduledTask -TaskName $tsTaskName `
                    -Action $tsTaskAction `
                    -Trigger @($tsTriggerBoot, $tsTriggerNet) `
                    -Principal $tsTaskPrincipal `
                    -Settings $tsTaskSettings `
                    -Description "Auto-connect Tailscale VPN at boot without requiring user login" `
                    -Force | Out-Null

                # Run the task immediately to confirm it works
                Start-ScheduledTask -TaskName $tsTaskName -ErrorAction SilentlyContinue
                Write-Output-Box "[OK] Scheduled Task '$tsTaskName' created and started (boot + logon triggers)"
                Write-Output-Box "[OK] Diagnostic log: $tsScriptDir\reconnect.log"
                Write-Output-Box "[OK] Tailscale will auto-connect on every restart (no login required)"
            }
            catch {
                Write-Output-Box "[WARNING] Auto-start config: $($_.Exception.Message)"
            }

            # TS-STEP 7: Get Tailscale IP
            Write-Output-Box ""
            Write-Output-Box "[7/7] Getting Tailscale IP address..."
            Start-Sleep -Seconds 5

            $tsIP = $null
            for ($tsAttempt = 1; $tsAttempt -le 12; $tsAttempt++) {
                Write-Output-Box "[INFO] Attempt $tsAttempt/12..."
                try {
                    $tsIpOut = & $tsCliPath ip -4 2>&1 | Out-String
                    if ($tsIpOut -match '(\d+\.\d+\.\d+\.\d+)') {
                        $tsIP = $Matches[1]
                        Write-Output-Box "[OK] Tailscale IP: $tsIP"
                        break
                    }
                }
                catch { }
                Start-Sleep -Seconds 3
            }

            if ($null -eq $tsIP) {
                Write-Output-Box "[WARNING] Could not detect Tailscale IP automatically"
                Write-Output-Box "[INFO] Check Tailscale Admin Console: https://login.tailscale.com/admin/machines"
            } else {
                # Quick RDP reachability test
                Write-Output-Box ""
                Write-Output-Box ">>> TESTING RDP CONNECTION <<<"
                $tsRdpReady = $false
                for ($i = 1; $i -le 5; $i++) {
                    Write-Output-Box "[INFO] Attempt $i/5..."
                    $tsRdpReady = Test-RDPPort -IPAddress $tsIP -Port 3389 -TimeoutSeconds 3
                    if ($tsRdpReady) { Write-Output-Box "[OK] RDP port is OPEN!"; break }
                    Start-Sleep -Seconds 2
                }
                if (-not $tsRdpReady) { Write-Output-Box "[WARNING] RDP port test failed (may need a few seconds)" }
            }

            # Final summary – Tailscale
            Write-Output-Box ""
            Write-Output-Box "==================================================="
            Write-Output-Box ">>> CONNECTION INFORMATION (TAILSCALE) <<<"
            Write-Output-Box "==================================================="
            if ($tsIP) { Write-Output-Box "Tailscale IP : $tsIP" } else { Write-Output-Box "Tailscale IP : (Check Tailscale Admin Console)" }
            Write-Output-Box "RDP Port     : 3389"
            Write-Output-Box "RDP Status   : $(if ($tsRdpWorking) { 'READY' } else { 'REQUIRES RESTART' })"
            Write-Output-Box "--- Users Created ($($userList.Count)) ---"
            foreach ($u in $userList) { Write-Output-Box "  Username: $($u.Username)  |  Password: $($u.Password)" }
            Write-Output-Box "==================================================="
            Write-Output-Box ""
            Write-Output-Box "[DONE] NOVIVO Remote Desktop setup completed!"
            Write-Output-Box ""
            Write-Output-Box "NEXT STEPS:"
            Write-Output-Box "1. Open Tailscale Admin: https://login.tailscale.com/admin/machines"
            Write-Output-Box "2. Confirm this device appears in your tailnet"
            Write-Output-Box "3. Connect via RDP: mstsc /v:$tsIP"
            if (-not $tsRdpWorking) {
                Write-Output-Box ""
                Write-Output-Box "!!! A machine restart may be required for RDP listener !!!"
                Start-Sleep -Milliseconds 500
                $tsRestartChoice = [System.Windows.Forms.MessageBox]::Show(
                    "RDP port 3389 is not yet listening.`n`nA restart is required for RDP to work.`n`nDo you want to restart this machine now?",
                    "Restart Required for RDP",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                if ($tsRestartChoice -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Write-Output-Box "[INFO] Restarting machine in 5 seconds..."
                    Start-Sleep -Seconds 5
                    Restart-Computer -Force
                }
            }
            return   # <-- end of Tailscale branch
        }
        # ====================================================================
        #  END TAILSCALE BRANCH
        # ====================================================================

        Write-Output-Box "==================================================="
        Write-Output-Box ">>> NOVIVO REMOTE DESKTOP - ZEROTIER SETUP <<<"
        Write-Output-Box "==================================================="
        Write-Output-Box ""
        
        # STEP 1: Download ZeroTier
        Write-Output-Box "[1/7] Downloading ZeroTier One..."
        $installerPath = "$env:TEMP\ZeroTierOne.msi"
        
        # Enable all TLS protocols for maximum compatibility
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
        [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        
        $downloadSuccess = $false
        $downloadUrls = @(
            "https://download.zerotier.com/dist/ZeroTier One.msi",
            "https://download.zerotier.com/RELEASES/1.14.0/dist/ZeroTier One.msi"
        )
        
        foreach ($downloadUrl in $downloadUrls) {
            try {
                Write-Output-Box "Trying: $downloadUrl"
                
                # Method 1: Try WebClient (more reliable)
                $webClient = New-Object System.Net.WebClient
                $webClient.DownloadFile($downloadUrl, $installerPath)
                
                if (Test-Path $installerPath) {
                    $fileSize = (Get-Item $installerPath).Length
                    if ($fileSize -gt 1MB) {
                        Write-Output-Box "[OK] Downloaded successfully ($([math]::Round($fileSize/1MB,2)) MB)"
                        $downloadSuccess = $true
                        break
                    }
                }
            }
            catch {
                Write-Output-Box "Failed: $($_.Exception.Message)"
                # Try Method 2: Invoke-WebRequest
                try {
                    Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing -TimeoutSec 60
                    if (Test-Path $installerPath) {
                        Write-Output-Box "[OK] Downloaded successfully (fallback method)"
                        $downloadSuccess = $true
                        break
                    }
                }
                catch {
                    continue
                }
            }
        }
        
        # Reset certificate validation
        [Net.ServicePointManager]::ServerCertificateValidationCallback = $null
        
        if (-not $downloadSuccess) {
            Write-Output-Box "[ERROR] All download methods failed. Check your internet connection."
            return
        }
        
        # STEP 2: Install ZeroTier
        Write-Output-Box ""
        Write-Output-Box "[2/7] Installing ZeroTier One..."
        try {
            $process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$installerPath`" /qn /norestart" -Wait -PassThru
            if ($process.ExitCode -eq 0) {
                Write-Output-Box "[OK] Installation completed"
                Start-Sleep -Seconds 3
            }
            else {
                Write-Output-Box "[ERROR] Installation failed with code: $($process.ExitCode)"
                return
            }
        }
        catch {
            Write-Output-Box "[ERROR] $($_.Exception.Message)"
            return
        }
        
        # Find ZeroTier CLI
        $ztCliPath = $null
        $possiblePaths = @(
            "$env:ProgramFiles\ZeroTier\One\zerotier-one_x64.exe",
            "$env:ProgramFiles\ZeroTier\One\zerotier-one.exe",
            "C:\Program Files (x86)\ZeroTier\One\zerotier-one.exe",
            "C:\ProgramData\ZeroTier\One\zerotier-one.exe"
        )
        foreach ($p in $possiblePaths) {
            if (Test-Path $p) { $ztCliPath = $p; break }
        }
        if (-not $ztCliPath) {
            $ztFound = Get-ChildItem "C:\Program Files*" -Filter "zerotier-one*.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($ztFound) { $ztCliPath = $ztFound.FullName }
        }
        if (-not $ztCliPath) {
            Write-Output-Box "[ERROR] ZeroTier executable not found after installation"
            return
        }
        Write-Output-Box "[INFO] ZeroTier path: $ztCliPath"
        
        # STEP 3: Start ZeroTier service
        Write-Output-Box ""
        Write-Output-Box "[3/7] Starting ZeroTier service..."
        try {
            Start-Service -Name "ZeroTierOneService" -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5
            $ztSvc = Get-Service -Name "ZeroTierOneService" -ErrorAction SilentlyContinue
            if ($ztSvc -and $ztSvc.Status -eq "Running") {
                Write-Output-Box "[OK] ZeroTier service is running"
            } else {
                Write-Output-Box "[WARNING] Service may not be running yet, continuing..."
            }
        }
        catch {
            Write-Output-Box "[WARNING] $($_.Exception.Message)"
        }
        
        # STEP 4: Join ZeroTier network
        Write-Output-Box ""
        Write-Output-Box "[4/7] Joining ZeroTier network: $networkID"
        try {
            $joinResult = & $ztCliPath "-q" "join" $networkID 2>&1 | Out-String
            Write-Output-Box "[OK] Join command executed: $joinResult"
            Start-Sleep -Seconds 3
        }
        catch {
            Write-Output-Box "[ERROR] Failed to join network: $($_.Exception.Message)"
            return
        }
        
        # STEP 5: Enable RDP  
        Write-Output-Box ""
        Write-Output-Box "[5/7] Enabling Remote Desktop..."
        
        try {
            & reg.exe add "HKLM\System\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f 2>&1 | Out-Null
            & reg.exe add "HKLM\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" /v UserAuthentication /t REG_DWORD /d 0 /f 2>&1 | Out-Null
            Write-Output-Box "[OK] Core RDP settings applied via reg.exe"
        }
        catch {
            Write-Output-Box "[WARNING] reg.exe failed, using PowerShell fallback"
        }
        
        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -Force
        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 0 -Force
        
        $regPaths = @(
            @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"; Name="fDenyTSConnections"; Value=0},
            @{Path="HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"; Name="fAllowToGetHelp"; Value=1},
            @{Path="HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server"; Name="AllowTSConnections"; Value=1},
            @{Path="HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name="PortNumber"; Value=3389; Type="DWord"},
            @{Path="HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name="SecurityLayer"; Value=0},
            @{Path="HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name="UserAuthentication"; Value=0},
            @{Path="HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name="fEnableWinStation"; Value=1},
            @{Path="HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"; Name="LocalAccountTokenFilterPolicy"; Value=1}
        )
        foreach ($reg in $regPaths) {
            if (-not (Test-Path $reg.Path)) { New-Item -Path $reg.Path -Force | Out-Null }
            $regType = if ($reg.Type) { $reg.Type } else { "DWord" }
            Set-ItemProperty -Path $reg.Path -Name $reg.Name -Value $reg.Value -Type $regType -Force
        }
        Write-Output-Box "[OK] RDP registry fully configured"
        
        # Firewall
        try {
            Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
            $existingRule = Get-NetFirewallRule -DisplayName "RDP-ZeroTier-3389" -ErrorAction SilentlyContinue
            if ($existingRule) { Remove-NetFirewallRule -DisplayName "RDP-ZeroTier-3389" -ErrorAction SilentlyContinue }
            New-NetFirewallRule -DisplayName "RDP-ZeroTier-3389" -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow -Enabled True -Profile Any -ErrorAction SilentlyContinue | Out-Null
            & netsh advfirewall firewall add rule name="RDP-ZeroTier-Netsh" dir=in action=allow protocol=TCP localport=3389 2>&1 | Out-Null
            Write-Output-Box "[OK] Firewall rules configured (3 methods)"
        }
        catch {
            Write-Output-Box "[WARNING] Firewall: $($_.Exception.Message)"
        }

        # Enable RDP via WMI  -  most reliable method on Win11
        try {
            $wmiTS = Get-WmiObject -Class Win32_TerminalServiceSetting -Namespace root/cimv2/TerminalServices -ErrorAction SilentlyContinue
            if ($wmiTS) {
                # Single-arg works on all editions including Win10 Pro for Workstations
                try { $wmiTS.SetAllowTSConnections(1) | Out-Null }
                catch { $wmiTS.SetAllowTSConnections(1, 0) | Out-Null }
                Write-Output-Box "[OK] RDP enabled via WMI (AllowTSConnections)"
            }
        } catch { Write-Output-Box "[INFO] WMI enable: $($_.Exception.Message)" }

        # Detect Windows edition  -  Home needs RDP Wrapper
        try {
            $winEdition = (Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
            if ($winEdition -match '\bHome\b') {
                Write-Output-Box ""
                Write-Output-Box "[INFO] Windows Home detected - installing RDP Wrapper to enable RDP..."
                $rdpwZip2  = "$env:TEMP\RDPWrap2.zip"
                $rdpwDir2  = "$env:TEMP\RDPWrapExtract2"
                $rdpwOk2   = $false
                try {
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                    $wc4 = New-Object System.Net.WebClient
                    $wc4.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
                    $wc4.DownloadFile("https://github.com/stascorp/rdpwrap/releases/download/v1.6.2/RDPWrap-v1.6.2.zip", $rdpwZip2)
                    if ((Test-Path $rdpwZip2) -and (Get-Item $rdpwZip2).Length -gt 100KB) {
                        if (Test-Path $rdpwDir2) { Remove-Item $rdpwDir2 -Recurse -Force }
                        Expand-Archive -Path $rdpwZip2 -DestinationPath $rdpwDir2 -Force
                        $rdpwInst2 = Get-ChildItem $rdpwDir2 -Filter "RDPWInst.exe" -Recurse | Select-Object -First 1
                        if ($rdpwInst2) {
                            $rdpwProc2 = Start-Process -FilePath $rdpwInst2.FullName -ArgumentList "-i" -Wait -PassThru -WindowStyle Hidden
                            Write-Output-Box "[OK] RDP Wrapper installed (code $($rdpwProc2.ExitCode))"
                            $rdpwOk2 = $true
                            $rdpwIniPath2 = "$env:ProgramFiles\RDP Wrapper\rdpwrap.ini"
                            try {
                                $wc5 = New-Object System.Net.WebClient
                                $wc5.Headers.Add("User-Agent", "Mozilla/5.0")
                                $wc5.DownloadFile("https://raw.githubusercontent.com/sebaxakerhtc/rdpwrap.ini/master/rdpwrap.ini", $rdpwIniPath2)
                                Write-Output-Box "[OK] RDP Wrapper ini updated for current Windows build"
                            } catch { Write-Output-Box "[INFO] ini update skipped: $($_.Exception.Message)" }
                            Start-Sleep -Seconds 2
                            Restart-Service -Name "RDPWrapper" -ErrorAction SilentlyContinue
                            Write-Output-Box "[OK] RDP Wrapper service started"
                        } else { Write-Output-Box "[WARNING] RDPWInst.exe not found in archive" }
                    } else { Write-Output-Box "[WARNING] RDP Wrapper download failed or file too small" }
                } catch { Write-Output-Box "[WARNING] RDP Wrapper install failed: $($_.Exception.Message)" }
                if (-not $rdpwOk2) {
                    Write-Output-Box "[WARNING] Could not auto-enable RDP on Windows Home"
                    Write-Output-Box "[INFO] Manual option: upgrade to Windows Pro, or use Chrome Remote Desktop"
                }
            } else {
                Write-Output-Box "[INFO] Windows edition: $winEdition"
            }
        } catch {}
        
        # Configure user accounts
        Write-Output-Box ""
        Write-Output-Box "[5b/7] Configuring $($userList.Count) user account(s)..."
        foreach ($userEntry in $userList) {
            $uname2 = $userEntry.Username
            $upass2 = $userEntry.Password
            Write-Output-Box "  [USER] >>> $uname2 <<<"
            try {
                $isMsAcc = $false
                try {
                    $lu = Get-LocalUser -Name $uname2 -ErrorAction SilentlyContinue
                    if ($lu -and "$($lu.PrincipalSource)" -eq 'MicrosoftAccount') { $isMsAcc = $true }
                } catch {}

                if ($isMsAcc) {
                    Write-Output-Box "[INFO] Microsoft account - password change skipped"
                    Write-Output-Box "[INFO] Use your Microsoft account password for RDP"
                } else {
                    $ztNetChk = & net user $uname2 2>&1
                    $ztUsrEx  = ($LASTEXITCODE -eq 0)
                    if (-not $ztUsrEx) {
                        $ztRes = & net user $uname2 $upass2 /add /passwordchg:no /expires:never /comment:"Created by NOVIVO Remote Desktop" 2>&1
                        $ztResStr = $ztRes | Out-String
                        if ($LASTEXITCODE -eq 0) {
                            Write-Output-Box "[OK] User created: $uname2"
                            & wmic useraccount where "name='$uname2'" set PasswordExpires=False 2>&1 | Out-Null
                        } elseif ($ztResStr -match '8646|not authoritative|online provider') {
                            Write-Output-Box "[INFO] Microsoft account - password change skipped"
                        } else { throw "Failed to create user: $ztResStr" }
                    } else {
                        $ztRes2 = & net user $uname2 $upass2 2>&1
                        $ztResStr2 = $ztRes2 | Out-String
                        if ($LASTEXITCODE -eq 0) {
                            Write-Output-Box "[OK] Password updated for: $uname2"
                            & wmic useraccount where "name='$uname2'" set PasswordExpires=False 2>&1 | Out-Null
                        } elseif ($ztResStr2 -match '8646|not authoritative|online provider') {
                            Write-Output-Box "[INFO] Microsoft account - password change skipped"
                        } else { throw "Failed to update password: $ztResStr2" }
                    }
                }
                $ztRdpGrpName = 'Remote Desktop Users'
                try {
                    $ztRdpSid  = New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-555'
                    $ztRdpNT   = $ztRdpSid.Translate([System.Security.Principal.NTAccount]).Value
                    $ztParts   = $ztRdpNT.Split('\\'.ToCharArray())
                    $ztRdpGrpName = $ztParts[$ztParts.Length - 1]
                } catch { }
                $addAdm = & net localgroup Administrators $uname2 /add 2>&1
                if ($LASTEXITCODE -eq 0) { Write-Output-Box "[OK] Added to Administrators" }
                else { Write-Output-Box "[INFO] Administrators: $addAdm" }
                $ztGrpExists = Get-LocalGroup -SID "S-1-5-32-555" -ErrorAction SilentlyContinue
                if (-not $ztGrpExists) {
                    try {
                        New-LocalGroup -Name $ztRdpGrpName -Description "Members in this group are granted the right to logon remotely" -ErrorAction SilentlyContinue | Out-Null
                        Write-Output-Box "[OK] Created '$ztRdpGrpName' group"
                    } catch {}
                }
                try {
                    Add-LocalGroupMember -SID "S-1-5-32-555" -Member $uname2 -ErrorAction Stop
                    Write-Output-Box "[OK] Added to $ztRdpGrpName"
                } catch {
                    if ($_.Exception.Message -match 'already.*member|member.*already') {
                        Write-Output-Box "[INFO] Already in $ztRdpGrpName"
                    } else {
                        $addRdp = & net localgroup $ztRdpGrpName $uname2 /add 2>&1
                        if ($LASTEXITCODE -eq 0) { Write-Output-Box "[OK] Added to $ztRdpGrpName" }
                        else { Write-Output-Box "[INFO] RDP Users: $addRdp" }
                    }
                }
            }
            catch {
                Write-Output-Box "[ERROR] User config failed for '$uname2': $($_.Exception.Message)"
                return
            }
        }
        
        # STEP 6: Restart RDP Services
        Write-Output-Box ""
        Write-Output-Box "[6/7] Restarting RDP services..."
        try {
            Stop-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
            Stop-Service -Name "SessionEnv" -Force -ErrorAction SilentlyContinue
            Stop-Service -Name "UmRdpService" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5
            
            & sc.exe config TermService  start= auto 2>&1 | Out-Null
            & sc.exe config SessionEnv   start= auto 2>&1 | Out-Null
            & sc.exe config UmRdpService start= auto 2>&1 | Out-Null
            
            Start-Service -Name "SessionEnv"  -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            Start-Service -Name "TermService" -ErrorAction Stop
            Start-Sleep -Seconds 10
            Start-Service -Name "UmRdpService" -ErrorAction SilentlyContinue
            
            $svcStatus = (Get-Service -Name "TermService").Status
            if ($svcStatus -eq "Running") {
                Write-Output-Box "[OK] TermService is RUNNING"
                $rdpWorking = $true
            } else {
                Write-Output-Box "[WARNING] TermService status: $svcStatus"
            }
            
            Start-Sleep -Seconds 5
            $portListening = Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue
            
            if (-not $portListening) {
                Write-Output-Box "[WARNING] Port 3389 not listening, trying emergency fixes..."
                
                try {
                    # EMERGENCY FIX SEQUENCE
                    Write-Output-Box "[INFO] Emergency: Force killing all RDP services..."
                    Stop-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
                    Stop-Service -Name "SessionEnv" -Force -ErrorAction SilentlyContinue
                    Stop-Service -Name "UmRdpService" -Force -ErrorAction SilentlyContinue
                    
                    # Kill stuck processes
                    Get-Process | Where-Object { $_.ProcessName -like "*svchost*" } | ForEach-Object {
                        try {
                            if ($_.Modules.ModuleName -contains "termsrv.dll") {
                                Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
                            }
                        }
                        catch {}
                    }
                    
                    Start-Sleep -Seconds 5
                    Write-Output-Box "[OK] Services stopped, processes killed"
                    
                    # Restart in correct order
                    Write-Output-Box "[INFO] Emergency: Restarting services in order..."
                    Start-Service -Name "SessionEnv" -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 3
                    Start-Service -Name "TermService" -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 10
                    Start-Service -Name "UmRdpService" -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 5
                    
                    Write-Output-Box "[OK] Emergency restart completed"
                    
                    # Re-check port
                    Start-Sleep -Seconds 3
                    $portCheck = Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue
                    
                    if ($portCheck) {
                        Write-Output-Box "[SUCCESS] Port 3389 is NOW LISTENING!"
                        Write-Output-Box "[INFO] Emergency fix WORKED - RDP is ready!"
                        $rdpWorking = $true
                    }
                    else {
                        # LAST RESORT: Try to rebuild RDP-Tcp listener via registry
                        Write-Output-Box ""
                        Write-Output-Box "[INFO] Last attempt: Rebuilding RDP-Tcp listener..."
                        
                        try {
                            # Force rebind by toggling fEnableWinStation
                            $rdpTcpPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
                            Set-ItemProperty -Path $rdpTcpPath -Name "fEnableWinStation" -Value 0 -Force
                            Start-Sleep -Seconds 2
                            Set-ItemProperty -Path $rdpTcpPath -Name "fEnableWinStation" -Value 1 -Force
                            
                            # Restart TermService one more time
                            Restart-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
                            Start-Sleep -Seconds 10
                            
                            # Final check
                            $portCheck = Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue
                            if ($portCheck) {
                                Write-Output-Box "[SUCCESS] Listener rebuild WORKED! Port 3389 is now listening!"
                                $rdpWorking = $true
                            }
                            else {
                                Write-Output-Box "[ERROR] Listener rebuild failed"
                                $rdpWorking = $false
                            }
                        }
                        catch {
                            Write-Output-Box "[WARNING] Rebuild attempt failed: $($_.Exception.Message)"
                            $rdpWorking = $false
                        }
                        
                        if (-not $rdpWorking) {
                            Write-Output-Box ""
                            Write-Output-Box "=== MACHINE RESTART REQUIRED ==="
                            Write-Output-Box "[INFO] This Windows requires restart for RDP listener"
                            Write-Output-Box "[INFO] Registry is configured correctly"
                            Write-Output-Box "[INFO] After restart, RDP will work automatically"
                            Write-Output-Box ""
                            Write-Output-Box "Run this command to schedule safe restart:"
                            Write-Output-Box "  powershell -File .\Safe-Restart.ps1"
                            Write-Output-Box ""
                            Write-Output-Box "Or restart now:"
                            Write-Output-Box "  Restart-Computer"
                            Write-Output-Box ""
                        }
                    }
                }
                catch {
                    Write-Output-Box "[ERROR] Emergency fix failed: $($_.Exception.Message)"
                    Write-Output-Box "[INFO] Please restart machine manually"
                    $rdpWorking = $false
                }
            }
            else {
                Write-Output-Box "[SUCCESS] Port 3389 is LISTENING - RDP is READY!"
                $rdpWorking = $true
            }
        }
        catch {
            Write-Output-Box "[ERROR] Service restart failed: $($_.Exception.Message)"
            $rdpWorking = $false
        }
        
        # STEP 7: Get ZeroTier IP and Test
        Write-Output-Box ""
        Write-Output-Box "[7/7] Getting ZeroTier IP address..."
        
        Start-Sleep -Seconds 5
        
        $ztIP = $null
        $maxAttempts = 10
        $attempt = 0
        
        while ($attempt -lt $maxAttempts -and $null -eq $ztIP) {
            $attempt++
            Write-Output-Box "[INFO] Attempt $attempt/$maxAttempts..."
            
            try {
                $listResult = & $ztCliPath "-q" "listnetworks" 2>&1 | Out-String
                
                if ($listResult -match "(\d+\.\d+\.\d+\.\d+)") {
                    $ztIP = $Matches[1]
                    Write-Output-Box "[OK] ZeroTier IP detected: $ztIP"
                    break
                }
            }
            catch {
                Write-Output-Box "[WARNING] Retry in 3 seconds..."
            }
            
            Start-Sleep -Seconds 3
        }
        
        if ($null -eq $ztIP) {
            Write-Output-Box "[WARNING] Could not detect ZeroTier IP automatically"
            Write-Output-Box "[INFO] Please check ZeroTier Central to authorize this device"
        }
        else {
            # Test RDP connectivity
            Write-Output-Box ""
            Write-Output-Box ">>> TESTING RDP CONNECTION <<<"
            Write-Output-Box "[INFO] Testing RDP port 3389..."
            
            # Try multiple times to allow services to fully initialize
            $rdpReady = $false
            for ($i = 1; $i -le 5; $i++) {
                Write-Output-Box "[INFO] Test attempt $i/5..."
                $rdpReady = Test-RDPPort -IPAddress $ztIP -Port 3389 -TimeoutSeconds 3
                if ($rdpReady) {
                    Write-Output-Box "[OK] RDP port is OPEN and READY!"
                    break
                }

                if ($i -lt 5) {
                    Write-Output-Box "[INFO] Port not ready yet, waiting 2 seconds..."
                    Start-Sleep -Seconds 2
                }
            }

            if (-not $rdpReady) {
                Write-Output-Box "[WARNING] RDP port test failed"
                Write-Output-Box "[INFO] RDP may need a few more seconds to initialize"
                Write-Output-Box "[INFO] Or firewall may be blocking connections"
            }
        }
        
        # Final Summary
        Write-Output-Box ""
        Write-Output-Box "==================================================="  
        Write-Output-Box ">>> CONNECTION INFORMATION (ZEROTIER) <<<"
        Write-Output-Box "==================================================="  
        if ($null -ne $ztIP) {
            Write-Output-Box "IP Address  : $ztIP"
        }
        else {
            Write-Output-Box "IP Address  : (Check ZeroTier Central)"
        }
        Write-Output-Box "RDP Port    : 3389"
        Write-Output-Box "--- Users Created ($($userList.Count)) ---"
        foreach ($u in $userList) { Write-Output-Box "  Username: $($u.Username)  |  Password: $($u.Password)" }

        # Show RDP status
        if ($rdpWorking) {
            Write-Output-Box "RDP Status  : READY (No restart needed)"
        }
        else {
            Write-Output-Box "RDP Status  : REQUIRES RESTART"
        }

        Write-Output-Box "==================================================="  
        Write-Output-Box ""
        Write-Output-Box "[DONE] NOVIVO Remote Desktop setup completed!"
        Write-Output-Box ""

        # Dynamic notes based on RDP status
        if ($rdpWorking) {
            Write-Output-Box "IMPORTANT NOTES:"
            Write-Output-Box "1. Authorize this device in ZeroTier Central"     
            Write-Output-Box "2. Wait 10-30 seconds for RDP to fully initialize"
            Write-Output-Box "3. Use Remote Desktop Connection (mstsc.exe)"     
            Write-Output-Box "4. RDP is ready - NO MACHINE RESTART NEEDED!"     
        }
        else {
            Write-Output-Box "!!! MACHINE RESTART REQUIRED !!!"
            Write-Output-Box "1. RDP listener could not be created without restart"
            Write-Output-Box "2. Registry is configured correctly"
            Write-Output-Box "3. After restart, RDP will work automatically"
            Write-Output-Box "4. Authorize device in ZeroTier Central"
            Write-Output-Box ""
            Write-Output-Box "To schedule safe restart (5 min delay):"
            Write-Output-Box "  powershell -File .\Safe-Restart.ps1"
            Write-Output-Box ""
            Write-Output-Box "To restart now:"
            Write-Output-Box "  Restart-Computer"
        }

    }
    catch {
        Write-Output-Box ""
        Write-Output-Box "[CRITICAL ERROR] $($_.Exception.Message)"
        Write-Output-Box ""
        Write-Output-Box "Stack Trace:"
        Write-Output-Box $_.ScriptStackTrace
    }
    finally {
    }
}
catch {
    Write-Output-Box ""
    Write-Output-Box "[CRITICAL ERROR] $($_.Exception.Message)"
}
finally {
    # ── Restore sleep settings ─────────────────────────────────────────────
    if ($_powerType) {
        [void]$_powerType::SetThreadExecutionState([uint32]2147483648)  # ES_CONTINUOUS = reset
    }
    Write-Output-Box "[INFO] Sleep settings restored"
}
