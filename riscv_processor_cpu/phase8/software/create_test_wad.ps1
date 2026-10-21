[CmdletBinding()]
param(
    [string]$OutputFile = "build/ddr_test.wad",
    [ValidateRange(4, 1048576)][int]$PayloadBytes = 4
)
$ErrorActionPreference = "Stop"
$outputPath = [IO.Path]::GetFullPath($OutputFile)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputPath)) | Out-Null
$stream = [IO.File]::Create($outputPath)
try {
    $writer = [IO.BinaryWriter]::new($stream)
    try {
        $writer.Write([Text.Encoding]::ASCII.GetBytes("PWAD"))
        $writer.Write([uint32]1)
        $writer.Write([uint32](12 + $PayloadBytes))
        $writer.Write([Text.Encoding]::ASCII.GetBytes("RV32"))
        $remaining = $PayloadBytes - 4
        while ($remaining -gt 0) {
            $chunk = [Math]::Min($remaining, 4096)
            $writer.Write((New-Object byte[] $chunk))
            $remaining -= $chunk
        }
        $writer.Write([uint32]12)
        $writer.Write([uint32]$PayloadBytes)
        $writer.Write([Text.Encoding]::ASCII.GetBytes("HELLO"))
        $writer.Write((New-Object byte[] 3))
    } finally { $writer.Dispose() }
} finally { $stream.Dispose() }
Write-Host "WAD fixture built: $outputPath"
