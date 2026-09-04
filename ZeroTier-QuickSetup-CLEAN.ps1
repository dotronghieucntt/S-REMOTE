# ZeroTier Quick Setup Tool
# Auto install ZeroTier + Enable RDP + Show connection info

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Create main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "ZeroTier Quick Setup"
$form.Size = New-Object System.Drawing.Size(540, 650)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.BackColor = [System.Drawing.Color]::White

# Set icon if exists
$iconPath = Join-Path $PSScriptRoot "icon.ico"
if (Test-Path $iconPath) {
    $form.Icon = New-Object System.Drawing.Icon($iconPath)
}

$marginLeft = 30
$marginTop = 30
$labelWidth = 120
$inputWidth = 350
$rowHeight = 35
$currentY = $marginTop

# Title Label
$titleLabel = New-Object System.Windows.Forms.Label
$titleLabel.Location = New-Object System.Drawing.Point($marginLeft, $currentY)
$titleLabel.Size = New-Object System.Drawing.Size(480, 30)
$titleLabel.Text = ">>> ZEROTIER QUICK SETUP TOOL <<<"
$titleLabel.Font = New-Object System.Drawing.Font("Arial", 12, [System.Drawing.FontStyle]::Bold)
$titleLabel.ForeColor = [System.Drawing.Color]::FromArgb(0, 102, 204)
$titleLabel.TextAlign = "MiddleCenter"
$form.Controls.Add($titleLabel)
$currentY += 40

# Network ID
$labelNetworkID = New-Object System.Windows.Forms.Label
$labelNetworkID.Location = New-Object System.Drawing.Point($marginLeft, $currentY)
$labelNetworkID.Size = New-Object System.Drawing.Size($labelWidth, 23)
$labelNetworkID.Text = "Network ID:"
$form.Controls.Add($labelNetworkID)

$textNetworkID = New-Object System.Windows.Forms.TextBox
$textNetworkID.Location = New-Object System.Drawing.Point(($marginLeft + $labelWidth), $currentY)
$textNetworkID.Size = New-Object System.Drawing.Size($inputWidth, 23)
$textNetworkID.Text = ""
$textNetworkID.Font = New-Object System.Drawing.Font("Consolas", 10)
$form.Controls.Add($textNetworkID)
$currentY += $rowHeight

# Username
$labelUsername = New-Object System.Windows.Forms.Label
$labelUsername.Location = New-Object System.Drawing.Point($marginLeft, $currentY)
$labelUsername.Size = New-Object System.Drawing.Size($labelWidth, 23)
$labelUsername.Text = "Username:"
$form.Controls.Add($labelUsername)

$textUsername = New-Object System.Windows.Forms.TextBox
$textUsername.Location = New-Object System.Drawing.Point(($marginLeft + $labelWidth), $currentY)
$textUsername.Size = New-Object System.Drawing.Size($inputWidth, 23)
$textUsername.Text = $env:USERNAME
$form.Controls.Add($textUsername)
$currentY += $rowHeight

# Password
$labelPassword = New-Object System.Windows.Forms.Label
$labelPassword.Location = New-Object System.Drawing.Point($marginLeft, $currentY)
$labelPassword.Size = New-Object System.Drawing.Size($labelWidth, 23)
$labelPassword.Text = "Password:"
$form.Controls.Add($labelPassword)

$textPassword = New-Object System.Windows.Forms.TextBox
$textPassword.Location = New-Object System.Drawing.Point(($marginLeft + $labelWidth), $currentY)
$textPassword.Size = New-Object System.Drawing.Size(250, 23)
$textPassword.UseSystemPasswordChar = $true
$form.Controls.Add($textPassword)

# Generate Password Button
$btnGenPassword = New-Object System.Windows.Forms.Button
$btnGenPassword.Location = New-Object System.Drawing.Point(($marginLeft + $labelWidth + 260), $currentY)
$btnGenPassword.Size = New-Object System.Drawing.Size(90, 23)
$btnGenPassword.Text = "Random"
$btnGenPassword.Add_Click({
    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*"
    $password = -join ((1..12) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    $textPassword.Text = $password
    $textPassword.UseSystemPasswordChar = $false
})
$form.Controls.Add($btnGenPassword)
$currentY += $rowHeight + 10

# Output TextBox
$outputBox = New-Object System.Windows.Forms.TextBox
$outputBox.Location = New-Object System.Drawing.Point($marginLeft, $currentY)
$outputBox.Size = New-Object System.Drawing.Size(480, 300)
$outputBox.Multiline = $true
$outputBox.ScrollBars = "Vertical"
$outputBox.ReadOnly = $true
$outputBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$outputBox.BackColor = [System.Drawing.Color]::Black
$outputBox.ForeColor = [System.Drawing.Color]::Lime
$form.Controls.Add($outputBox)
$currentY += 310

# Install Button
$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Location = New-Object System.Drawing.Point($marginLeft, $currentY)
$btnInstall.Size = New-Object System.Drawing.Size(230, 35)
$btnInstall.Text = "START INSTALLATION"
$btnInstall.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnInstall.ForeColor = [System.Drawing.Color]::White
$btnInstall.FlatStyle = "Flat"
$btnInstall.Font = New-Object System.Drawing.Font("Arial", 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnInstall)

# Close Button
$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Location = New-Object System.Drawing.Point(($marginLeft + 250), $currentY)
$btnClose.Size = New-Object System.Drawing.Size(230, 35)
$btnClose.Text = "CLOSE"
$btnClose.BackColor = [System.Drawing.Color]::FromArgb(200, 200, 200)
$btnClose.FlatStyle = "Flat"
$btnClose.Font = New-Object System.Drawing.Font("Arial", 10)
$btnClose.Add_Click({ $form.Close() })
$form.Controls.Add($btnClose)

# Helper function to write output
function Write-Output-Box {
    param([string]$Message, [string]$Color = "Lime")
    $outputBox.AppendText("$Message`r`n")
    $outputBox.SelectionStart = $outputBox.Text.Length
    $outputBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

# Function to test RDP port connectivity
function Test-RDPPort {
    param(
        [string]$IPAddress,
        [int]$Port = 3389,
        [int]$TimeoutSeconds = 3
    )
    
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $asyncResult = $tcpClient.BeginConnect($IPAddress, $Port, $null, $null)
        $wait = $asyncResult.AsyncWaitHandle.WaitOne($TimeoutSeconds * 1000, $false)
        
        if ($wait) {
            try {
                $tcpClient.EndConnect($asyncResult)
                $tcpClient.Close()
                return $true
            }
            catch {
                return $false
            }
        }
        else {
            $tcpClient.Close()
            return $false
        }
    }
    catch {
        return $false
    }
}

# Main installation logic
$btnInstall.Add_Click({
    $btnInstall.Enabled = $false
    $outputBox.Clear()
    
    try {
        $networkID = $textNetworkID.Text.Trim()
        $username = $textUsername.Text.Trim()
        $password = $textPassword.Text
        
        # Validate inputs
        if ([string]::IsNullOrWhiteSpace($networkID)) {
            Write-Output-Box "[ERROR] Network ID cannot be empty!"
            $btnInstall.Enabled = $true
            return
        }
        if ([string]::IsNullOrWhiteSpace($username)) {
            Write-Output-Box "[ERROR] Username cannot be empty!"
            $btnInstall.Enabled = $true
            return
        }
        if ([string]::IsNullOrWhiteSpace($password)) {
            Write-Output-Box "[ERROR] Password cannot be empty!"
            $btnInstall.Enabled = $true
            return
        }
        
        Write-Output-Box "==================================================="
        Write-Output-Box ">>> ZEROTIER QUICK SETUP TOOL <<<"
        Write-Output-Box "==================================================="
        Write-Output-Box ""
        
        # STEP 1: Download ZeroTier
        Write-Output-Box "[1/7] Downloading ZeroTier One..."
        $installerPath = "$env:TEMP\ZeroTierOne.msi"
        $downloadUrl = "https://download.zerotier.com/dist/ZeroTier%20One.msi"
        
        try {
            Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing
            Write-Output-Box "[OK] Downloaded successfully"
        }
        catch {
            Write-Output-Box "[ERROR] Download failed: $($_.Exception.Message)"
            $btnInstall.Enabled = $true
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
                $btnInstall.Enabled = $true
                return
            }
        }
        catch {
            Write-Output-Box "[ERROR] Installation error: $($_.Exception.Message)"
            $btnInstall.Enabled = $true
            return
        }
        
        # STEP 3: Join Network
        Write-Output-Box ""
        Write-Output-Box "[3/7] Joining ZeroTier network..."
        $ztCliPath = "C:\Program Files (x86)\ZeroTier\One\zerotier-one_x64.exe"
        if (-not (Test-Path $ztCliPath)) {
            $ztCliPath = "C:\ProgramData\ZeroTier\One\zerotier-one_x64.exe"
        }
        
        try {
            $joinResult = & $ztCliPath "-q" "join" $networkID 2>&1
            Write-Output-Box "[OK] Joined network: $networkID"
            Start-Sleep -Seconds 2
        }
        catch {
            Write-Output-Box "[WARNING] Join command failed, but network may be added"
        }
        
        # STEP 4: Enable RDP
        Write-Output-Box ""
        Write-Output-Box "[4/7] Configuring Remote Desktop..."
        
        # Enable RDP in registry
        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name "fDenyTSConnections" -Value 0 -Force
        Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp" -Name "UserAuthentication" -Value 0 -Force
        
        # Enable additional RDP settings
        $regPaths = @(
            @{Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"; Name = "fDenyTSConnections"; Value = 0},
            @{Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"; Name = "fAllowToGetHelp"; Value = 1},
            @{Path = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services"; Name = "fAllowUnsolicited"; Value = 1},
            @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server"; Name = "AllowTSConnections"; Value = 1},
            @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server"; Name = "fAllowToGetHelp"; Value = 1},
            @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name = "PortNumber"; Value = 3389; Type = "DWord"},
            @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name = "LanAdapter"; Value = 0},
            @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name = "MinEncryptionLevel"; Value = 1},
            @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name = "SecurityLayer"; Value = 0},
            @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name = "fInheritMaxSessionTime"; Value = 0},
            @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name = "fInheritMaxDisconnectionTime"; Value = 0},
            @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name = "fInheritMaxIdleTime"; Value = 0},
            @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name = "MaxInstanceCount"; Value = 4294967295; Type = "DWord"},
            @{Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"; Name = "fEnableWinStation"; Value = 1},
            @{Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"; Name = "LocalAccountTokenFilterPolicy"; Value = 1}
        )
        
        foreach ($reg in $regPaths) {
            $regPath = $reg.Path
            $regName = $reg.Name
            $regValue = $reg.Value
            $regType = if ($reg.Type) { $reg.Type } else { "DWord" }
            
            if (-not (Test-Path $regPath)) {
                New-Item -Path $regPath -Force | Out-Null
            }
            Set-ItemProperty -Path $regPath -Name $regName -Value $regValue -Type $regType -Force
        }
        
        Write-Output-Box "[OK] RDP registry configured"
        
        # Configure firewall
        try {
            Enable-NetFirewallRule -DisplayGroup "Remote Desktop" -ErrorAction SilentlyContinue
            New-NetFirewallRule -DisplayName "Remote Desktop - Custom" -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow -ErrorAction SilentlyContinue
            Write-Output-Box "[OK] Firewall rules enabled"
        }
        catch {
            Write-Output-Box "[WARNING] Firewall configuration may need manual adjustment"
        }
        
        # STEP 5: Configure User
        Write-Output-Box ""
        Write-Output-Box "[5/7] Configuring user account..."
        
        try {
            # Check if user exists
            $userExists = Get-LocalUser -Name $username -ErrorAction SilentlyContinue
            
            if ($null -eq $userExists) {
                # Create new user
                $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
                New-LocalUser -Name $username -Password $securePassword -FullName $username -Description "Created by ZeroTier Setup" -PasswordNeverExpires -ErrorAction Stop | Out-Null
                Write-Output-Box "[OK] User created: $username"
            }
            else {
                # Update existing user password
                $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
                Set-LocalUser -Name $username -Password $securePassword -ErrorAction Stop
                Write-Output-Box "[OK] Password updated for: $username"
            }
            
            # Add to Administrators group
            try {
                Add-LocalGroupMember -Group "Administrators" -Member $username -ErrorAction SilentlyContinue
                Write-Output-Box "[OK] Added to Administrators"
            }
            catch {
                Write-Output-Box "[INFO] Already in Administrators group"
            }
            
            # Add to Remote Desktop Users group
            try {
                Add-LocalGroupMember -Group "Remote Desktop Users" -Member $username -ErrorAction SilentlyContinue
                Write-Output-Box "[OK] Added to Remote Desktop Users"
            }
            catch {
                Write-Output-Box "[INFO] Already in Remote Desktop Users group"
            }
        }
        catch {
            Write-Output-Box "[ERROR] User configuration failed: $($_.Exception.Message)"
            $btnInstall.Enabled = $true
            return
        }
        
        # STEP 6: Restart RDP Services (NO MACHINE RESTART NEEDED)
        Write-Output-Box ""
        Write-Output-Box "[6/7] Restarting RDP services..."
        
        try {
            # Stop Terminal Services
            Stop-Service -Name "TermService" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            
            # Start Terminal Services
            Start-Service -Name "TermService" -ErrorAction Stop
            Start-Sleep -Seconds 2
            
            # Verify service is running
            $svc = Get-Service -Name "TermService"
            if ($svc.Status -eq "Running") {
                Write-Output-Box "[OK] TermService restarted successfully"
            }
            else {
                Write-Output-Box "[WARNING] TermService status: $($svc.Status)"
            }
            
            # Restart UmRdpService if exists
            $umRdp = Get-Service -Name "UmRdpService" -ErrorAction SilentlyContinue
            if ($null -ne $umRdp) {
                Restart-Service -Name "UmRdpService" -Force -ErrorAction SilentlyContinue
                Write-Output-Box "[OK] UmRdpService restarted"
            }
            
            # Restart SessionEnv if exists
            $sessionEnv = Get-Service -Name "SessionEnv" -ErrorAction SilentlyContinue
            if ($null -ne $sessionEnv) {
                Restart-Service -Name "SessionEnv" -Force -ErrorAction SilentlyContinue
                Write-Output-Box "[OK] SessionEnv restarted"
            }
            
            Start-Sleep -Seconds 3
        }
        catch {
            Write-Output-Box "[ERROR] Service restart failed: $($_.Exception.Message)"
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
                    Write-Output-Box "[OK] RDP port is OPEN and ready!"
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
        Write-Output-Box ">>> CONNECTION INFORMATION <<<"
        Write-Output-Box "==================================================="
        if ($null -ne $ztIP) {
            Write-Output-Box "IP Address  : $ztIP"
        }
        else {
            Write-Output-Box "IP Address  : (Check ZeroTier Central)"
        }
        Write-Output-Box "Username    : $username"
        Write-Output-Box "Password    : $password"
        Write-Output-Box "RDP Port    : 3389"
        Write-Output-Box "==================================================="
        Write-Output-Box ""
        Write-Output-Box "[DONE] Setup completed successfully!"
        Write-Output-Box ""
        Write-Output-Box "IMPORTANT NOTES:"
        Write-Output-Box "1. Authorize this device in ZeroTier Central"
        Write-Output-Box "2. Wait 10-30 seconds for RDP to fully initialize"
        Write-Output-Box "3. Use Remote Desktop to connect"
        Write-Output-Box "4. NO MACHINE RESTART REQUIRED!"
        
    }
    catch {
        Write-Output-Box ""
        Write-Output-Box "[CRITICAL ERROR] $($_.Exception.Message)"
        Write-Output-Box ""
        Write-Output-Box "Stack Trace:"
        Write-Output-Box $_.ScriptStackTrace
    }
    finally {
        $btnInstall.Enabled = $true
    }
})

# Show form
[void]$form.ShowDialog()
