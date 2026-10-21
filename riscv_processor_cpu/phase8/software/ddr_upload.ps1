[CmdletBinding()]
param(
    [string]$Port = "COM4",
    [string]$File = "build/ddr_app_test.bin",
    [string]$WadFile = "",
    [int]$Baud = 115200,
    [ValidateRange(0, 100)][int]$InterByteDelayMs = 2,
    [switch]$LegacyWadTransfer,
    [switch]$Run,
    [switch]$GraphicalViewer,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
    throw "DDR application not found: $File"
}
$image = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $File))
if ($image.Length -lt 1 -or $image.Length -gt 4194304) {
    throw "DDR application must be 1..4194304 bytes."
}
$wad = $null
if ($WadFile) {
    if (-not (Test-Path -LiteralPath $WadFile -PathType Leaf)) {
        throw "WAD not found: $WadFile"
    }
    $wad = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $WadFile))
    if ($wad.Length -lt 12 -or $wad.Length -gt 33554432) {
        throw "WAD must be 12..33554432 bytes."
    }
    $magic = [Text.Encoding]::ASCII.GetString($wad, 0, 4)
    $count = [BitConverter]::ToUInt32($wad, 4)
    $directory = [BitConverter]::ToUInt32($wad, 8)
    if (($magic -ne "IWAD" -and $magic -ne "PWAD") -or
        $directory -gt $wad.Length -or $count -gt [Math]::Floor(($wad.Length - $directory) / 16)) {
        throw "WAD header or directory is invalid."
    }
    for ($i = 0; $i -lt $count; ++$i) {
        $entry = [int]$directory + $i * 16
        $position = [BitConverter]::ToUInt32($wad, $entry)
        $length = [BitConverter]::ToUInt32($wad, $entry + 4)
        if ($length -and ($position -gt $wad.Length -or $length -gt $wad.Length - $position)) {
            throw "WAD lump $i points outside the file."
        }
    }
}
if (-not ("Rdd1Crc32" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
public static class Rdd1Crc32 {
    public static uint Compute(byte[] bytes) {
        uint crc = 0xffffffffu;
        foreach (byte b in bytes) {
            crc ^= b;
            for (int bit = 0; bit < 8; bit++)
                crc = (crc >> 1) ^ ((crc & 1u) != 0 ? 0xedb88320u : 0u);
        }
        return crc ^ 0xffffffffu;
    }
}
"@
}
function Wait-Line {
    param([IO.Ports.SerialPort]$Serial, [string]$Expected, [int]$TimeoutMs = 10000,
          [switch]$AllowSuffix, [switch]$Optional, [string]$TimeoutMessage = "")
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $line = $Serial.ReadLine().Trim()
            if ($line -eq $Expected -or ($AllowSuffix -and $line.StartsWith($Expected))) {
                if ($Optional) { return $true }
                return
            }
            if ($line.StartsWith("RDD1:ERR") -or $line.StartsWith("RDDW:ERR")) {
                throw "Loader rejected transfer: $line"
            }
            if (($Expected.StartsWith("RDD1:INFO ") -and $line.StartsWith("RDD1:INFO ")) -or
                ($Expected.StartsWith("RDDW:INFO ") -and $line.StartsWith("RDDW:INFO "))) {
                throw "Loader image state changed after upload: $line. Expected $Expected."
            }
            if ($line) { Write-Host "CPU  $line" }
        } catch [TimeoutException] { }
    }
    if ($Optional) { return $false }
    if ($TimeoutMessage) { throw $TimeoutMessage }
    throw "Timed out waiting for '$Expected'. Close PuTTY and check the DDR loader bitstream."
}
function Send-Bytes {
    param([IO.Ports.SerialPort]$Serial, [byte[]]$Bytes, [int]$DelayMs,
          [int]$Offset = 0, [int]$Count = -1)
    if ($Count -lt 0) { $Count = $Bytes.Length - $Offset }
    if ($DelayMs -eq 0) {
        $Serial.Write($Bytes, $Offset, $Count)
        return
    }
    for ($i = $Offset; $i -lt $Offset + $Count; ++$i) {
        $Serial.Write($Bytes, $i, 1)
        if ($DelayMs -gt 0) { [Threading.Thread]::Sleep($DelayMs) }
    }
}
function Send-Payload {
    param([IO.Ports.SerialPort]$Serial, [byte[]]$Bytes,
          [string]$Prefix, [int]$DelayMs, [int]$BlockBytes = 16)
    for ($offset = 0; $offset -lt $Bytes.Length; $offset += $BlockBytes) {
        $length = [Math]::Min($BlockBytes, $Bytes.Length - $offset)
        Send-Bytes $Serial $Bytes $DelayMs $offset $length
        $received = $offset + $length
        Wait-Line $Serial "$($Prefix):NEXT $received" 10000
        if (($received % 16384) -eq 0 -or $received -eq $Bytes.Length) {
            Write-Progress -Activity "Loading DDR $Prefix" -Status "$received / $($Bytes.Length)" `
                -PercentComplete ([int](100 * $received / $Bytes.Length))
        }
    }
    Write-Progress -Activity "Loading DDR $Prefix" -Completed
    $verifyTimeout = [int][Math]::Min(600000, [Math]::Max(30000, $Bytes.Length * 0.1))
    Wait-Line $Serial "$($Prefix):OK" $verifyTimeout
}

$crc = [Rdd1Crc32]::Compute($image)
$header = New-Object byte[] 12
[Array]::Copy([Text.Encoding]::ASCII.GetBytes("RDD1"), 0, $header, 0, 4)
[Array]::Copy([BitConverter]::GetBytes([uint32]$image.Length), 0, $header, 4, 4)
[Array]::Copy([BitConverter]::GetBytes([uint32]$crc), 0, $header, 8, 4)
Write-Host ("RDD1 image: {0} bytes, CRC32 {1:X8}, destination 0x80000000" -f $image.Length, $crc)
if ($wad) {
    $wadCrc = [Rdd1Crc32]::Compute($wad)
    $wadHeader = New-Object byte[] 12
    [Array]::Copy([Text.Encoding]::ASCII.GetBytes("RDDW"), 0, $wadHeader, 0, 4)
    [Array]::Copy([BitConverter]::GetBytes([uint32]$wad.Length), 0, $wadHeader, 4, 4)
    [Array]::Copy([BitConverter]::GetBytes([uint32]$wadCrc), 0, $wadHeader, 8, 4)
    Write-Host ("RDDW WAD: {0} bytes, {1} lumps, CRC32 {2:X8}, destination 0x82000000" -f `
        $wad.Length, $count, $wadCrc)
}
if ($DryRun) { return }

$serial = [IO.Ports.SerialPort]::new($Port, $Baud, [IO.Ports.Parity]::None, 8,
                                     [IO.Ports.StopBits]::One)
$serial.Handshake = [IO.Ports.Handshake]::None
$serial.DtrEnable = $false
$serial.RtsEnable = $false
$serial.NewLine = "`n"
$serial.ReadTimeout = 250
$serial.WriteTimeout = 5000
try {
    try { $serial.Open() }
    catch { throw "Cannot open $Port. Close PuTTY and check the USB serial port. $($_.Exception.Message)" }
    Start-Sleep -Milliseconds 150
    $serial.DiscardInBuffer()
    if ($wad) {
        $serial.Write("J")
        Wait-Line $serial "RDDW:INFO BASE=82000000 MAX=33554432 LOADED=" 3000 `
            -AllowSuffix -TimeoutMessage "No reply from the WAD-capable loader. If you pressed G after a previous upload, close PuTTY, press BTN0 once to return to the loader, and retry. If the loader's idle line lacks W=wad and J=wad-info, rebuild and program the arty_s7_ddr_loader bitstream."
        $wadBlockBytes = 16
        if (-not $LegacyWadTransfer) {
            $serial.Write("K")
            if (Wait-Line $serial "RDDW:CAPS FAST_BLOCK=1024" 1500 -Optional) {
                $wadBlockBytes = 1024
            } elseif ($wad.Length -gt 65536) {
                throw "This loader only supports 16-byte WAD blocks. Rebuild and program the fast-capable arty_s7_ddr_loader bitstream before uploading a large WAD, or pass -LegacyWadTransfer to accept the slow transfer."
            }
        }
        Write-Host "WAD transfer: $wadBlockBytes-byte acknowledged blocks."
    }
    $serial.Write($(if ($Run -and -not $wad) { "A" } else { "U" }))
    Wait-Line $serial "RDD1:READY"
    Start-Sleep -Milliseconds 20
    Send-Bytes $serial $header $InterByteDelayMs
    Wait-Line $serial "RDD1:HEADER_OK"
    Start-Sleep -Milliseconds 20
    Send-Payload $serial $image "RDD1" $InterByteDelayMs
    if ($wad) {
        $serial.Write($(if ($wadBlockBytes -eq 1024) { "F" } else { "W" }))
        Wait-Line $serial "RDDW:READY"
        Start-Sleep -Milliseconds 20
        Send-Bytes $serial $wadHeader $InterByteDelayMs
        Wait-Line $serial "RDDW:HEADER_OK"
        Start-Sleep -Milliseconds 20
        $wadTimer = [Diagnostics.Stopwatch]::StartNew()
        Send-Payload $serial $wad "RDDW" $InterByteDelayMs $wadBlockBytes
        $wadTimer.Stop()
        Write-Host ("WAD payload verified in {0:n1} s ({1:n1} KiB/s)." -f `
            $wadTimer.Elapsed.TotalSeconds, `
            ($wad.Length / 1024.0 / [Math]::Max(0.001, $wadTimer.Elapsed.TotalSeconds)))
        $serial.Write("J")
        Wait-Line $serial "RDDW:INFO BASE=82000000 MAX=33554432 LOADED=$($wad.Length)" 5000
    }
    if ($Run) {
        if ($wad) { $serial.Write("G") }
        Wait-Line $serial "RDD1:GO" 5000
        $deadline = [DateTime]::UtcNow.AddSeconds(2)
        while ([DateTime]::UtcNow -lt $deadline) {
            try {
                $line = $serial.ReadLine().Trim()
                if ($line) { Write-Host "CPU  $line" }
            } catch [TimeoutException] { }
        }
        Write-Host "Press BTN0 before another upload; the loader is not active while the application runs."
    } else {
        $serial.Write("I")
        Wait-Line $serial "RDD1:INFO BASE=80000000 MAX=4194304 LOADED=$($image.Length)" 5000
        Write-Host "DDR image verified; loader confirms LOADED=$($image.Length)."
        if ($GraphicalViewer) {
            Write-Host "Start the graphical viewer: make ddr_doom_view PORT=$Port DDR_BAUD=$Baud"
            Write-Host "Keep PuTTY closed. The viewer sends G and displays binary frames."
        } else {
            Write-Host "Open PuTTY on the same port at $Baud baud and press uppercase G."
        }
        Write-Host "Do not press BTN0, reprogram, or power-cycle between upload and G."
        Write-Host "After running the application with G, press BTN0 before starting a different upload."
        Write-Host "If G reports NO_IMAGE, press I to inspect the state, then close PuTTY and upload again."
    }
} finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
}
