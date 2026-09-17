# release.ps1 - the only way this fork ships. Every push is a version.
#
#   .\release.ps1 -Bump minor -Notes "Added §23 manufactured balance"
#   .\release.ps1 -Bump patch -Notes "Fixed the §8 example"
#
# What it does, in order: refuses a dirty tree that isn't just SKILL.md/README.md/sidecars, bumps
# metadata.version in SKILL.md (minor = new pattern or group, patch = wording/examples/word lists,
# major = rebase on a new upstream major), prepends the README release note, commits, tags vX.Y.Z,
# pushes branch + tag, creates the GitHub release. The pre-push hook (install once with
# .\release.ps1 -InstallHook) refuses any push whose HEAD is not tagged with SKILL.md's version,
# so a plain `git push` after an edit fails until you release.
param(
  [ValidateSet('major','minor','patch')][string]$Bump,
  [string]$Notes,
  [switch]$InstallHook
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

if ($InstallHook) {
  $hook = @'
#!/bin/sh
# pre-push: HEAD must carry the tag named by SKILL.md metadata.version. Ship via release.ps1.
v=$(sed -n 's/^  version: "\(.*\)"/\1/p' SKILL.md | head -1)
if ! git tag --points-at HEAD | grep -qx "v$v"; then
  echo "pre-push: HEAD is not tagged v$v (SKILL.md metadata.version). Run: pwsh release.ps1 -Bump patch|minor -Notes '...'" >&2
  exit 1
fi
'@
  Set-Content -Path .git/hooks/pre-push -Value $hook -NoNewline -Encoding ascii
  Write-Output "installed .git/hooks/pre-push"
  return
}
if (-not $Bump -or -not $Notes) { throw "need -Bump major|minor|patch and -Notes '...'" }

$skill = Get-Content SKILL.md -Raw
$cur = [regex]::Match($skill, '(?m)^  version: "(\d+)\.(\d+)\.(\d+)"')
if (-not $cur.Success) { throw "no metadata.version in SKILL.md" }
$maj,$min,$pat = [int]$cur.Groups[1].Value, [int]$cur.Groups[2].Value, [int]$cur.Groups[3].Value
switch ($Bump) { 'major' { $maj++; $min=0; $pat=0 } 'minor' { $min++; $pat=0 } 'patch' { $pat++ } }
$new = "$maj.$min.$pat"
if (git tag -l "v$new") { throw "tag v$new already exists" }

$skill = $skill -replace '(?m)^  version: ".*"', "  version: `"$new`""
Set-Content SKILL.md -Value $skill -NoNewline -Encoding utf8
$readme = Get-Content README.md -Raw
$marker = "<summary>Show release notes</summary>`n`n"
if ($readme -notmatch [regex]::Escape($marker)) { $marker = "<summary>Show release notes</summary>`r`n`r`n" }
$patterns = ([regex]::Matches($skill, '(?m)^### (\d+)\. ')).Count
$readme = $readme.Replace($marker, "$marker- **$new** (fork) - $Notes $patterns patterns total.`n")
Set-Content README.md -Value $readme -NoNewline -Encoding utf8

git add -A
git commit -q -m "v$new`: $Notes"
git tag -a "v$new" -m "$Notes"
git push -q origin HEAD
git push -q origin "v$new"
gh release create "v$new" --title "v$new" --notes "$Notes ($patterns patterns)" | Out-Null
Write-Output "released v$new"
