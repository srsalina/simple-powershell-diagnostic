# diagnostics.ps1 - Windows System Diagnostic Tool
# Run with admin privileges for full access
# Usage: .\diagnostics.ps1 [-o output_file]

param (
    [string]$o
)

# Determine output destination
if ($o) {
    $OutputFile = $o
    $SaveToFile = $true
} else {
    $OutputFile = $null
    $SaveToFile = $false
}

# Function to write output (to console or file)
function Write-DiagOutput {
    param ([string]$Text)
    if ($SaveToFile) {
        $Text | Out-File -FilePath $OutputFile -Append
    } else {
        Write-Host $Text
    }
}

# Function for section headers
function Write-Section {
    param ([string]$Title)
    Write-DiagOutput ""
    Write-DiagOutput "===== $Title ====="
    Write-DiagOutput "----------------------------------------"
}

# Health check variables
$DiskWarning = ""
$CpuLoad = [math]::Round((Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average, 2)
if ($CpuLoad -gt 80) { $CpuWarning = "WARNING: High CPU load ($CpuLoad%)" }

# Start diagnostic collection
Write-DiagOutput "System Diagnostic Report"
Write-DiagOutput "Generated: $(Get-Date)"
Write-DiagOutput "----------------------------------------"

# Storage Utilization
Write-Section "Storage Utilization"
Get-Disk | Where-Object { $_.Size -gt 0 } | ForEach-Object {
    $part = Get-Partition -DiskNumber $_.Number | Where-Object { $_.Size -gt 0 }
    $vol = Get-Volume -Partition $part
    foreach ($v in $vol) {
        $used = [math]::Round(($v.Size - $v.SizeRemaining) / 1GB, 2)
        $total = [math]::Round($v.Size / 1GB, 2)
        $percent = [math]::Round(($used / $total) * 100, 2)
        if ($percent -ge 90) { $DiskWarning = "WARNING: Disk nearing capacity (>90%)" }
        if ($percent -eq 100) { $DiskWarning = "CRITICAL: Disk at 100% capacity" }
        Write-DiagOutput "$($v.DriveLetter): ${used}GB used of ${total}GB ($percent%) - $($v.FileSystemLabel)"
    }
}

# RAM Usage
Write-Section "RAM Usage"
$mem = Get-CimInstance Win32_OperatingSystem
$totalMem = [math]::Round($mem.TotalVisibleMemorySize / 1MB, 2)
$freeMem = [math]::Round($mem.FreePhysicalMemory / 1MB, 2)
$usedMem = [math]::Round($totalMem - $freeMem, 2)
Write-DiagOutput "Total: ${totalMem}GB  Used: ${usedMem}GB  Free: ${freeMem}GB"

# CPU Usage
Write-Section "CPU Usage"
Write-DiagOutput "Average Load: $CpuLoad%"
Write-DiagOutput ""
Write-DiagOutput "Top Processes:"
Get-Process | Sort-Object CPU -Descending | Select-Object -First 3 | ForEach-Object {
    $cpu = [math]::Round($_.CPU, 2)
    $mem = [math]::Round($_.WorkingSet64 / 1MB, 2)
    Write-DiagOutput "  $($_.Name) (PID: $($_.Id)) - CPU: ${cpu}s  Memory: ${mem}MB"
}

# Operating System Details
Write-Section "Operating System Details"
$os = Get-CimInstance Win32_OperatingSystem
Write-DiagOutput "OS: $($os.Caption) (Build $($os.BuildNumber))"
Write-DiagOutput "Uptime: $((Get-Date) - $os.LastBootUpTime | ForEach-Object { "$($_.Days)d $($_.Hours)h $($_.Minutes)m" })"

# General System Information
Write-Section "General System Information"
Write-DiagOutput "Hostname: $(hostname)"
Write-DiagOutput "CPU Model: $((Get-CimInstance Win32_Processor).Name)"
Write-DiagOutput "Processes: $((Get-Process).Count)"
Write-DiagOutput ""
Write-DiagOutput "Network IPs:"
Get-NetIPAddress | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } | ForEach-Object {
    Write-DiagOutput "  $($_.IPAddress) ($($_.InterfaceAlias))"
}

# System Logs
Write-Section "System Logs (Warnings and Errors)"
Write-DiagOutput "Last 10 Critical Logs:"
Get-EventLog -LogName System -EntryType Error,Warning -Newest 10 | ForEach-Object {
    Write-DiagOutput "  $($_.TimeGenerated): $($_.Source) - $($_.Message -replace '\s+', ' ')"
}

# System Health Summary
Write-Section "System Health Summary"
Write-DiagOutput $(if ($DiskWarning) { $DiskWarning } else { "Disk Space: OK" })
Write-DiagOutput $(if ($CpuWarning) { $CpuWarning } else { "CPU Load: OK ($CpuLoad%)" })
$freeMemMB = [math]::Round($mem.FreePhysicalMemory / 1024, 2)
Write-DiagOutput $(if ($freeMemMB -lt 100) { "WARNING: Low free memory ($freeMemMB MB)" } else { "Memory: OK" })

} | Tee-Object -FilePath $OutputFile -ErrorAction SilentlyContinue > $null

# Feedback
if ($SaveToFile) {
    Write-Host "`n${BLUE}Diagnostic collection complete. Output saved to: $OutputFile${NC}"
} else {
    Write-Host "`n${BLUE}Diagnostic collection complete. Output displayed above.${NC}"
}
Write-Host "Please review the output and share with your helpdesk team as needed."
