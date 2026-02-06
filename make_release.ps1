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
Compress-Archive -Path $folderName -DestinationPath $zipName

# Cleanup
Remove-Item -Recurse -Force $folderName

Write-Host "Done! Created $zipName"
