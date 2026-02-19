$path = $args[0]

if (-not $path) {
    Write-Host "Usage: .\SequenceNumberChecker.ps1 'C:\Path\To\File'`n"
    Write-Host 'No file specified, aborting... ' -NoNewline
    pause
    exit 1
}

if (-not (Test-Path $path)) {
    Write-Host 'File not found, aborting...'
    pause
    exit 1
}

$sysTemp = 'C:\Windows\Temp\'
$file = Split-Path -Path $path -Leaf
$copyPath = Join-Path -Path $sysTemp -ChildPath $file

Copy-Item -Path $path -Destination $copyPath

if (-not (Test-Path $copyPath)) {
    Write-Host 'Failed to create copy, aborting...'
    pause
    exit 1
}

$hive = New-Object IO.FileStream($copyPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)

if (-not $hive) {
    Write-Host 'Failed to open the file, aborting...'
    pause
    exit 1
}

# Get primary sequence number
$hive.Seek(4, [IO.SeekOrigin]::Begin) | Out-Null
$primary = $hive.ReadByte()

# Get secondary sequence number
$hive.Seek(8, [IO.SeekOrigin]::Begin) | Out-Null
$secondary = $hive.ReadByte()

if ($primary -eq $secondary) {
    Write-Host 'No sequence number mismatch found, aborting...'
    pause
    exit 1
}

Write-Host 'Primary and secondary sequence number mismatch!'
Write-Host 'Performing repairs...'

# Increment sequence num and wrap around since it should be 8-bit
$updatedPrimary = ($primary+1) % 256

# Update the primary sequence number
$hive.Seek(4, [IO.SeekOrigin]::Begin) | Out-Null
$hive.WriteByte($updatedPrimary)

# Update the secondary sequence number
$hive.Seek(8, [IO.SeekOrigin]::Begin) | Out-Null
$hive.WriteByte($updatedPrimary)

$hive.Seek(0, [IO.SeekOrigin]::Begin) | Out-Null

$index = 0
$checksum = New-Object byte[] 4
$bytes = New-Object byte[] 4

# Calculate the new checksum value
while ($index -le 0x1fb) {
    $hive.Read($bytes, 0, 4) | Out-Null

    # I barely know how to do bitwise operations in PowerShell,
    # I ain't figuring out how to correct for endianness.
    # Instead, update the checksum in discrete bytes.
    # In the single test I did, the resulting file had the same hash
    # as when I used the original C++ version,
    # and I'm willing to assume that wasn't a coincidence.
    foreach ($i in 0..3) {
        $checksum[$i] = $checksum[$i] -bxor $bytes[$i]
    }

    $index += 4
}

$hive.Seek(0x1fc, [IO.SeekOrigin]::Begin) | Out-Null
foreach ($i in 0..3) {
    $hive.WriteByte($checksum[$i])
}

$hive.Dispose()

Write-Host 'Repairs have completed. If you are repairing a registry hive,'
Write-Host 'you will have to replace the original file from the recovery console.'
Write-Host "The new file is located at: $copyPath"
pause
exit 0