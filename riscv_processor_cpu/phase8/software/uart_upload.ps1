[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Port = "COM4",

    [Parameter(Mandatory = $false)]
    [string]$File = "build/snake_app.bin",

    [Parameter(Mandatory = $false)]
    [int]$Baud = 115200,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 100)]
    [int]$InterByteDelayMs = 2,

    [switch]$Run
)

$ErrorActionPreference = "Stop"
$maximumImageSize = 49152
$transferBlockSize = 32

if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
    throw "Application image not found: $File"
}

$image = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $File))
if ($image.Length -eq 0 -or $image.Length -gt $maximumImageSize) {
    throw "Image size $($image.Length) is outside the valid range 1..$maximumImageSize bytes."
}

if (-not ("RvblCrc32" -as [type])) {
    Add-Type -TypeDefinition @"
using System;
public static class RvblCrc32 {
    public static uint Compute(byte[] data) {
        uint crc = 0xffffffffu;
        foreach (byte value in data) {
            crc ^= value;
            for (int bit = 0; bit < 8; ++bit) {
                crc = (crc >> 1) ^ ((crc & 1u) != 0 ? 0xedb88320u : 0u);
            }
        }
        return crc ^ 0xffffffffu;
    }
}
"@
}

function Wait-RvblLine {
    param(
        [System.IO.Ports.SerialPort]$Serial,
        [string]$Expected,
        [int]$TimeoutMilliseconds = 8000,
        [switch]$Quiet
    )

    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $line = $Serial.ReadLine().Trim()
            if ($line) {
                if (-not $Quiet -or $line -ne $Expected) {
                    Write-Host "CPU  $line"
                }
                if ($line -eq $Expected) {
                    return
                }
                if ($line.StartsWith("RVBL:ERR")) {
                    throw "Bootloader rejected the transfer: $line"
                }
            }
        } catch [System.TimeoutException] {
            # Keep polling until the overall deadline expires.
        }
    }
    throw "Timed out waiting for '$Expected'. Close PuTTY, press BTN0, and retry."
}

function Send-RvblBytes {
    param(
        [System.IO.Ports.SerialPort]$Serial,
        [byte[]]$Bytes,
        [int]$DelayMilliseconds
    )

    for ($offset = 0; $offset -lt $Bytes.Length; ++$offset) {
        $Serial.Write($Bytes, $offset, 1)
        if ($DelayMilliseconds -gt 0) {
            [System.Threading.Thread]::Sleep($DelayMilliseconds)
        }
    }
}

$crc = [RvblCrc32]::Compute($image)
$header = New-Object byte[] 12
[Array]::Copy([Text.Encoding]::ASCII.GetBytes("RVBL"), 0, $header, 0, 4)
[Array]::Copy([BitConverter]::GetBytes([uint32]$image.Length), 0, $header, 4, 4)
[Array]::Copy([BitConverter]::GetBytes([uint32]$crc), 0, $header, 8, 4)

$serial = [System.IO.Ports.SerialPort]::new(
    $Port,
    $Baud,
    [System.IO.Ports.Parity]::None,
    8,
    [System.IO.Ports.StopBits]::One
)
$serial.Handshake = [System.IO.Ports.Handshake]::None
$serial.DtrEnable = $false
$serial.RtsEnable = $false
$serial.NewLine = "`n"
$serial.ReadTimeout = 250
$serial.WriteTimeout = 5000

try {
    Write-Host ("Uploading {0} bytes to {1} at {2} baud (CRC32 {3:X8}, {4} ms pacing)..." -f `
        $image.Length, $Port, $Baud, $crc, $InterByteDelayMs)
    try {
        $serial.Open()
    } catch {
        throw "Cannot open $Port. Close PuTTY or any other serial terminal using the port, verify the FPGA is connected, and retry. $($_.Exception.Message)"
    }
    Start-Sleep -Milliseconds 150
    $serial.DiscardInBuffer()

    $command = if ($Run) { "A" } else { "U" }
    $serial.Write($command)
    Wait-RvblLine -Serial $serial -Expected "RVBL:READY"

    # Let the target finish returning from the READY print routine before the
    # binary header starts. This also cleanly separates text and binary phases.
    Start-Sleep -Milliseconds 20
    Send-RvblBytes -Serial $serial -Bytes $header -DelayMilliseconds $InterByteDelayMs
    Wait-RvblLine -Serial $serial -Expected "RVBL:HEADER_OK"

    Start-Sleep -Milliseconds 20
    for ($offset = 0; $offset -lt $image.Length; $offset += $transferBlockSize) {
        $blockLength = [Math]::Min($transferBlockSize, $image.Length - $offset)
        $block = New-Object byte[] $blockLength
        [Array]::Copy($image, $offset, $block, 0, $blockLength)
        Send-RvblBytes -Serial $serial -Bytes $block -DelayMilliseconds $InterByteDelayMs

        $received = $offset + $blockLength
        try {
            Wait-RvblLine -Serial $serial -Expected "RVBL:NEXT $received" `
                -TimeoutMilliseconds 5000 -Quiet
        } catch {
            throw "Transfer lost synchronization after $offset of $($image.Length) bytes. $($_.Exception.Message)"
        }

        $percent = [Math]::Floor(($received * 100.0) / $image.Length)
        Write-Progress -Activity "Uploading firmware" `
            -Status "$received / $($image.Length) bytes acknowledged" `
            -PercentComplete $percent
    }
    Write-Progress -Activity "Uploading firmware" -Completed
    Wait-RvblLine -Serial $serial -Expected "RVBL:OK" -TimeoutMilliseconds 15000

    if ($Run) {
        Write-Host "Upload verified. The CPU is starting the application."
    } else {
        Write-Host "Upload verified. Close this uploader, open PuTTY, and press G to start it."
    }
} finally {
    if ($serial.IsOpen) {
        $serial.Close()
    }
    $serial.Dispose()
}
