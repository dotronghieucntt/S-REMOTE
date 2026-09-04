# NOVIVO Remote Desktop Setup Tool
# Auto install Tailscale/ZeroTier + Enable RDP + Show connection info

# ── Self-elevate to Administrator if not already ──────────────────────────────
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $scriptPath = $MyInvocation.MyCommand.Path
    if (-not $scriptPath) { $scriptPath = $PSCommandPath }
    Start-Process -FilePath "powershell.exe" -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    exit
}
# ─────────────────────────────────────────────────────────────────────────────

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

# ═══════════════════════════════════════════════════════════════════════════════
#  THEME  ── NOVIVO Ember (charcoal + amber)
# ═══════════════════════════════════════════════════════════════════════════════
$clrBg        = [System.Drawing.Color]::FromArgb(14, 12, 10)        # Deep navy background
$clrCard      = [System.Drawing.Color]::FromArgb(22, 20, 16)        # Card / group background
$clrCardAlt   = [System.Drawing.Color]::FromArgb(18, 16, 13)        # Slightly darker card
$clrBorder    = [System.Drawing.Color]::FromArgb(55, 46, 32)        # Subtle border
$clrHeader    = [System.Drawing.Color]::FromArgb(10, 9, 7)        # Header panel background
$clrAccent    = [System.Drawing.Color]::FromArgb(222, 108, 12)      # Primary blue accent
$clrAccent2   = [System.Drawing.Color]::FromArgb(245, 140, 40)      # Lighter accent
$clrSuccess   = [System.Drawing.Color]::FromArgb(32, 200, 100)       # Teal success
$clrDanger    = [System.Drawing.Color]::FromArgb(225, 65, 60)       # Red danger
$clrWarning   = [System.Drawing.Color]::FromArgb(255, 210, 60)      # Amber warning
$clrPurple    = [System.Drawing.Color]::FromArgb(160, 75, 200)      # Purple for set-pass
$clrTextPri   = [System.Drawing.Color]::FromArgb(238, 226, 205)     # Primary text
$clrTextSec   = [System.Drawing.Color]::FromArgb(130, 112, 85)     # Secondary/muted text
$clrInput     = [System.Drawing.Color]::FromArgb(28, 24, 18)        # Input background
$clrGridHead  = [System.Drawing.Color]::FromArgb(24, 21, 16)        # Grid header bg
$clrGridRow   = [System.Drawing.Color]::FromArgb(18, 15, 12)        # Grid row bg
$clrGridSel   = [System.Drawing.Color]::FromArgb(130, 75, 10)       # Grid selection
$clrLogBg     = [System.Drawing.Color]::FromArgb(8, 7, 5)          # Console log background
$clrLogFg     = [System.Drawing.Color]::FromArgb(225, 170, 30)       # Console log text
$clrStatusBar = [System.Drawing.Color]::FromArgb(8, 7, 5)         # Status bar background
$clrBtnGray   = [System.Drawing.Color]::FromArgb(38, 32, 22)        # Gray button background

# ── Fonts
$fBrand    = New-Object System.Drawing.Font("Segoe UI", 26, [System.Drawing.FontStyle]::Bold)
$fSubtitle = New-Object System.Drawing.Font("Segoe UI", 11)
$fLabel    = New-Object System.Drawing.Font("Segoe UI", 9)
$fLabelB   = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$fGroup    = New-Object System.Drawing.Font("Segoe UI", 9,  [System.Drawing.FontStyle]::Bold)
$fInput    = New-Object System.Drawing.Font("Consolas",  10)
$fBtn      = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$fBtnMain  = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$fLog      = New-Object System.Drawing.Font("Consolas",  9)
$fVersion  = New-Object System.Drawing.Font("Segoe UI", 8)
$fStatus   = New-Object System.Drawing.Font("Segoe UI", 8)
$fMono     = New-Object System.Drawing.Font("Consolas",  10)

# ═══════════════════════════════════════════════════════════════════════════════
# ═══════════════════════════════════════════════════════════════════════════════
#  MAIN FORM  ── two-column layout: [Config Panel | Log Panel]
# ═══════════════════════════════════════════════════════════════════════════════
$form = New-Object System.Windows.Forms.Form
$form.Text            = "NOVIVO Remote Desktop"
$form.ClientSize      = New-Object System.Drawing.Size(1040, 700)
$form.StartPosition   = "CenterScreen"
$form.FormBorderStyle = "Sizable"
$form.MaximizeBox     = $false
$form.MinimumSize     = New-Object System.Drawing.Size(900, 640)
$form.BackColor       = $clrBg
$form.AutoScaleMode   = [System.Windows.Forms.AutoScaleMode]::None
$form.GetType().GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]"Instance,NonPublic").SetValue($form, $true, $null)

$iconPath = Join-Path $PSScriptRoot "icon.ico"
if (Test-Path $iconPath) { $form.Icon = New-Object System.Drawing.Icon($iconPath) }

# ─────────────────────────────────────────────────────────────────────────────
#  HEADER  ── full-width branding strip
# ─────────────────────────────────────────────────────────────────────────────
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Location  = New-Object System.Drawing.Point(0, 0)
$pnlHeader.Size      = New-Object System.Drawing.Size(1040, 86)
$pnlHeader.BackColor = $clrHeader
$pnlHeader.Anchor    = [System.Windows.Forms.AnchorStyles]"Top, Left, Right"
$form.Controls.Add($pnlHeader)

$stripe = New-Object System.Windows.Forms.Panel
$stripe.Location  = New-Object System.Drawing.Point(0, 0)
$stripe.Size      = New-Object System.Drawing.Size(4, 86)
$stripe.BackColor = $clrAccent
$pnlHeader.Controls.Add($stripe)

$lblBrand = New-Object System.Windows.Forms.Label
$lblBrand.Location  = New-Object System.Drawing.Point(20, 10)
$lblBrand.Size      = New-Object System.Drawing.Size(360, 42)
$lblBrand.Text      = "NOVIVO"
$lblBrand.Font      = $fBrand
$lblBrand.ForeColor = $clrTextPri
$lblBrand.BackColor = [System.Drawing.Color]::Transparent
$pnlHeader.Controls.Add($lblBrand)

$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Location  = New-Object System.Drawing.Point(24, 57)
$lblSub.Size      = New-Object System.Drawing.Size(300, 22)
$lblSub.Text      = "Remote Desktop Setup Tool"
$lblSub.Font      = $fSubtitle
$lblSub.ForeColor = $clrTextSec
$lblSub.BackColor = [System.Drawing.Color]::Transparent
$pnlHeader.Controls.Add($lblSub)

# Admin status indicator (right side of header)
$pnlDot = New-Object System.Windows.Forms.Panel
$pnlDot.Size      = New-Object System.Drawing.Size(8, 8)
$pnlDot.Location  = New-Object System.Drawing.Point(880, 38)
$pnlDot.BackColor = $clrSuccess
$pnlDot.Anchor    = [System.Windows.Forms.AnchorStyles]"Top, Right"
$pnlHeader.Controls.Add($pnlDot)

$lblAdminBadge = New-Object System.Windows.Forms.Label
$lblAdminBadge.Location  = New-Object System.Drawing.Point(896, 34)
$lblAdminBadge.Size      = New-Object System.Drawing.Size(130, 18)
$lblAdminBadge.Text      = "Administrator"
$lblAdminBadge.Font      = $fLabelB
$lblAdminBadge.ForeColor = $clrSuccess
$lblAdminBadge.BackColor = [System.Drawing.Color]::Transparent
$lblAdminBadge.Anchor    = [System.Windows.Forms.AnchorStyles]"Top, Right"
$pnlHeader.Controls.Add($lblAdminBadge)

$lblVer = New-Object System.Windows.Forms.Label
$lblVer.Location  = New-Object System.Drawing.Point(896, 56)
$lblVer.Size      = New-Object System.Drawing.Size(130, 18)
$lblVer.Text      = "v2.0"
$lblVer.Font      = $fVersion
$lblVer.ForeColor = [System.Drawing.Color]::FromArgb(120, 90, 40)
$lblVer.BackColor = [System.Drawing.Color]::Transparent
$lblVer.Anchor    = [System.Windows.Forms.AnchorStyles]"Top, Right"
$pnlHeader.Controls.Add($lblVer)

$sep0 = New-Object System.Windows.Forms.Panel
$sep0.Location  = New-Object System.Drawing.Point(0, 86)
$sep0.Size      = New-Object System.Drawing.Size(1040, 2)
$sep0.BackColor = $clrAccent
$sep0.Anchor    = [System.Windows.Forms.AnchorStyles]"Top, Left, Right"
$form.Controls.Add($sep0)

# ─────────────────────────────────────────────────────────────────────────────
#  HIDDEN COMPAT CONTROLS  (used by install logic)
# ─────────────────────────────────────────────────────────────────────────────
$titleLabel         = New-Object System.Windows.Forms.Label
$titleLabel.Visible = $false
$titleLabel.Text    = ">>> TAILSCALE QUICK SETUP TOOL <<<"
$form.Controls.Add($titleLabel)

$labelNetworkID         = New-Object System.Windows.Forms.Label
$labelNetworkID.Visible = $false
$labelNetworkID.Text    = "Auth Key:"
$form.Controls.Add($labelNetworkID)

$radioTailscale         = New-Object System.Windows.Forms.RadioButton
$radioTailscale.Visible = $false
$radioTailscale.Checked = $true
$form.Controls.Add($radioTailscale)

$radioZeroTier         = New-Object System.Windows.Forms.RadioButton
$radioZeroTier.Visible = $false
$form.Controls.Add($radioZeroTier)

# ─────────────────────────────────────────────────────────────────────────────
#  LEFT CONFIG PANEL  (x=0, anchored top-bottom-left)
# ─────────────────────────────────────────────────────────────────────────────
$pnlLeft = New-Object System.Windows.Forms.Panel
$pnlLeft.Location  = New-Object System.Drawing.Point(0, 88)
$pnlLeft.Size      = New-Object System.Drawing.Size(460, 584)
$pnlLeft.BackColor = [System.Drawing.Color]::FromArgb(16, 14, 11)
$pnlLeft.Anchor    = [System.Windows.Forms.AnchorStyles]"Top, Left, Bottom"
$form.Controls.Add($pnlLeft)

# Left–right divider line
$pnlDivider = New-Object System.Windows.Forms.Panel
$pnlDivider.Location  = New-Object System.Drawing.Point(460, 88)
$pnlDivider.Size      = New-Object System.Drawing.Size(1, 584)
$pnlDivider.BackColor = $clrBorder
$pnlDivider.Anchor    = [System.Windows.Forms.AnchorStyles]"Top, Left, Bottom"
$form.Controls.Add($pnlDivider)

# ── VPN METHOD section ───────────────────────────────────────────────────────
$pnlVpnHdr = New-Object System.Windows.Forms.Panel
$pnlVpnHdr.Location  = New-Object System.Drawing.Point(0, 0)
$pnlVpnHdr.Size      = New-Object System.Drawing.Size(460, 30)
$pnlVpnHdr.BackColor = [System.Drawing.Color]::FromArgb(20, 18, 13)
$pnlLeft.Controls.Add($pnlVpnHdr)

$pnlVpnAccent = New-Object System.Windows.Forms.Panel
$pnlVpnAccent.Location  = New-Object System.Drawing.Point(0, 0)
$pnlVpnAccent.Size      = New-Object System.Drawing.Size(3, 30)
$pnlVpnAccent.BackColor = $clrAccent
$pnlVpnHdr.Controls.Add($pnlVpnAccent)

$lblVpnTitle = New-Object System.Windows.Forms.Label
$lblVpnTitle.Location  = New-Object System.Drawing.Point(12, 7)
$lblVpnTitle.Size      = New-Object System.Drawing.Size(200, 16)
$lblVpnTitle.Text      = "VPN METHOD"
$lblVpnTitle.Font      = $fGroup
$lblVpnTitle.ForeColor = $clrAccent
$lblVpnTitle.BackColor = [System.Drawing.Color]::Transparent
$pnlVpnHdr.Controls.Add($lblVpnTitle)

# Styled VPN toggle buttons (replace radio buttons visually)
$btnVpnTS = New-Object System.Windows.Forms.Button
$btnVpnTS.Location                  = New-Object System.Drawing.Point(12, 38)
$btnVpnTS.Size                      = New-Object System.Drawing.Size(212, 36)
$btnVpnTS.Text                      = "TAILSCALE"
$btnVpnTS.Font                      = $fBtn
$btnVpnTS.FlatStyle                 = "Flat"
$btnVpnTS.BackColor                 = $clrAccent
$btnVpnTS.ForeColor                 = [System.Drawing.Color]::White
$btnVpnTS.FlatAppearance.BorderSize = 0
$pnlLeft.Controls.Add($btnVpnTS)

$btnVpnZT = New-Object System.Windows.Forms.Button
$btnVpnZT.Location                  = New-Object System.Drawing.Point(236, 38)
$btnVpnZT.Size                      = New-Object System.Drawing.Size(212, 36)
$btnVpnZT.Text                      = "ZEROTIER"
$btnVpnZT.Font                      = $fBtn
$btnVpnZT.FlatStyle                 = "Flat"
$btnVpnZT.BackColor                 = [System.Drawing.Color]::FromArgb(30, 26, 18)
$btnVpnZT.ForeColor                 = $clrTextSec
$btnVpnZT.FlatAppearance.BorderSize = 1
$btnVpnZT.FlatAppearance.BorderColor = $clrBorder
$pnlLeft.Controls.Add($btnVpnZT)

$pnlVpnSep = New-Object System.Windows.Forms.Panel
$pnlVpnSep.Location  = New-Object System.Drawing.Point(0, 84)
$pnlVpnSep.Size      = New-Object System.Drawing.Size(460, 1)
$pnlVpnSep.BackColor = $clrBorder
$pnlLeft.Controls.Add($pnlVpnSep)

# VPN toggle click events
$btnVpnTS.Add_Click({
    $radioTailscale.Checked              = $true
    $btnVpnTS.BackColor                  = $clrAccent
    $btnVpnTS.ForeColor                  = [System.Drawing.Color]::White
    $btnVpnTS.FlatAppearance.BorderSize  = 0
    $btnVpnZT.BackColor                  = [System.Drawing.Color]::FromArgb(30, 26, 18)
    $btnVpnZT.ForeColor                  = $clrTextSec
    $btnVpnZT.FlatAppearance.BorderSize  = 1
    $labelNetworkID.Text = "Auth Key:"
    $titleLabel.Text     = ">>> TAILSCALE QUICK SETUP TOOL <<<"
    $lblKeyHdr.Text      = "Auth Key"
    # No credential ships with the tool - only clear a value left over from the
    # other VPN method (a 16-hex ZeroTier network ID).
    if ($textNetworkID.Text -match '^[0-9a-fA-F]{16}$') { $textNetworkID.Text = "" }
})

$btnVpnZT.Add_Click({
    $radioZeroTier.Checked               = $true
    $btnVpnZT.BackColor                  = $clrAccent
    $btnVpnZT.ForeColor                  = [System.Drawing.Color]::White
    $btnVpnZT.FlatAppearance.BorderSize  = 0
    $btnVpnTS.BackColor                  = [System.Drawing.Color]::FromArgb(30, 26, 18)
    $btnVpnTS.ForeColor                  = $clrTextSec
    $btnVpnTS.FlatAppearance.BorderSize  = 1
    $labelNetworkID.Text = "Network ID:"
    $titleLabel.Text     = ">>> ZEROTIER QUICK SETUP TOOL <<<"
    $lblKeyHdr.Text      = "Network ID"
    if ($textNetworkID.Text -like "tskey-*") { $textNetworkID.Text = "" }
})

# ── AUTH KEY section ──────────────────────────────────────────────────────────
$lblKeyHdr = New-Object System.Windows.Forms.Label
$lblKeyHdr.Location  = New-Object System.Drawing.Point(14, 96)
$lblKeyHdr.Size      = New-Object System.Drawing.Size(432, 16)
$lblKeyHdr.Text      = "Auth Key"
$lblKeyHdr.Font      = $fGroup
$lblKeyHdr.ForeColor = $clrTextSec
$lblKeyHdr.BackColor = [System.Drawing.Color]::Transparent
$pnlLeft.Controls.Add($lblKeyHdr)

$textNetworkID = New-Object System.Windows.Forms.TextBox
$textNetworkID.Location    = New-Object System.Drawing.Point(14, 116)
$textNetworkID.Size        = New-Object System.Drawing.Size(432, 30)
$textNetworkID.Text        = ""
$textNetworkID.Font        = $fInput
$textNetworkID.BackColor   = $clrInput
$textNetworkID.ForeColor   = $clrTextPri
$textNetworkID.BorderStyle = "FixedSingle"
$textNetworkID.Anchor      = [System.Windows.Forms.AnchorStyles]"Top, Left, Right"
$pnlLeft.Controls.Add($textNetworkID)

$pnlKeySep = New-Object System.Windows.Forms.Panel
$pnlKeySep.Location  = New-Object System.Drawing.Point(0, 158)
$pnlKeySep.Size      = New-Object System.Drawing.Size(460, 1)
$pnlKeySep.BackColor = $clrBorder
$pnlLeft.Controls.Add($pnlKeySep)

# ── USERS & CREDENTIALS section ───────────────────────────────────────────────
$pnlUsersHdr = New-Object System.Windows.Forms.Panel
$pnlUsersHdr.Location  = New-Object System.Drawing.Point(0, 159)
$pnlUsersHdr.Size      = New-Object System.Drawing.Size(460, 30)
$pnlUsersHdr.BackColor = [System.Drawing.Color]::FromArgb(20, 18, 13)
$pnlLeft.Controls.Add($pnlUsersHdr)

$pnlUsersAccent = New-Object System.Windows.Forms.Panel
$pnlUsersAccent.Location  = New-Object System.Drawing.Point(0, 0)
$pnlUsersAccent.Size      = New-Object System.Drawing.Size(3, 30)
$pnlUsersAccent.BackColor = $clrSuccess
$pnlUsersHdr.Controls.Add($pnlUsersAccent)

$lblUsersTitle = New-Object System.Windows.Forms.Label
$lblUsersTitle.Location  = New-Object System.Drawing.Point(12, 7)
$lblUsersTitle.Size      = New-Object System.Drawing.Size(340, 16)
$lblUsersTitle.Text      = "USERS & CREDENTIALS  (RDP)"
$lblUsersTitle.Font      = $fGroup
$lblUsersTitle.ForeColor = $clrSuccess
$lblUsersTitle.BackColor = [System.Drawing.Color]::Transparent
$pnlUsersHdr.Controls.Add($lblUsersTitle)

$userGrid = New-Object System.Windows.Forms.DataGridView
$userGrid.Location                                 = New-Object System.Drawing.Point(14, 197)
$userGrid.Size                                     = New-Object System.Drawing.Size(432, 112)
$userGrid.AllowUserToAddRows                       = $false
$userGrid.AllowUserToDeleteRows                    = $false
$userGrid.RowHeadersVisible                        = $false
$userGrid.SelectionMode                            = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$userGrid.AutoSizeColumnsMode                      = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
$userGrid.ScrollBars                               = "Vertical"
$userGrid.Font                                     = $fInput
$userGrid.BackgroundColor                          = $clrGridRow
$userGrid.GridColor                                = [System.Drawing.Color]::FromArgb(45, 38, 26)
$userGrid.ColumnHeadersHeight                      = 28
$userGrid.RowTemplate.Height                       = 26
$userGrid.MultiSelect                              = $true
$userGrid.BorderStyle                              = "FixedSingle"
$userGrid.EnableHeadersVisualStyles                = $false
$userGrid.ColumnHeadersDefaultCellStyle.Font       = $fLabelB
$userGrid.ColumnHeadersDefaultCellStyle.BackColor  = $clrGridHead
$userGrid.ColumnHeadersDefaultCellStyle.ForeColor  = $clrTextSec
$userGrid.DefaultCellStyle.BackColor               = $clrGridRow
$userGrid.DefaultCellStyle.ForeColor               = $clrTextPri
$userGrid.DefaultCellStyle.SelectionBackColor      = $clrGridSel
$userGrid.DefaultCellStyle.SelectionForeColor      = $clrTextPri
$userGrid.Anchor                                   = [System.Windows.Forms.AnchorStyles]"Top, Left, Right"
$pnlLeft.Controls.Add($userGrid)

$colUsername            = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colUsername.Name       = "Username"
$colUsername.HeaderText = "Username"
$colUsername.FillWeight = 45
$colPassword            = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colPassword.Name       = "Password"
$colPassword.HeaderText = "Password"
$colPassword.FillWeight = 55
$userGrid.Columns.Add($colUsername) | Out-Null
$userGrid.Columns.Add($colPassword) | Out-Null
$userGrid.Rows.Add($env:USERNAME, "") | Out-Null

# Password masking
$script:showPasswords = $false
$userGrid.Add_CellPainting({
    param($s, $e)
    if ($e.ColumnIndex -eq 1 -and $e.RowIndex -ge 0) {
        $isEditing = ($s.IsCurrentCellInEditMode -and $s.CurrentCell -and $s.CurrentCell.RowIndex -eq $e.RowIndex -and $s.CurrentCell.ColumnIndex -eq 1)
        if (-not $isEditing -and -not $script:showPasswords) {
            $cellVal = $s.Rows[$e.RowIndex].Cells[1].Value
            if ($null -ne $cellVal -and $cellVal.ToString().Length -gt 0) {
                $e.PaintBackground($e.CellBounds, $true)
                $masked = '*' * [Math]::Min($cellVal.ToString().Length, 30)
                $sf  = New-Object System.Drawing.StringFormat
                $sf.Alignment     = [System.Drawing.StringAlignment]::Near
                $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
                $brush = New-Object System.Drawing.SolidBrush($e.CellStyle.ForeColor)
                $r = [System.Drawing.RectangleF]::new($e.CellBounds.X + 4, $e.CellBounds.Y, $e.CellBounds.Width - 8, $e.CellBounds.Height)
                $e.Graphics.DrawString($masked, $e.CellStyle.Font, $brush, $r, $sf)
                $brush.Dispose(); $sf.Dispose()
                $e.Handled = $true
            }
        }
    }
})
$userGrid.Add_EditingControlShowing({
    param($s, $e)
    $tb = $e.Control -as [System.Windows.Forms.TextBox]
    if ($tb) { $tb.UseSystemPasswordChar = ($s.CurrentCell -and $s.CurrentCell.ColumnIndex -eq 1 -and -not $script:showPasswords) }
})

# User action buttons – row 1
$btnAddUser = New-Object System.Windows.Forms.Button
$btnAddUser.Location                  = New-Object System.Drawing.Point(14, 317)
$btnAddUser.Size                      = New-Object System.Drawing.Size(104, 30)
$btnAddUser.Text                      = "+ Add User"
$btnAddUser.Font                      = $fBtn
$btnAddUser.FlatStyle                 = "Flat"
$btnAddUser.BackColor                 = $clrAccent
$btnAddUser.ForeColor                 = [System.Drawing.Color]::White
$btnAddUser.FlatAppearance.BorderSize = 0
$btnAddUser.Add_Click({
    $newIdx = $userGrid.Rows.Add("", "")
    $userGrid.CurrentCell = $userGrid.Rows[$newIdx].Cells["Username"]
    $userGrid.BeginEdit($true)
})
$pnlLeft.Controls.Add($btnAddUser)

$btnRemoveUser = New-Object System.Windows.Forms.Button
$btnRemoveUser.Location                  = New-Object System.Drawing.Point(126, 317)
$btnRemoveUser.Size                      = New-Object System.Drawing.Size(104, 30)
$btnRemoveUser.Text                      = "- Remove"
$btnRemoveUser.Font                      = $fBtn
$btnRemoveUser.FlatStyle                 = "Flat"
$btnRemoveUser.BackColor                 = $clrDanger
$btnRemoveUser.ForeColor                 = [System.Drawing.Color]::White
$btnRemoveUser.FlatAppearance.BorderSize = 0
$btnRemoveUser.Add_Click({
    $toRemove = @()
    foreach ($row in $userGrid.SelectedRows) { $toRemove += $row.Index }
    foreach ($idx in ($toRemove | Sort-Object -Descending)) {
        if ($userGrid.Rows.Count -gt 1) { $userGrid.Rows.RemoveAt($idx) }
    }
})
$pnlLeft.Controls.Add($btnRemoveUser)

$btnRandomAll = New-Object System.Windows.Forms.Button
$btnRandomAll.Location                  = New-Object System.Drawing.Point(238, 317)
$btnRandomAll.Size                      = New-Object System.Drawing.Size(104, 30)
$btnRandomAll.Text                      = "Random Pwd"
$btnRandomAll.Font                      = $fBtn
$btnRandomAll.FlatStyle                 = "Flat"
$btnRandomAll.BackColor                 = $clrSuccess
$btnRandomAll.ForeColor                 = [System.Drawing.Color]::White
$btnRandomAll.FlatAppearance.BorderSize = 0
$btnRandomAll.Add_Click({
    $chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*"
    $targetRows = if ($userGrid.SelectedRows.Count -gt 0) { $userGrid.SelectedRows } else { $userGrid.Rows }
    foreach ($row in $targetRows) {
        $row.Cells["Password"].Value = -join ((1..12) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    }
})
$pnlLeft.Controls.Add($btnRandomAll)

$btnClearPass = New-Object System.Windows.Forms.Button
$btnClearPass.Location                  = New-Object System.Drawing.Point(350, 317)
$btnClearPass.Size                      = New-Object System.Drawing.Size(96, 30)
$btnClearPass.Text                      = "Clear All"
$btnClearPass.Font                      = $fBtn
$btnClearPass.FlatStyle                 = "Flat"
$btnClearPass.BackColor                 = $clrBtnGray
$btnClearPass.ForeColor                 = $clrTextSec
$btnClearPass.FlatAppearance.BorderSize = 0
$btnClearPass.Add_Click({
    $cf = [System.Windows.Forms.MessageBox]::Show("Clear all passwords?", "Confirm", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($cf -eq [System.Windows.Forms.DialogResult]::Yes) {
        foreach ($row in $userGrid.Rows) { $row.Cells["Password"].Value = "" }
    }
})
$pnlLeft.Controls.Add($btnClearPass)

# User action buttons – row 2
$btnSetPass = New-Object System.Windows.Forms.Button
$btnSetPass.Location                  = New-Object System.Drawing.Point(14, 355)
$btnSetPass.Size                      = New-Object System.Drawing.Size(260, 30)
$btnSetPass.Text                      = "Set Password for Selected User"
$btnSetPass.Font                      = $fBtn
$btnSetPass.FlatStyle                 = "Flat"
$btnSetPass.BackColor                 = $clrPurple
$btnSetPass.ForeColor                 = [System.Drawing.Color]::White
$btnSetPass.FlatAppearance.BorderSize = 0
$btnSetPass.Add_Click({
    $selRows = $userGrid.SelectedRows
    if ($selRows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select a user row first.", "Set Password", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    $targetRow  = $selRows[0]
    $targetUser = if ($targetRow.Cells["Username"].Value) { $targetRow.Cells["Username"].Value.ToString() } else { "(unnamed)" }

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text            = "Set Password -- $targetUser"
    $dlg.Size            = New-Object System.Drawing.Size(360, 170)
    $dlg.StartPosition   = "CenterParent"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox     = $false
    $dlg.MinimizeBox     = $false
    $dlg.BackColor       = [System.Drawing.Color]::FromArgb(20, 17, 13)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text      = "New password for '$targetUser':"
    $lbl.Location  = New-Object System.Drawing.Point(12, 14)
    $lbl.Size      = New-Object System.Drawing.Size(320, 18)
    $lbl.Font      = $fLabel
    $lbl.ForeColor = [System.Drawing.Color]::FromArgb(210, 190, 155)
    $lbl.BackColor = [System.Drawing.Color]::Transparent
    $dlg.Controls.Add($lbl)

    $txtP = New-Object System.Windows.Forms.TextBox
    $txtP.Location              = New-Object System.Drawing.Point(12, 38)
    $txtP.Size                  = New-Object System.Drawing.Size(238, 24)
    $txtP.UseSystemPasswordChar = $true
    $txtP.Font                  = $fMono
    $txtP.BackColor             = [System.Drawing.Color]::FromArgb(26, 22, 15)
    $txtP.ForeColor             = [System.Drawing.Color]::FromArgb(238, 226, 205)
    $txtP.BorderStyle           = "FixedSingle"
    $txtP.Text = if ($targetRow.Cells["Password"].Value) { $targetRow.Cells["Password"].Value.ToString() } else { "" }
    $dlg.Controls.Add($txtP)

    $chkView = New-Object System.Windows.Forms.CheckBox
    $chkView.Text      = "Show"
    $chkView.Location  = New-Object System.Drawing.Point(258, 40)
    $chkView.Size      = New-Object System.Drawing.Size(72, 22)
    $chkView.Font      = $fLabel
    $chkView.ForeColor = [System.Drawing.Color]::FromArgb(130, 112, 85)
    $chkView.BackColor = [System.Drawing.Color]::Transparent
    $chkView.Add_CheckedChanged({ $txtP.UseSystemPasswordChar = -not $chkView.Checked })
    $dlg.Controls.Add($chkView)

    $btnRnd = New-Object System.Windows.Forms.Button
    $btnRnd.Text                      = "Random"
    $btnRnd.Location                  = New-Object System.Drawing.Point(12, 72)
    $btnRnd.Size                      = New-Object System.Drawing.Size(88, 28)
    $btnRnd.Font                      = $fBtn
    $btnRnd.FlatStyle                 = "Flat"
    $btnRnd.BackColor                 = [System.Drawing.Color]::FromArgb(0, 160, 80)
    $btnRnd.ForeColor                 = [System.Drawing.Color]::White
    $btnRnd.FlatAppearance.BorderSize = 0
    $btnRnd.Add_Click({
        $ch = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#"
        $txtP.Text = -join ((1..12) | ForEach-Object { $ch[(Get-Random -Maximum $ch.Length)] })
        $chkView.Checked = $true
    })
    $dlg.Controls.Add($btnRnd)

    $btnOK = New-Object System.Windows.Forms.Button
    $btnOK.Text                      = "OK"
    $btnOK.Location                  = New-Object System.Drawing.Point(170, 72)
    $btnOK.Size                      = New-Object System.Drawing.Size(78, 28)
    $btnOK.Font                      = $fBtn
    $btnOK.FlatStyle                 = "Flat"
    $btnOK.BackColor                 = [System.Drawing.Color]::FromArgb(222, 108, 12)
    $btnOK.ForeColor                 = [System.Drawing.Color]::White
    $btnOK.FlatAppearance.BorderSize = 0
    $btnOK.DialogResult              = [System.Windows.Forms.DialogResult]::OK
    $dlg.AcceptButton                = $btnOK
    $dlg.Controls.Add($btnOK)

    $btnCancel2 = New-Object System.Windows.Forms.Button
    $btnCancel2.Text                      = "Cancel"
    $btnCancel2.Location                  = New-Object System.Drawing.Point(256, 72)
    $btnCancel2.Size                      = New-Object System.Drawing.Size(78, 28)
    $btnCancel2.Font                      = $fBtn
    $btnCancel2.FlatStyle                 = "Flat"
    $btnCancel2.BackColor                 = [System.Drawing.Color]::FromArgb(38, 32, 22)
    $btnCancel2.ForeColor                 = [System.Drawing.Color]::FromArgb(130, 112, 85)
    $btnCancel2.FlatAppearance.BorderSize = 0
    $btnCancel2.DialogResult              = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.CancelButton                     = $btnCancel2
    $dlg.Controls.Add($btnCancel2)

    $dlg.ActiveControl = $txtP
    if ($dlg.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        $targetRow.Cells["Password"].Value = $txtP.Text
        $userGrid.Refresh()
    }
    $dlg.Dispose()
})
$pnlLeft.Controls.Add($btnSetPass)

$chkShowPass = New-Object System.Windows.Forms.CheckBox
$chkShowPass.Location  = New-Object System.Drawing.Point(284, 359)
$chkShowPass.Size      = New-Object System.Drawing.Size(162, 22)
$chkShowPass.Text      = "Show Passwords"
$chkShowPass.Font      = $fLabel
$chkShowPass.ForeColor = $clrTextSec
$chkShowPass.BackColor = [System.Drawing.Color]::Transparent
$chkShowPass.Add_CheckedChanged({
    $script:showPasswords = $chkShowPass.Checked
    $userGrid.Refresh()
})
$pnlLeft.Controls.Add($chkShowPass)

# ── START SETUP button (anchored bottom of left panel) ───────────────────────
$pnlStartSep = New-Object System.Windows.Forms.Panel
$pnlStartSep.Location  = New-Object System.Drawing.Point(0, 526)
$pnlStartSep.Size      = New-Object System.Drawing.Size(460, 1)
$pnlStartSep.BackColor = $clrBorder
$pnlStartSep.Anchor    = [System.Windows.Forms.AnchorStyles]"Bottom, Left, Right"
$pnlLeft.Controls.Add($pnlStartSep)

$btnInstall = New-Object System.Windows.Forms.Button
$btnInstall.Location                  = New-Object System.Drawing.Point(14, 534)
$btnInstall.Size                      = New-Object System.Drawing.Size(432, 42)
$btnInstall.Text                      = ">> START SETUP"
$btnInstall.BackColor                 = $clrAccent
$btnInstall.ForeColor                 = [System.Drawing.Color]::White
$btnInstall.FlatStyle                 = "Flat"
$btnInstall.FlatAppearance.BorderSize = 0
$btnInstall.Font                      = $fBtnMain
$btnInstall.Anchor                    = [System.Windows.Forms.AnchorStyles]"Bottom, Left, Right"
$pnlLeft.Controls.Add($btnInstall)

# ─────────────────────────────────────────────────────────────────────────────
#  RIGHT LOG PANEL  (fills remaining width, anchored all sides)
# ─────────────────────────────────────────────────────────────────────────────
$pnlRight = New-Object System.Windows.Forms.Panel
$pnlRight.Location  = New-Object System.Drawing.Point(461, 88)
$pnlRight.Size      = New-Object System.Drawing.Size(579, 584)
$pnlRight.BackColor = [System.Drawing.Color]::FromArgb(9, 8, 6)
$pnlRight.Anchor    = [System.Windows.Forms.AnchorStyles]"Top, Left, Right, Bottom"
$form.Controls.Add($pnlRight)

# Log header band
$pnlLogHdr = New-Object System.Windows.Forms.Panel
$pnlLogHdr.Location  = New-Object System.Drawing.Point(0, 0)
$pnlLogHdr.Size      = New-Object System.Drawing.Size(579, 34)
$pnlLogHdr.BackColor = [System.Drawing.Color]::FromArgb(12, 11, 8)
$pnlLogHdr.Anchor    = [System.Windows.Forms.AnchorStyles]"Top, Left, Right"
$pnlRight.Controls.Add($pnlLogHdr)

$pnlLogAccent = New-Object System.Windows.Forms.Panel
$pnlLogAccent.Location  = New-Object System.Drawing.Point(0, 0)
$pnlLogAccent.Size      = New-Object System.Drawing.Size(3, 34)
$pnlLogAccent.BackColor = $clrLogFg
$pnlLogHdr.Controls.Add($pnlLogAccent)

$lblLogTitle = New-Object System.Windows.Forms.Label
$lblLogTitle.Location  = New-Object System.Drawing.Point(12, 9)
$lblLogTitle.Size      = New-Object System.Drawing.Size(300, 16)
$lblLogTitle.Text      = "INSTALLATION LOG"
$lblLogTitle.Font      = $fGroup
$lblLogTitle.ForeColor = $clrLogFg
$lblLogTitle.BackColor = [System.Drawing.Color]::Transparent
$pnlLogHdr.Controls.Add($lblLogTitle)

$pnlLogSep = New-Object System.Windows.Forms.Panel
$pnlLogSep.Location  = New-Object System.Drawing.Point(0, 34)
$pnlLogSep.Size      = New-Object System.Drawing.Size(579, 1)
$pnlLogSep.BackColor = [System.Drawing.Color]::FromArgb(28, 22, 14)
$pnlLogSep.Anchor    = [System.Windows.Forms.AnchorStyles]"Top, Left, Right"
$pnlRight.Controls.Add($pnlLogSep)

$outputBox = New-Object System.Windows.Forms.TextBox
$outputBox.Location    = New-Object System.Drawing.Point(0, 35)
$outputBox.Size        = New-Object System.Drawing.Size(579, 504)
$outputBox.Multiline   = $true
$outputBox.ScrollBars  = "Vertical"
$outputBox.ReadOnly    = $true
$outputBox.Font        = $fLog
$outputBox.BackColor   = $clrLogBg
$outputBox.ForeColor   = $clrLogFg
$outputBox.BorderStyle = "None"
$outputBox.Anchor      = [System.Windows.Forms.AnchorStyles]"Top, Left, Right, Bottom"
$pnlRight.Controls.Add($outputBox)

$pnlBottomSep = New-Object System.Windows.Forms.Panel
$pnlBottomSep.Location  = New-Object System.Drawing.Point(0, 539)
$pnlBottomSep.Size      = New-Object System.Drawing.Size(579, 1)
$pnlBottomSep.BackColor = $clrBorder
$pnlBottomSep.Anchor    = [System.Windows.Forms.AnchorStyles]"Bottom, Left, Right"
$pnlRight.Controls.Add($pnlBottomSep)

$btnCopyLog = New-Object System.Windows.Forms.Button
$btnCopyLog.Location                  = New-Object System.Drawing.Point(0, 540)
$btnCopyLog.Size                      = New-Object System.Drawing.Size(395, 44)
$btnCopyLog.Text                      = "COPY LOG TO CLIPBOARD"
$btnCopyLog.Font                      = $fBtn
$btnCopyLog.BackColor                 = [System.Drawing.Color]::FromArgb(18, 15, 10)
$btnCopyLog.ForeColor                 = $clrTextSec
$btnCopyLog.FlatStyle                 = "Flat"
$btnCopyLog.FlatAppearance.BorderSize = 0
$btnCopyLog.Anchor                    = [System.Windows.Forms.AnchorStyles]"Bottom, Left"
$btnCopyLog.Add_Click({
    if ([string]::IsNullOrWhiteSpace($outputBox.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Log is empty.", "Copy Log", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    } else {
        [System.Windows.Forms.Clipboard]::SetText($outputBox.Text)
        $btnCopyLog.Text      = "[OK]  COPIED TO CLIPBOARD"
        $btnCopyLog.BackColor = [System.Drawing.Color]::FromArgb(80, 65, 10)
        $btnCopyLog.ForeColor = [System.Drawing.Color]::White
        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 1600
        $timer.Add_Tick({
            $btnCopyLog.Text      = "COPY LOG TO CLIPBOARD"
            $btnCopyLog.BackColor = [System.Drawing.Color]::FromArgb(18, 15, 10)
            $btnCopyLog.ForeColor = $clrTextSec
            $timer.Stop(); $timer.Dispose()
        })
        $timer.Start()
    }
})
$pnlRight.Controls.Add($btnCopyLog)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Location                  = New-Object System.Drawing.Point(395, 540)
$btnClose.Size                      = New-Object System.Drawing.Size(184, 44)
$btnClose.Text                      = "X  CLOSE"
$btnClose.BackColor                 = [System.Drawing.Color]::FromArgb(38, 18, 10)
$btnClose.FlatStyle                 = "Flat"
$btnClose.FlatAppearance.BorderSize = 0
$btnClose.Font                      = $fBtn
$btnClose.ForeColor                 = [System.Drawing.Color]::FromArgb(215, 90, 40)
$btnClose.Anchor                    = [System.Windows.Forms.AnchorStyles]"Bottom, Right"
$btnClose.Add_Click({ $form.Close() })
$pnlRight.Controls.Add($btnClose)

# ─────────────────────────────────────────────────────────────────────────────
#  STATUS BAR  (anchored to bottom)
# ─────────────────────────────────────────────────────────────────────────────
$pnlStatus = New-Object System.Windows.Forms.Panel
$pnlStatus.Location  = New-Object System.Drawing.Point(0, 672)
$pnlStatus.Size      = New-Object System.Drawing.Size(1040, 28)
$pnlStatus.BackColor = $clrStatusBar
$pnlStatus.Anchor    = [System.Windows.Forms.AnchorStyles]"Bottom, Left, Right"
$form.Controls.Add($pnlStatus)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location  = New-Object System.Drawing.Point(14, 7)
$lblStatus.Size      = New-Object System.Drawing.Size(500, 16)
$lblStatus.Text      = "Ready  |  Running as Administrator"
$lblStatus.Font      = $fStatus
$lblStatus.ForeColor = [System.Drawing.Color]::FromArgb(90, 72, 48)
$lblStatus.BackColor = [System.Drawing.Color]::Transparent
$pnlStatus.Controls.Add($lblStatus)

$lblStatusRight = New-Object System.Windows.Forms.Label
$lblStatusRight.Location  = New-Object System.Drawing.Point(740, 7)
$lblStatusRight.Size      = New-Object System.Drawing.Size(286, 16)
$lblStatusRight.Text      = "NOVIVO Remote Desktop  v2.0"
$lblStatusRight.Font      = $fStatus
$lblStatusRight.ForeColor = [System.Drawing.Color]::FromArgb(90, 72, 48)
$lblStatusRight.BackColor = [System.Drawing.Color]::Transparent
$lblStatusRight.TextAlign = "MiddleRight"
$lblStatusRight.Anchor    = [System.Windows.Forms.AnchorStyles]"Top, Right"
$pnlStatus.Controls.Add($lblStatusRight)

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
    
    # Initialize RDP status flag
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
            $btnInstall.Enabled = $true
            return
        }
        if ($userList.Count -eq 0) {
            Write-Output-Box "[ERROR] Please add at least one user in the Users table!"
            $btnInstall.Enabled = $true
            return
        }
        foreach ($u in $userList) {
            if ([string]::IsNullOrWhiteSpace($u.Password)) {
                Write-Output-Box "[ERROR] Password for user '$($u.Username)' cannot be empty!"
                $btnInstall.Enabled = $true
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
                    $btnInstall.Enabled = $true
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
                    $btnInstall.Enabled = $true
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
                $btnInstall.Enabled = $true
                return
            }
            Write-Output-Box "[INFO] tailscale path: $tsCliPath"

            # Ensure Tailscale service is running
            try {
                $tsSvcName = Get-Service -DisplayName '*Tailscale*' -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Name
                if (-not $tsSvcName) { $tsSvcName = 'Tailscale' }
                $tsSvcStatus = (Get-Service -Name $tsSvcName -ErrorAction SilentlyContinue).Status
                if ($tsSvcStatus -ne 'Running') {
                    Start-Service -Name $tsSvcName -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 4
                    Write-Output-Box "[INFO] Started Tailscale service"
                }
            } catch { }

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
                    $tsWmiTS.SetAllowTSConnections(1, 1) | Out-Null
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
                    $btnInstall.Enabled = $true
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
                    Write-Output-Box "[WARNING] Port 3389 not yet listening  -  forcing second restart..."
                    & sc.exe stop TermService 2>&1 | Out-Null
                    Start-Sleep -Seconds 4
                    & sc.exe start TermService 2>&1 | Out-Null
                    Start-Sleep -Seconds 8
                    $tsPort2 = Get-NetTCPConnection -LocalPort 3389 -State Listen -ErrorAction SilentlyContinue
                    if ($tsPort2) {
                        Write-Output-Box "[OK] Port 3389 is now LISTENING (after retry)"
                        $tsRdpWorking = $true
                    } else {
                        Write-Output-Box "[WARNING] Port 3389 still not listening  -  restart required"
                        $tsRdpWorking = $false
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
            $btnInstall.Enabled = $true
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
            Write-Output-Box "[ERROR] $($_.Exception.Message)"
            $btnInstall.Enabled = $true
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
            $btnInstall.Enabled = $true
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
            $btnInstall.Enabled = $true
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
                $wmiTS.SetAllowTSConnections(1, 1) | Out-Null
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
                $btnInstall.Enabled = $true
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
        $btnInstall.Enabled = $true
    }
})

# Show form
[void]$form.ShowDialog()
