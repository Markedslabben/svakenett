# Windows SSH Server Setup Script
# Run this in PowerShell as Administrator

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "Windows SSH Server Setup" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""

# Check if OpenSSH Server is installed
Write-Host "1. Checking if OpenSSH Server is installed..." -ForegroundColor Yellow
$sshServer = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'

if ($sshServer.State -eq "Installed") {
    Write-Host "   [OK] OpenSSH Server is already installed" -ForegroundColor Green
} else {
    Write-Host "   [!] OpenSSH Server is NOT installed" -ForegroundColor Red
    Write-Host "   Installing OpenSSH Server..." -ForegroundColor Yellow
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
    Write-Host "   [OK] OpenSSH Server installed successfully" -ForegroundColor Green
}

Write-Host ""

# Check if SSH service is running
Write-Host "2. Checking SSH service status..." -ForegroundColor Yellow
$sshService = Get-Service -Name sshd -ErrorAction SilentlyContinue

if ($sshService) {
    if ($sshService.Status -eq "Running") {
        Write-Host "   [OK] SSH service is running" -ForegroundColor Green
    } else {
        Write-Host "   [!] SSH service is stopped" -ForegroundColor Red
        Write-Host "   Starting SSH service..." -ForegroundColor Yellow
        Start-Service sshd
        Write-Host "   [OK] SSH service started" -ForegroundColor Green
    }
} else {
    Write-Host "   [!] SSH service not found" -ForegroundColor Red
}

Write-Host ""

# Set SSH service to start automatically
Write-Host "3. Setting SSH to start automatically on boot..." -ForegroundColor Yellow
Set-Service -Name sshd -StartupType 'Automatic'
Write-Host "   [OK] SSH service set to automatic startup" -ForegroundColor Green

Write-Host ""

# Configure firewall
Write-Host "4. Checking firewall rule for SSH..." -ForegroundColor Yellow
$firewallRule = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue

if ($firewallRule) {
    Write-Host "   [OK] Firewall rule already exists" -ForegroundColor Green
} else {
    Write-Host "   Creating firewall rule..." -ForegroundColor Yellow
    New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
    Write-Host "   [OK] Firewall rule created" -ForegroundColor Green
}

Write-Host ""
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "SSH Server Configuration Complete!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Your Windows computer is now accessible via SSH at:" -ForegroundColor Yellow
Write-Host "   ssh klaus@192.168.100.59" -ForegroundColor Cyan
Write-Host ""
Write-Host "To test from another computer:" -ForegroundColor Yellow
Write-Host "   ssh klaus@192.168.100.59" -ForegroundColor Cyan
Write-Host ""
Write-Host "Current service status:" -ForegroundColor Yellow
Get-Service sshd | Select-Object Name, Status, StartType | Format-Table -AutoSize
