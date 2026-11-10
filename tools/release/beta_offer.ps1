# Generate signed beta passes and feed offers. This tool only writes the requested local output file.
param(
    [Parameter(Mandatory)][ValidateSet('Invite','Offer')][string]$Mode,
    [Parameter(Mandatory)][string]$KeyFile,
    [Parameter(Mandatory)][string]$Output,
    [ValidateRange(1,90)][int]$Days = 14,
    [string]$Installation,
    [string]$Feed,
    [string]$Package,
    [string]$Url,
    [string]$Note = ''
)
$ErrorActionPreference = 'Stop'
$utf8 = [Text.UTF8Encoding]::new($false)
function Require-Https([string]$Value) {
    [Uri]$address = $null
    if ($Value.Length -gt 2048 -or -not [Uri]::TryCreate($Value,[UriKind]::Absolute,[ref]$address) -or
        $address.Scheme -ne 'https' -or -not $address.Host -or $address.UserInfo -or $address.Fragment) {
        throw 'Use a direct HTTPS URL.'
    }
}
$expires = [DateTimeOffset]::UtcNow.AddDays($Days).ToUnixTimeSeconds()
if ($Mode -eq 'Invite') {
    [Guid]$id = [Guid]::Empty
    if (-not [Guid]::TryParseExact($Installation, 'N', [ref]$id)) { throw 'Pass the tester installation number.' }
    Require-Https $Feed
    $fields = [ordered]@{ kind = 'pg-beta-pass-1'; installation = $id.ToString('N'); feed = $Feed; expires = $expires }
} else {
    Require-Https $Url
    if ($Note.Length -gt 1200) { throw 'Keep the test note within 1200 characters.' }
    $file = Get-Item -LiteralPath $Package
    if ($file.PSIsContainer -or $file.Length -le 0 -or $file.Length -gt 256MB) { throw 'Invalid beta ZIP size.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($file.FullName)
    try {
        $entries = @($zip.Entries | Where-Object FullName -Match '^[^/]+/app/version\.json$')
        if ($entries.Count -ne 1 -or $entries[0].Length -gt 16384) { throw 'Expected one app/version.json in the ZIP.' }
        $reader = [IO.StreamReader]::new($entries[0].Open(),$utf8)
        try { $version = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
    } finally { $zip.Dispose() }
    if ($version.channel -eq 'nexus' -or $version.appVersion -notmatch '^\d{1,4}\.\d{1,4}\.\d{1,4}$' -or
        $version.modBuild -notmatch '^[A-Za-z0-9._-]{1,100}$') { throw 'Use a GitHub assistant package with a valid build marker.' }
    $fields = [ordered]@{
        kind = 'pg-beta-offer-1'; version = $version.appVersion; build = $version.modBuild
        size = $file.Length; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()
        url = $Url; note = $Note; expires = $expires
    }
}
$rsa = [Security.Cryptography.RSACryptoServiceProvider]::new()
$rsa.PersistKeyInCsp = $false
try {
    $rsa.FromXmlString([IO.File]::ReadAllText((Resolve-Path -LiteralPath $KeyFile).Path))
    $payload = $utf8.GetBytes(($fields | ConvertTo-Json -Compress))
    $signature = $rsa.SignData($payload,[Security.Cryptography.CryptoConfig]::MapNameToOID('SHA256'))
    $signed = [Convert]::ToBase64String($payload) + '.' + [Convert]::ToBase64String($signature)
    [IO.File]::WriteAllText($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Output),$signed,$utf8)
    "Wrote signed $Mode file."
} finally { $rsa.Dispose() }
