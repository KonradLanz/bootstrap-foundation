# =============================================================================
# lib/detect-hardware.ps1
# Hardware capability detection for Windows nodes.
# Dot-source this file in any PowerShell setup script:
#   . .\lib\detect-hardware.ps1
#   Detect-Hardware
#
# Exports a [hashtable] $HW with the same keys as detect-hardware.sh:
#   $HW.RamMB, $HW.VramMB, $HW.InferenceMB,
#   $HW.CpuArch, $HW.Chipset, $HW.GpuVendor,
#   $HW.NodeProfile, $HW.ProfileReason
#
# License: AGPL-3.0-or-later OR MIT  Copyright 2026 GrEEV.com KG
# =============================================================================

function Detect-Hardware {
    $hw = @{
        RamMB         = 0
        VramMB        = 0
        InferenceMB   = 0
        CpuArch       = 'x86_64'
        Chipset       = 'unknown'
        GpuVendor     = 'none'
        NodeProfile   = 'micro'
        ProfileReason = 'default'
    }

    # ----------------------------------------------------------------
    # CPU arch
    # ----------------------------------------------------------------
    $arch = $env:PROCESSOR_ARCHITECTURE
    switch ($arch) {
        'AMD64' { $hw.CpuArch = 'x86_64' }
        'ARM64' { $hw.CpuArch = 'arm64'  }
        default { $hw.CpuArch = $arch    }
    }

    # ----------------------------------------------------------------
    # Total RAM via WMI (works without admin rights)
    # ----------------------------------------------------------------
    try {
        $ramBytes = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
        $hw.RamMB = [int]($ramBytes / 1MB)
    } catch {
        Write-Warning "RAM detection failed: $_"
    }

    # ----------------------------------------------------------------
    # GPU VRAM via WMI — sums all discrete adapters, picks largest
    # ----------------------------------------------------------------
    try {
        $gpus = Get-CimInstance Win32_VideoController |
                Where-Object { $_.AdapterRAM -gt 0 }

        foreach ($gpu in $gpus) {
            $mb = [int]($gpu.AdapterRAM / 1MB)
            $name = $gpu.Name

            if ($mb -gt $hw.VramMB) {
                $hw.VramMB = $mb
                $hw.GpuVendor = switch -Wildcard ($name) {
                    '*NVIDIA*' { 'nvidia' }
                    '*AMD*'    { 'amd'   }
                    '*Radeon*' { 'amd'   }
                    '*Intel*'  { 'intel' }
                    default    { 'unknown' }
                }
            }
        }
    } catch {
        Write-Warning "VRAM detection failed: $_"
    }

    # WMI sometimes reports AdapterRAM as 4294967295 (~4GB) for cards
    # with >4GB VRAM due to a 32-bit overflow. Clamp to 0 in that case
    # and try nvidia-smi for a more accurate reading.
    if ($hw.VramMB -ge 4095) {
        try {
            $smiOut = & nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null
            if ($smiOut) {
                $hw.VramMB    = [int]($smiOut.Trim())
                $hw.GpuVendor = 'nvidia'
            }
        } catch { }
    }

    # ----------------------------------------------------------------
    # CPU vendor string
    # ----------------------------------------------------------------
    try {
        $cpuName = (Get-CimInstance Win32_Processor | Select-Object -First 1).Name
        $hw.Chipset = switch -Wildcard ($cpuName) {
            '*Intel*' { 'intel' }
            '*AMD*'   { 'amd'   }
            default   { 'unknown' }
        }
    } catch { }

    # ----------------------------------------------------------------
    # InferenceMB: VRAM if GPU present, else half of RAM
    # ----------------------------------------------------------------
    if ($hw.VramMB -gt 0) {
        $hw.InferenceMB = $hw.VramMB
    } else {
        $hw.InferenceMB = [int]($hw.RamMB * 0.50)
    }

    # ----------------------------------------------------------------
    # Node profile
    # ----------------------------------------------------------------
    if ($hw.RamMB -ge 32768) {
        $hw.NodeProfile   = 'secondary'
        $hw.ProfileReason = "Windows x86_64, $($hw.RamMB)MB RAM — secondary worker"
    } elseif ($hw.VramMB -ge 1024) {
        $hw.NodeProfile   = 'windows-thin'
        $hw.ProfileReason = "Windows x86_64, $($hw.RamMB)MB RAM, $($hw.VramMB)MB VRAM — thin GPU node"
    } else {
        $hw.NodeProfile   = 'micro'
        $hw.ProfileReason = "Windows x86_64, $($hw.RamMB)MB RAM, no usable GPU — micro node"
    }

    # ----------------------------------------------------------------
    # MAC address of primary adapter (needed for pfsense DHCP reservation)
    # ----------------------------------------------------------------
    try {
        $hw.MacAddress = (Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } |
                         Sort-Object -Property LinkSpeed -Descending |
                         Select-Object -First 1).MacAddress
    } catch { $hw.MacAddress = 'unknown' }

    $global:HW = $hw
    return $hw
}


function Print-HwSummary {
    param([hashtable]$hw = $global:HW)
    Write-Host "--- Hardware Detection Summary ---" -ForegroundColor Cyan
    Write-Host "  CPU arch    : $($hw.CpuArch)"
    Write-Host "  Chipset     : $($hw.Chipset)"
    Write-Host "  System RAM  : $($hw.RamMB) MB"
    Write-Host "  GPU vendor  : $($hw.GpuVendor)"
    Write-Host "  VRAM        : $($hw.VramMB) MB"
    Write-Host "  Inference   : $($hw.InferenceMB) MB usable for models"
    Write-Host "  Node profile: $($hw.NodeProfile)" -ForegroundColor Green
    Write-Host "  Reason      : $($hw.ProfileReason)"
    Write-Host "  MAC address : $($hw.MacAddress)  <- add to pfsense DHCP"
    Write-Host "----------------------------------" -ForegroundColor Cyan
}


function HW-ToJson {
    param([hashtable]$hw = $global:HW)
    $hw | ConvertTo-Json -Compress
}
