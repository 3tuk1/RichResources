$info = Get-Content -Raw "info.json" -Encoding UTF8 | ConvertFrom-Json
$name = $info.name
$version = $info.version
$folderName = "${name}_${version}"
$zipName = "${folderName}.zip"

Write-Host "Creating release for $name $version..."

# Create clean destination
if (Test-Path $folderName) { Remove-Item -Recurse -Force $folderName }
New-Item -ItemType Directory -Path $folderName | Out-Null

# Copy items explicitly to avoid excluding issues
$items = Get-ChildItem -Path . 

foreach ($item in $items) {
    # Exclude list
    if ($item.Name -in @(".git", ".vscode", ".gitignore", "make_release.ps1", $zipName, $folderName)) {
        continue
    }
    Copy-Item -Path $item.FullName -Destination $folderName -Recurse
}

# Zip
if (Test-Path $zipName) { Remove-Item $zipName }

# Try to use 7z if available for proper slash handling
$7zLocations = @(
    "D:\WINDOWS CARE APP\7-Zip\7z.exe",
    "C:\Program Files\7-Zip\7z.exe",
    "C:\Program Files (x86)\7-Zip\7z.exe",
    "$env:ProgramFiles\7-Zip\7z.exe",
    "${env:ProgramFiles(x86)}\7-Zip\7z.exe"
)

$7zPath = $null
foreach ($path in $7zLocations) {
    if (Test-Path $path) {
        $7zPath = $path
        break
    }
}

if (-not $7zPath) {
    if (Get-Command "7z" -ErrorAction SilentlyContinue) {
        $7zPath = "7z"
    }
}

if ($7zPath) {
    Write-Host "Using 7-Zip ($7zPath)..."
    & $7zPath a -tzip $zipName $folderName
} else {
    Write-Warning "7-Zip not found. Falling back to Compress-Archive."
    Compress-Archive -Path $folderName -DestinationPath $zipName
}

# Cleanup
Remove-Item -Recurse -Force $folderName

Write-Host "Done! Created $zipName"
