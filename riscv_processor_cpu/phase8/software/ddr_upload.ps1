[CmdletBinding()]
param(
    [string]$Port = "COM4",
    [string]$File = "build/ddr_app_test.bin",
    [int]$Baud = 115200,
    [ValidateRange(0, 100)][int]$InterByteDelayMs = 2,
    [switch]$Run,
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
    param([IO.Ports.SerialPort]$Serial, [string]$Expected, [int]$TimeoutMs = 10000)
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        try {
            $line = $Serial.ReadLine().Trim()
            if ($line -eq $Expected) { return }
            if ($line.StartsWith("RDD1:ERR")) { throw "Loader rejected transfer: $line" }
            if ($Expected.StartsWith("RDD1:INFO ") -and $line.StartsWith("RDD1:INFO ")) {
                throw "Loader image state changed after upload: $line. Expected $Expected."
            }
            if ($line) { Write-Host "CPU  $line" }
        } catch [TimeoutException] { }
    }
    throw "Timed out waiting for '$Expected'. Close PuTTY and check the DDR loader bitstream."
}
function Send-Bytes {
    param([IO.Ports.SerialPort]$Serial, [byte[]]$Bytes, [int]$DelayMs)
    for ($i = 0; $i -lt $Bytes.Length; ++$i) {
        $Serial.Write($Bytes, $i, 1)
        if ($DelayMs -gt 0) { [Threading.Thread]::Sleep($DelayMs) }
    }
}

$crc = [Rdd1Crc32]::Compute($image)
$header = New-Object byte[] 12
[Array]::Copy([Text.Encoding]::ASCII.GetBytes("RDD1"), 0, $header, 0, 4)
[Array]::Copy([BitConverter]::GetBytes([uint32]$image.Length), 0, $header, 4, 4)
[Array]::Copy([BitConverter]::GetBytes([uint32]$crc), 0, $header, 8, 4)
Write-Host ("RDD1 image: {0} bytes, CRC32 {1:X8}, destination 0x80000000" -f $image.Length, $crc)
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
    $serial.Write($(if ($Run) { "A" } else { "U" }))
    Wait-Line $serial "RDD1:READY"
    Start-Sleep -Milliseconds 20
    Send-Bytes $serial $header $InterByteDelayMs
    Wait-Line $serial "RDD1:HEADER_OK"
    Start-Sleep -Milliseconds 20
    for ($offset = 0; $offset -lt $image.Length; $offset += 16) {
        $length = [Math]::Min(16, $image.Length - $offset)
        $block = New-Object byte[] $length
        [Array]::Copy($image, $offset, $block, 0, $length)
        Send-Bytes $serial $block $InterByteDelayMs
        $received = $offset + $length
        Wait-Line $serial "RDD1:NEXT $received" 10000
        Write-Progress -Activity "Loading DDR" -Status "$received / $($image.Length)" `
            -PercentComplete ([int](100 * $received / $image.Length))
    }
    Write-Progress -Activity "Loading DDR" -Completed
    Wait-Line $serial "RDD1:OK" 30000
    if ($Run) {
        Wait-Line $serial "RDD1:GO" 5000
        $deadline = [DateTime]::UtcNow.AddSeconds(2)
        while ([DateTime]::UtcNow -lt $deadline) {
            try {
                $line = $serial.ReadLine().Trim()
                if ($line) { Write-Host "CPU  $line" }
            } catch [TimeoutException] { }
        }
    } else {
        $serial.Write("I")
        Wait-Line $serial "RDD1:INFO BASE=80000000 MAX=4194304 LOADED=$($image.Length)" 5000
        Write-Host "DDR image verified; loader confirms LOADED=$($image.Length)."
        Write-Host "Open PuTTY on the same port at $Baud baud and press uppercase G."
        Write-Host "Do not press BTN0, reprogram, or power-cycle between upload and G."
        Write-Host "If G reports NO_IMAGE, press I to inspect the state, then close PuTTY and upload again."
    }
} finally {
    if ($serial.IsOpen) { $serial.Close() }
    $serial.Dispose()
}
