[CmdletBinding()]
param(
    [string]$EncryptedFile = ".\android-signing-key.zip.enc",
    [string]$OutputDirectory = ".\android-signing-key-unpacked"
)

$ErrorActionPreference = "Stop"
$openssl = "C:\Program Files\Git\usr\bin\openssl.exe"
if (-not (Test-Path -LiteralPath $openssl -PathType Leaf)) {
    throw "OpenSSL was not found at '$openssl'. Install Git for Windows or edit the openssl path in this script."
}
if (-not (Test-Path -LiteralPath $EncryptedFile -PathType Leaf)) {
    throw "Encrypted artifact not found: $EncryptedFile"
}

$encryptedPath = (Resolve-Path -LiteralPath $EncryptedFile).Path
$workDir = Split-Path -Parent $encryptedPath
$tempPassword = Join-Path $workDir ".keystore-export-passphrase.tmp"
$tempZip = Join-Path $workDir ".android-signing-key.decrypted.tmp.zip"
$finalZip = Join-Path $workDir "android-signing-key.zip"
$bstr = [IntPtr]::Zero
$password = $null

try {
    $secure = Read-Host "Enter KEYSTORE_EXPORT_PASSPHRASE (input is hidden)" -AsSecureString
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)

    # OpenSSL's Windows build may not inherit PowerShell environment variables
    # consistently. A short-lived UTF-8 password file avoids that issue.
    [System.IO.File]::WriteAllText($tempPassword, $password, [System.Text.UTF8Encoding]::new($false))

    Push-Location -LiteralPath $workDir
    try {
        & $openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -in $encryptedPath -out $tempZip -pass "file:./.keystore-export-passphrase.tmp"
        $opensslExitCode = $LASTEXITCODE
    }
    finally {
        Pop-Location
    }

    if ($opensslExitCode -ne 0) {
        throw "Decryption failed. Check KEYSTORE_EXPORT_PASSPHRASE; no key was changed."
    }

    Add-Type -AssemblyName System.IO.Compression
    $archive = [System.IO.Compression.ZipFile]::OpenRead($tempZip)
    try {
        $required = @(
            "output/upload-keystore.jks",
            "output/release-secrets.txt",
            "output/README.txt"
        )
        $entryNames = @($archive.Entries | ForEach-Object { $_.FullName })
        foreach ($entry in $required) {
            if ($entryNames -notcontains $entry) {
                throw "Decrypted data is not the expected signing archive (missing $entry)."
            }
        }
    }
    finally {
        $archive.Dispose()
    }

    Move-Item -LiteralPath $tempZip -Destination $finalZip -Force
    if (Test-Path -LiteralPath $OutputDirectory) {
        Remove-Item -LiteralPath $OutputDirectory -Recurse -Force
    }
    Expand-Archive -LiteralPath $finalZip -DestinationPath $OutputDirectory -Force

    Write-Host "Decryption and archive validation succeeded." -ForegroundColor Green
    Write-Host "Extracted files:"
    Get-ChildItem -LiteralPath $OutputDirectory -Recurse -File | Select-Object Name, Length
    Write-Host ""
    Write-Host "IMPORTANT: Do not share release-secrets.txt or upload-keystore.jks."
}
finally {
    Remove-Item -LiteralPath $tempPassword -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempZip -Force -ErrorAction SilentlyContinue
    if ($bstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    $password = $null
    Remove-Variable secure -ErrorAction SilentlyContinue
}
