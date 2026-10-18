[CmdletBinding()]
param(
    [ValidateRange(1, 1000000000)]
    [long]$CoreClockHz = 25000000,

    [long[]]$BaudRates = @(115200, 921600, 1000000, 2000000)
)

$ErrorActionPreference = 'Stop'

$frameCases = @(
    [pscustomobject]@{ Mode = '320x200 indexed, binary'; Bytes = 64000 },
    [pscustomobject]@{ Mode = '64x32 binary + 10-byte header'; Bytes = 2058 },
    [pscustomobject]@{ Mode = '80x25 ASCII'; Bytes = 2051 },
    [pscustomobject]@{ Mode = '80x40 ASCII'; Bytes = 3281 },
    [pscustomobject]@{ Mode = '80x20 UTF8 blocks, indexed FG/BG'; Bytes = 40041 },
    [pscustomobject]@{ Mode = '80x20 UTF8 blocks, RGB FG/BG'; Bytes = 65641 }
)

Write-Output 'Ideal 8N1 link limits; engine time, terminal rendering, gaps and USB overhead excluded.'
foreach ($baud in $BaudRates) {
    if ($baud -le 0 -or $baud -gt $CoreClockHz) {
        throw "Baud rate $baud must be positive and no greater than CoreClockHz."
    }

    $divisor = [math]::Floor($CoreClockHz / [double]$baud)
    $actualBaud = $CoreClockHz / $divisor
    $baudError = 100.0 * ($actualBaud / $baud - 1.0)
    Write-Output ("`nRequested {0} baud: divisor {1}, actual {2:N3}, error {3:N3}%" -f `
        $baud, $divisor, $actualBaud, $baudError)

    $frameCases | ForEach-Object {
        [pscustomobject]@{
            Mode = $_.Mode
            BytesPerFrame = $_.Bytes
            IdealFPS = [math]::Round($baud / 10.0 / $_.Bytes, 3,
                [MidpointRounding]::AwayFromZero)
        }
    } | Format-Table -AutoSize | Out-String | Write-Output
}

Write-Output ("35 Hz game-tic budget at {0} Hz: {1:N0} cycles/tic" -f `
    $CoreClockHz, ($CoreClockHz / 35.0))
Write-Output 'ASCII sizes assume ESC[H plus CRLF between rows, with wrap disabled.'
Write-Output 'Block sizes assume three-byte glyphs and separate maximum-length FG/BG escapes per cell.'
Write-Output 'Link FPS uses requested baud; the actual divisor result is shown separately.'
