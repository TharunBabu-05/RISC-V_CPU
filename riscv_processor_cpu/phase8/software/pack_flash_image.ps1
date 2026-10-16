[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InputFile,

    [Parameter(Mandatory = $true)]
    [string]$OutputFile,

    [uint32]$EntryAddress = 0x00004000
)

$ErrorActionPreference = "Stop"
$maximumImageSize = 49152

if (-not (Test-Path -LiteralPath $InputFile -PathType Leaf)) {
    throw "Application image not found: $InputFile"
}

$payload = [System.IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $InputFile))
if ($payload.Length -eq 0 -or $payload.Length -gt $maximumImageSize) {
    throw "Image size $($payload.Length) is outside 1..$maximumImageSize bytes."
}

[uint32]$crc = [uint32]::MaxValue
foreach ($value in $payload) {
    $crc = $crc -bxor [uint32]$value
    for ($bit = 0; $bit -lt 8; ++$bit) {
        if (($crc -band 1) -ne 0) {
            $crc = ($crc -shr 1) -bxor [uint32]3988292384
        } else {
            $crc = $crc -shr 1
        }
    }
}
$crc = $crc -bxor [uint32]::MaxValue

$header = New-Object byte[] 16
[Array]::Copy([Text.Encoding]::ASCII.GetBytes("RVF1"), 0, $header, 0, 4)
[Array]::Copy([BitConverter]::GetBytes([uint32]$payload.Length), 0, $header, 4, 4)
[Array]::Copy([BitConverter]::GetBytes($crc), 0, $header, 8, 4)
[Array]::Copy([BitConverter]::GetBytes($EntryAddress), 0, $header, 12, 4)

$outputPath = [System.IO.Path]::GetFullPath($OutputFile)
$outputDirectory = [System.IO.Path]::GetDirectoryName($outputPath)
if ($outputDirectory) {
    [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
}

$stream = [System.IO.File]::Create($outputPath)
try {
    $stream.Write($header, 0, $header.Length)
    $stream.Write($payload, 0, $payload.Length)
} finally {
    $stream.Dispose()
}

Write-Host ("QSPI image: {0} payload bytes, CRC32 {1:X8}, entry 0x{2:X8}" -f `
    $payload.Length, $crc, $EntryAddress)
