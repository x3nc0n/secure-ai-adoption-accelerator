<#
.SYNOPSIS
    Source validator for Microsoft Sentinel - AI Governance Solution.

.DESCRIPTION
    Validates solution source files without requiring a deployed workspace or alert firing.
    Runs fourteen checks covering structure, syntax, uniqueness, security, and documentation.
    Exits with code 1 if any check fails; exits 0 if all pass.

    Concurrency note: If files expected by a check are not yet present (solution is partially
    scaffolded), the check reports a warning rather than a failure — unless the missing file
    is required by an existing artifact that references it, in which case it is a failure.
    This allows the validator to run incrementally as content is authored.

.PARAMETER SolutionRoot
    Path to the solution root folder.
    Default: ../Solutions/Microsoft Sentinel - AI Governance Solution  (relative to this script)

.PARAMETER RepoRoot
    Path to the repository root.
    Default: parent directory of the script's parent directory

.PARAMETER Strict
    If set, treat warnings as failures.

.PARAMETER PackagePath
    Optional path to a generated package directory. When supplied, enables Check 12:
    asserts mainTemplate.json and createUiDefinition.json exist at this path, parse as
    valid JSON, and contain the expected top-level ARM / UI-definition fields.
    Generator exit code alone is NOT sufficient — file presence and content are verified.
    Example: -PackagePath "Solutions\...\Package\1.0.0"

.PARAMETER ForbiddenValue
    Optional environment-specific values that must not appear in deployable source.
    Pass one or more workspace, resource-group, subscription, or tenant identifiers
    from the validation environment without committing them to this script.

.EXAMPLE
    .\Test-AIGovernanceSource.ps1
    .\Test-AIGovernanceSource.ps1 -SolutionRoot "C:\repo\Solutions\Microsoft Sentinel - AI Governance Solution"
    .\Test-AIGovernanceSource.ps1 -Strict
    .\Test-AIGovernanceSource.ps1 -PackagePath "Solutions\...\Package\1.0.0"
    .\Test-AIGovernanceSource.ps1 -ForbiddenValue "law-example","rg-example"
#>

[CmdletBinding()]
param (
    [Parameter()]
    [string]$SolutionRoot,

    [Parameter()]
    [string]$RepoRoot,

    [switch]$Strict,

    [Parameter()]
    [string]$PackagePath,

    [Parameter()]
    [string[]]$ForbiddenValue = @()
)

$ErrorActionPreference = 'Continue'

# Resolve paths
if (-not $SolutionRoot) {
    $SolutionRoot = Join-Path $PSScriptRoot "..\Solutions\Microsoft Sentinel - AI Governance Solution"
}
$SolutionRoot = [System.IO.Path]::GetFullPath($SolutionRoot)

if (-not $RepoRoot) {
    $RepoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
}

# Store this script's own path so expanded scans can exclude it (it intentionally
# contains detection pattern strings and must not flag itself).
$script:ValidatorScriptPath = $PSCommandPath
$script:ScriptsDir          = Join-Path $RepoRoot "scripts"

$script:Failures = [System.Collections.Generic.List[string]]::new()
$script:Warnings = [System.Collections.Generic.List[string]]::new()
$script:Passed   = [System.Collections.Generic.List[string]]::new()
$script:ChecksRun = 0

function Fail {
    param([string]$CheckName, [string]$Message)
    $entry = "[$CheckName] FAIL: $Message"
    $script:Failures.Add($entry)
    Write-Host "  FAIL  $Message" -ForegroundColor Red
}

function Warn {
    param([string]$CheckName, [string]$Message)
    $entry = "[$CheckName] WARN: $Message"
    $script:Warnings.Add($entry)
    Write-Host "  WARN  $Message" -ForegroundColor Yellow
    if ($Strict) {
        $script:Failures.Add("[$CheckName] STRICT: $Message")
    }
}

function Pass {
    param([string]$CheckName, [string]$Message)
    $entry = "[$CheckName] PASS: $Message"
    $script:Passed.Add($entry)
    Write-Host "  PASS  $Message" -ForegroundColor Green
}

function Write-CheckHeader {
    param([string]$Name)
    $script:ChecksRun++
    Write-Host ""
    Write-Host "CHECK $($script:ChecksRun): $Name" -ForegroundColor Cyan
}

function Get-WorkbookItems {
    param([object[]]$Items)

    foreach ($item in @($Items)) {
        $item
        if ($item.content -and $item.content.items) {
            Get-WorkbookItems -Items $item.content.items
        }
    }
}

# ── Duration parser for Sentinel YAML queryFrequency / queryPeriod ─────────────
# Returns duration in minutes; $null if the string cannot be parsed.
# Accepts Sentinel simplified format (1h, 6h, 1d, 7d, 30m) and ISO 8601 (PT1H, P1D, P7D).
function ConvertFrom-SentinelDuration {
    param([string]$Duration)
    if (-not $Duration) { return $null }
    $d = $Duration.Trim()
    if ($d -match '^(\d+)m$')  { return [int]$Matches[1] }
    if ($d -match '^(\d+)h$')  { return [int]$Matches[1] * 60 }
    if ($d -match '^(\d+)d$')  { return [int]$Matches[1] * 1440 }
    if ($d -match '^(\d+)w$')  { return [int]$Matches[1] * 10080 }
    if ($d -match '^PT(\d+)M$') { return [int]$Matches[1] }
    if ($d -match '^PT(\d+)H$') { return [int]$Matches[1] * 60 }
    if ($d -match '^P(\d+)D$')  { return [int]$Matches[1] * 1440 }
    if ($d -match '^P(\d+)W$')  { return [int]$Matches[1] * 10080 }
    return $null
}

# Extract the KQL query block from a Sentinel YAML file content string.
# Returns the raw indented query text; empty string if the 'query: |' key is not found.
# Block starts on a 'query: |' line and ends at the first non-indented line (same logic
# used inline in Check 7 — kept as a shared helper to avoid duplication).
function Get-YamlQueryBlock {
    param([string]$Content)
    $sb = [System.Text.StringBuilder]::new()
    $inBlock = $false
    foreach ($ql in ($Content -split "`r?`n")) {
        if ($ql -match '^query:\s*\|') { $inBlock = $true; continue }
        if ($inBlock) {
            if ($ql.Length -gt 0 -and $ql[0] -notmatch '\s') { $inBlock = $false }
            else { [void]$sb.AppendLine($ql) }
        }
    }
    return $sb.ToString()
}

# Playbook directory name map keyed by canonical PB-* shortcodes used in YAML Response: lines.
# Update this map when new playbooks are added.
$script:KnownPlaybookMap = @{
    'PB-NOTIFY-01' = 'AIGS-Notify-001-TeamsAlert'
    'PB-AUTO-01'   = 'AIGS-Auto-001-RestoreDiagnostics'
}

# Maximum allowed queryPeriod for Scheduled rules (duplicate-control threshold: 14 days).
$script:MaxQueryPeriodMinutes = 14 * 1440  # 20160

# ──────────────────────────────────────────────────────────────
# Validate solution root exists
# ──────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "==================================================" -ForegroundColor White
Write-Host " Microsoft Sentinel - AI Governance Solution" -ForegroundColor White
Write-Host " Source Validator" -ForegroundColor White
Write-Host "==================================================" -ForegroundColor White
Write-Host " Solution root : $SolutionRoot"
Write-Host " Repository    : $RepoRoot"
Write-Host " Strict mode   : $($Strict.IsPresent)"
Write-Host ""

if (-not (Test-Path $SolutionRoot)) {
    Write-Host "Solution root does not exist: $SolutionRoot" -ForegroundColor Red
    Write-Host "The solution directory has not been scaffolded yet. Validator cannot run." -ForegroundColor Yellow
    exit 1
}

# ──────────────────────────────────────────────────────────────
# CHECK 1: JSON Parse Validity
# ──────────────────────────────────────────────────────────────
Write-CheckHeader "JSON Parse Validity"

$jsonFiles = Get-ChildItem -Recurse -Path $SolutionRoot -Filter "*.json" -File |
    Where-Object { $_.FullName -notlike "*\Package\*" }

if ($jsonFiles.Count -eq 0) {
    Warn "JSON" "No JSON files found in solution directory — solution not yet scaffolded"
} else {
    foreach ($f in $jsonFiles) {
        $rel = $f.FullName.Replace($RepoRoot, '').TrimStart('\','/')
        try {
            $content = Get-Content $f.FullName -Raw -ErrorAction Stop
            $null = $content | ConvertFrom-Json -ErrorAction Stop
            Pass "JSON" "$rel"
        } catch {
            Fail "JSON" "$rel — $($_.Exception.Message)"
        }
    }
}

# ──────────────────────────────────────────────────────────────
# CHECK 2: YAML Required Fields (Text-Safe)
# ──────────────────────────────────────────────────────────────
Write-CheckHeader "YAML Required Fields (Analytic Rules and Hunting Queries)"

# Required fields for Microsoft Sentinel YAML analytic rule / hunting query manifests
$requiredRuleFields = @('id:', 'name:', 'description:', 'kind:', 'severity:', 'requiredDataConnectors:', 'query:')
$requiredHuntFields  = @('id:', 'name:', 'description:', 'query:')

$ruleDir  = Join-Path $SolutionRoot "Analytic Rules"
$huntDir  = Join-Path $SolutionRoot "Hunting Queries"
$parserDir = Join-Path $SolutionRoot "Parsers"

function Test-YamlFields {
    param([string]$FilePath, [string[]]$RequiredFields, [string]$Label)
    $rel = $FilePath.Replace($RepoRoot, '').TrimStart('\','/')
    $content = Get-Content $FilePath -Raw -ErrorAction SilentlyContinue
    if (-not $content) {
        Fail "YAML" "$rel — file is empty or unreadable"
        return
    }
    $missing = @()
    foreach ($field in $RequiredFields) {
        # Text-safe check: field key must appear at the start of a line (top-level key)
        if ($content -notmatch "(?m)^\s*$([regex]::Escape($field))") {
            $missing += $field
        }
    }
    if ($missing.Count -gt 0) {
        Fail "YAML" "$rel — missing required field(s): $($missing -join ', ')"
    } else {
        Pass "YAML" "$rel"
    }
}

if (Test-Path $ruleDir) {
    $ruleFiles = Get-ChildItem -Path $ruleDir -Filter "*.yaml" -File -Recurse
    if ($ruleFiles.Count -eq 0) {
        Warn "YAML" "Analytic Rules directory exists but contains no .yaml files"
    } else {
        foreach ($f in $ruleFiles) { Test-YamlFields $f.FullName $requiredRuleFields "AnalyticRule" }
    }
} else {
    Warn "YAML" "Analytic Rules directory not yet present ($ruleDir)"
}

if (Test-Path $huntDir) {
    $huntFiles = Get-ChildItem -Path $huntDir -Filter "*.yaml" -File -Recurse
    if ($huntFiles.Count -eq 0) {
        Warn "YAML" "Hunting Queries directory exists but contains no .yaml files"
    } else {
        foreach ($f in $huntFiles) { Test-YamlFields $f.FullName $requiredHuntFields "HuntingQuery" }
    }
} else {
    Warn "YAML" "Hunting Queries directory not yet present ($huntDir)"
}

if (Test-Path $parserDir) {
    $parserFiles = Get-ChildItem -Path $parserDir -Filter "*.yaml" -File -Recurse
    foreach ($f in $parserFiles) {
        Test-YamlFields $f.FullName @('id:', 'name:', 'query:') "Parser"
    }
}

# ── Enhanced checks for Scheduled analytic rules ──────────────────────────────
# Requires queryFrequency and queryPeriod; validates duration syntax and magnitude;
# validates playbook cross-references in Response: lines.
if (Test-Path $ruleDir) {
    $ruleFilesEnhanced = Get-ChildItem -Path $ruleDir -Filter "*.yaml" -File -Recurse
    foreach ($f in $ruleFilesEnhanced) {
        $rel     = $f.FullName.Replace($RepoRoot, '').TrimStart('\','/')
        $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }

        # Only apply Scheduled-specific checks to rules declared as Scheduled
        if ($content -notmatch '(?m)^\s*kind\s*:\s*Scheduled') { continue }

        # Require queryFrequency and queryPeriod for Scheduled rules
        foreach ($freqField in @('queryFrequency', 'queryPeriod')) {
            if ($content -notmatch "(?m)^\s*${freqField}\s*:") {
                Fail "YAML" "$rel — Scheduled rule missing required field: ${freqField}"
            }
        }

        # Parse and validate queryFrequency
        $freqMatch = [regex]::Match($content, '(?m)^\s*queryFrequency\s*:\s*(\S+)')
        if ($freqMatch.Success) {
            $freqRaw = $freqMatch.Groups[1].Value.Trim("'`"")
            $freqMin = ConvertFrom-SentinelDuration $freqRaw
            if ($null -eq $freqMin) {
                Fail "YAML" "$rel — queryFrequency '$freqRaw' is not a parseable duration (expected e.g. 1h, 6h, 1d, PT1H, P1D)"
            } else {
                Pass "YAML" "$rel — queryFrequency '$freqRaw' is valid ($freqMin min)"
                # E4: Warn if a CopilotActivity-sourced rule runs shorter than 1h.
                # Purview UAL (CopilotActivity's source) has a 15-60 min ingestion delay;
                # sub-hourly runs miss events and can produce duplicate detections.
                if ($freqMin -lt 60) {
                    $qbForFreq = Get-YamlQueryBlock $content
                    $qbNoComments = ($qbForFreq -split "`r?`n" |
                        Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
                    if ($qbNoComments -match '\bCopilotActivity\b') {
                        Warn "YAML" "$rel — CopilotActivity rule has queryFrequency '$freqRaw' ($freqMin min) shorter than 1h; Purview UAL ingestion delay is 15-60 min — raise to at least 1h to avoid missed or duplicate detections"
                    }
                }
            }
        }

        # Parse and validate queryPeriod; assert <= duplicate-control threshold
        $periodMatch = [regex]::Match($content, '(?m)^\s*queryPeriod\s*:\s*(\S+)')
        if ($periodMatch.Success) {
            $periodRaw = $periodMatch.Groups[1].Value.Trim("'`"")
            $periodMin = ConvertFrom-SentinelDuration $periodRaw
            if ($null -eq $periodMin) {
                Fail "YAML" "$rel — queryPeriod '$periodRaw' is not a parseable duration (expected e.g. 1h, 1d, 7d, P1D)"
            } elseif ($periodMin -gt $script:MaxQueryPeriodMinutes) {
                Fail "YAML" "$rel — queryPeriod '$periodRaw' ($periodMin min) exceeds duplicate-control threshold of 14 days ($($script:MaxQueryPeriodMinutes) min)"
            } else {
                Pass "YAML" "$rel — queryPeriod '$periodRaw' is valid and within 14-day threshold"
            }
        }

        # Validate playbook cross-references in Response: lines of the description block
        $playbookRefs = [regex]::Matches($content, 'PB-[A-Z]+-\d+')
        $playbookBaseDir = Join-Path $SolutionRoot "Playbooks"
        foreach ($pbRef in ($playbookRefs | Select-Object -ExpandProperty Value -Unique)) {
            if ($script:KnownPlaybookMap.ContainsKey($pbRef)) {
                $expectedDir = Join-Path $playbookBaseDir $script:KnownPlaybookMap[$pbRef]
                if (Test-Path $expectedDir) {
                    Pass "YAML" "$rel — playbook reference $pbRef resolves to $($script:KnownPlaybookMap[$pbRef])"
                } else {
                    Fail "YAML" "$rel — playbook reference $pbRef maps to directory '$($script:KnownPlaybookMap[$pbRef])' which does not exist at $expectedDir"
                }
            } else {
                Warn "YAML" "$rel — playbook reference $pbRef is not in the known playbook map; verify it resolves to an actual Playbooks/ subdirectory"
            }
        }
    }
}

# ──────────────────────────────────────────────────────────────
# CHECK 3: Unique GUIDs
# ──────────────────────────────────────────────────────────────
Write-CheckHeader "Unique GUIDs Across Solution Content"

# Collect GUIDs from all YAML and JSON files (excluding Package/ which is generated)
$guidPattern = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'

$guidMap = @{}  # guid -> list of file paths where it appears as an 'id:' value

$contentFiles = Get-ChildItem -Recurse -Path $SolutionRoot -Include "*.yaml","*.json" -File |
    Where-Object { $_.FullName -notlike "*\Package\*" }

foreach ($f in $contentFiles) {
    $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $content) { continue }

    # Extract GUIDs that appear on lines that look like YAML id fields or JSON "id" properties
    # Patterns: "id: <guid>", '"id": "<guid>"'
    $idMatches = [regex]::Matches($content, '(?i)(?:^\s*id\s*:\s*|"id"\s*:\s*")(' + $guidPattern + ')', [System.Text.RegularExpressions.RegexOptions]::Multiline)
    foreach ($m in $idMatches) {
        $guid = $m.Groups[1].Value.ToLower()
        if (-not $guidMap.ContainsKey($guid)) { $guidMap[$guid] = [System.Collections.Generic.List[string]]::new() }
        $rel = $f.FullName.Replace($RepoRoot, '').TrimStart('\','/')
        if ($guidMap[$guid] -notcontains $rel) { $guidMap[$guid].Add($rel) }
    }
}

if ($guidMap.Count -eq 0) {
    Warn "GUID" "No content GUIDs found — solution content not yet authored"
} else {
    $duplicates = $guidMap.GetEnumerator() | Where-Object { $_.Value.Count -gt 1 }
    if ($duplicates) {
        foreach ($dup in $duplicates) {
            Fail "GUID" "Duplicate GUID $($dup.Key) appears in: $($dup.Value -join '; ')"
        }
    } else {
        Pass "GUID" "$($guidMap.Count) content GUID(s) are all unique"
    }
}

# Check guids.json registry if present; store at script scope for Check 6 (searchKey lookup)
# and Check 13 (roadmap path existence gate).
$guidsRegistryFile = Join-Path $SolutionRoot "guids.json"
$script:GuidsRegistry = $null
if (Test-Path $guidsRegistryFile) {
    try {
        $script:GuidsRegistry = Get-Content $guidsRegistryFile -Raw | ConvertFrom-Json -ErrorAction Stop
        Pass "GUID" "guids.json registry is valid JSON"
    } catch {
        Fail "GUID" "guids.json registry fails to parse: $($_.Exception.Message)"
    }
} else {
    Warn "GUID" "guids.json not yet present — create before Gate 1a"
}

# ──────────────────────────────────────────────────────────────
# CHECK 4: Forbidden Hard-Coded Azure IDs
# ──────────────────────────────────────────────────────────────
Write-CheckHeader "No Forbidden Hard-Coded Azure IDs"

# Hard-coded identifiers that must never appear in deployable artifacts.
# Scope: ARM templates, YAML rule/hunt files, KQL files, and PowerShell scripts.
# Documentation (.md), watchlist data (CSV/JSON with sample values), and registry
# files (guids.json, SolutionMetadata.json, api-versions.md) are excluded — they
# may legitimately reference environment names for documentation or sample purposes.
#
# Real subscription IDs are identified by being non-nil (not 00000000-...) GUIDs
# after /subscriptions/. Nil GUIDs in sample data are flagged by Check 9 instead.

$forbiddenPatterns = @(
    # Non-nil subscription GUID in resource path — nil GUIDs (00000000-...) are sample data, excluded below
    @{ Pattern = '/subscriptions/(?!00000000-)[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'; Label = 'hard-coded real subscription resource path' },
    # Literal tenantId with a non-nil GUID
    @{ Pattern = '"tenantId"\s*:\s*"(?!00000000-)[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"'; Label = 'hard-coded tenantId field' }
)

foreach ($value in $ForbiddenValue) {
    if (-not [string]::IsNullOrWhiteSpace($value)) {
        $forbiddenPatterns += @{
            Pattern = [regex]::Escape($value)
            Label   = 'environment-specific value supplied through -ForbiddenValue'
        }
    }
}

# Only check deployable artifact types — not documentation or data files
$deployableExtensions = @('*.json', '*.yaml', '*.yml', '*.kql', '*.ps1')
# Files explicitly allowed even among deployable types
$allowedInFiles = @('guids.json', 'SolutionMetadata.json', 'api-versions.md')
# Watchlist JSON/CSV are sample data files, not deployable templates
$watchlistPathFragment = 'Data\Watchlists'

# Watchlist files (both legacy Data\Watchlists and canonical solution-root Watchlists)
# contain example/template data with placeholder subscription IDs — exclude both paths.
$deployableFiles = Get-ChildItem -Recurse -Path $SolutionRoot -Include $deployableExtensions -File |
    Where-Object {
        $_.FullName -notlike "*\Package\*" -and
        $_.FullName -notlike "*\Watchlists\*"
    }

# Also scan scripts directory — must not contain session-local identifiers.
# Exclude this validator script itself (it contains detection strings intentionally).
if (Test-Path $script:ScriptsDir) {
    $scriptFiles = Get-ChildItem -Path $script:ScriptsDir -Include $deployableExtensions -File -Recurse |
        Where-Object { $_.FullName -ne $script:ValidatorScriptPath }
    $deployableFiles = @($deployableFiles) + @($scriptFiles)
}

foreach ($f in $deployableFiles) {
    $rel = $f.FullName.Replace($RepoRoot, '').TrimStart('\','/')
    $fileName = [System.IO.Path]::GetFileName($f.FullName)
    if ($allowedInFiles -contains $fileName) { continue }

    $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $content) { continue }

    foreach ($fp in $forbiddenPatterns) {
        if ($content -match $fp.Pattern) {
            $matchObj = [regex]::Match($content, $fp.Pattern)
            $context = ""
            if ($matchObj.Success) {
                $start = [Math]::Max(0, $matchObj.Index - 30)
                $len   = [Math]::Min(80, $content.Length - $start)
                $context = $content.Substring($start, $len) -replace "`r`n|`n", " "
            }
            # Allow if the match is inside an ARM parameters() indirection expression
            if ($context -match "\[parameters\(|parameters\s*\(") { continue }
            Fail "HARDCODE" "$rel — $($fp.Label). Context: ...${context}..."
        }
    }
}

$hardcodeFailures = $script:Failures | Where-Object { $_ -like "*[HARDCODE]*" }
if (-not $hardcodeFailures) {
    Pass "HARDCODE" "No forbidden hard-coded Azure IDs found in deployable source files"
}

# ──────────────────────────────────────────────────────────────
# CHECK 5: Package/ Artifact Set (generated artifacts only; no foreign source files)
# ──────────────────────────────────────────────────────────────
# Official Azure-Sentinel solutions commit generated Package outputs alongside source.
# createSolutionV3.ps1 does NOT generate a README; git-tracking of Package/ is normal.
# Assert: expected core artifacts present; no foreign source file types introduced by hand.
Write-CheckHeader "Package/ Artifact Set (generated artifacts; no foreign source files)"

$packageDir = Join-Path $SolutionRoot "Package"
$pkgExpectedArtifacts = @('mainTemplate.json', 'createUiDefinition.json')
$pkgForeignExtensions  = @('.yaml', '.yml', '.ps1', '.md', '.txt', '.bicep')

if (Test-Path $packageDir) {
    foreach ($artifact in $pkgExpectedArtifacts) {
        if (Test-Path (Join-Path $packageDir $artifact)) {
            Pass "PACKAGE" "Package/$artifact — present"
        } else {
            Fail "PACKAGE" "Package/$artifact — missing expected generated artifact"
        }
    }
    $pkgAllFiles = Get-ChildItem -Path $packageDir -File -Recurse
    $pkgForeign  = @($pkgAllFiles | Where-Object { $_.Extension -in $pkgForeignExtensions })
    if ($pkgForeign.Count -gt 0) {
        foreach ($f in $pkgForeign) {
            $frel = $f.FullName.Replace($SolutionRoot, '').TrimStart('\','/')
            Fail "PACKAGE" "$frel — foreign source file type '$($f.Extension)' in Package/; only .json and .zip are generated by createSolutionV3.ps1"
        }
    } else {
        Pass "PACKAGE" "Package/ — $($pkgAllFiles.Count) file(s) present, no foreign source types"
    }
} else {
    Pass "PACKAGE" "Package/ directory absent — correctly absent until generated"
}

# ──────────────────────────────────────────────────────────────
# CHECK 6: Watchlist Full ARM Shape, ItemKey, CSV Columns, rawContent, No Active Baseline Rows
# ──────────────────────────────────────────────────────────────
Write-CheckHeader "Watchlist Validation (ARM Shape / ItemKey / CSV Columns / rawContent / No Active Rows)"

# Helper: validate a CSV file for ItemKey/Status columns and no Active rows
function Test-WatchlistCsv {
    param([string]$CsvPath, [string]$Label)
    $allLines = @()
    try {
        $allLines = Get-Content $CsvPath -ErrorAction Stop
    } catch {
        Fail "WATCHLIST" "$Label — cannot read CSV: $($_.Exception.Message)"; return
    }
    if ($allLines.Count -eq 0) { Fail "WATCHLIST" "$Label — file is empty"; return }
    $headerRow  = $allLines[0]
    $headerCols = $headerRow -split ','
    if ($headerCols -notcontains 'ItemKey') {
        Fail "WATCHLIST" "$Label — CSV header missing required 'ItemKey' column. Header: $headerRow"
    } else { Pass "WATCHLIST" "$Label — CSV has 'ItemKey' column" }
    if ($headerCols -notcontains 'Status') {
        Fail "WATCHLIST" "$Label — CSV header missing required 'Status' column. Header: $headerRow"
    } else { Pass "WATCHLIST" "$Label — CSV has 'Status' column" }
    if ($headerCols -contains 'Status') {
        $statusColIdx = [Array]::IndexOf($headerCols, 'Status')
        $activeRows = @()
        for ($i = 1; $i -lt $allLines.Count; $i++) {
            $rowCols = $allLines[$i] -split ','
            if ($rowCols.Count -gt $statusColIdx -and $rowCols[$statusColIdx].Trim().Trim('"') -ieq 'Active') {
                $activeRows += "row $($i+1): $($allLines[$i].Substring(0,[Math]::Min(80,$allLines[$i].Length)))"
            }
        }
        if ($activeRows.Count -gt 0) {
            Fail "WATCHLIST" "$Label — $($activeRows.Count) Status=Active row(s) in shipped baseline (use Template or Deprecated). First: $($activeRows[0])"
        } else { Pass "WATCHLIST" "$Label — no Status=Active rows in baseline (correct)" }
    }
}

# ── CANONICAL: solution-root Watchlists\<name>\<name>.json  (ARM template format) ──
$rootWlDir = Join-Path $SolutionRoot "Watchlists"
if (-not (Test-Path $rootWlDir)) {
    Warn "WATCHLIST" "solution-root Watchlists/ directory not yet present — watchlists not yet authored"
} else {
    $wlSubdirs = Get-ChildItem -Path $rootWlDir -Directory
    if ($wlSubdirs.Count -eq 0) {
        Warn "WATCHLIST" "solution-root Watchlists/ directory has no watchlist subdirectories"
    } else {
        foreach ($wlSub in $wlSubdirs) {
            $wlName  = $wlSub.Name
            $jsonPath = Join-Path $wlSub.FullName "$wlName.json"
            $csvPath  = Join-Path $wlSub.FullName "$wlName.csv"

            if (-not (Test-Path $jsonPath)) {
                Fail "WATCHLIST" "Watchlists/$wlName — missing ARM template JSON ($wlName.json)"
            } else {
                $arm = $null
                try { $arm = Get-Content $jsonPath -Raw | ConvertFrom-Json -ErrorAction Stop }
                catch { Fail "WATCHLIST" "Watchlists/$wlName/$wlName.json — JSON parse error: $($_.Exception.Message)"; continue }

                # Full ARM template shape: $schema, contentVersion, resources
                $missingTop = @()
                foreach ($tf in @('$schema', 'contentVersion', 'resources')) {
                    if ($arm.PSObject.Properties.Name -notcontains $tf) { $missingTop += $tf }
                }
                if ($missingTop.Count -gt 0) {
                    Fail "WATCHLIST" "Watchlists/$wlName/$wlName.json — missing ARM top-level field(s): $($missingTop -join ', ')"
                } else {
                    Pass "WATCHLIST" "Watchlists/$wlName/$wlName.json — ARM top-level shape valid"
                }

                # Find the Watchlist resource in the resources array
                $wlRes = $arm.resources | Where-Object { $_.type -like "*Watchlists*" } | Select-Object -First 1
                if (-not $wlRes) {
                    Fail "WATCHLIST" "Watchlists/$wlName/$wlName.json — no Watchlist resource found in resources array (expected type *Watchlists*)"
                } elseif (-not $wlRes.properties) {
                    Fail "WATCHLIST" "Watchlists/$wlName/$wlName.json — Watchlist resource has no 'properties' object"
                } else {
                    $props = $wlRes.properties
                    $missingProps = @()
                    foreach ($pf in @('displayName', 'itemsSearchKey', 'contentType', 'rawContent')) {
                        if ($props.PSObject.Properties.Name -notcontains $pf) { $missingProps += $pf }
                    }
                    if ($missingProps.Count -gt 0) {
                        Fail "WATCHLIST" "Watchlists/$wlName/$wlName.json — Watchlist properties missing field(s): $($missingProps -join ', ')"
                    } else {
                        Pass "WATCHLIST" "Watchlists/$wlName/$wlName.json — Watchlist properties complete"
                    }

                    # itemsSearchKey must match the value declared in guids.json.
                    # Default is "ItemKey" when the watchlist is not registered.
                    # Watchlists with a non-standard searchKey (e.g. AIGS_ApprovedCopilotPlugins
                    # declares "PluginId") are validated against the registry entry, not a
                    # hardcoded default. The registry is checked in both the main body and
                    # the _roadmap section to handle watchlists not yet promoted.
                    if ($props.PSObject.Properties.Name -contains 'itemsSearchKey') {
                        $expectedSearchKey = 'ItemKey'  # default when not registered
                        if ($script:GuidsRegistry) {
                            $wlRegEntry = $null
                            if ($script:GuidsRegistry.watchlists -and
                                $script:GuidsRegistry.watchlists.PSObject.Properties.Name -contains $wlName) {
                                $wlRegEntry = $script:GuidsRegistry.watchlists.$wlName
                            } elseif ($script:GuidsRegistry._roadmap -and
                                      $script:GuidsRegistry._roadmap.watchlists -and
                                      $script:GuidsRegistry._roadmap.watchlists.PSObject.Properties.Name -contains $wlName) {
                                $wlRegEntry = $script:GuidsRegistry._roadmap.watchlists.$wlName
                            }
                            if ($wlRegEntry -and $wlRegEntry.PSObject.Properties.Name -contains 'searchKey') {
                                $expectedSearchKey = $wlRegEntry.searchKey
                            }
                        }
                        if ($props.itemsSearchKey -cne $expectedSearchKey) {
                            Fail "WATCHLIST" "Watchlists/$wlName/$wlName.json — itemsSearchKey is '$($props.itemsSearchKey)'; expected '$expectedSearchKey' (per guids.json registry)"
                        } else {
                            Pass "WATCHLIST" "Watchlists/$wlName/$wlName.json — itemsSearchKey is '$expectedSearchKey'"
                        }
                    }

                    # rawContent must match the companion CSV (after newline normalization)
                    if (Test-Path $csvPath) {
                        $csvNorm  = ((Get-Content $csvPath -Raw) -replace "`r`n","`n").TrimEnd("`n")
                        $jsonNorm = ($props.rawContent -replace "`r`n","`n").TrimEnd("`n")
                        if ($csvNorm -ceq $jsonNorm) {
                            Pass "WATCHLIST" "Watchlists/$wlName/$wlName.json — rawContent matches companion CSV"
                        } else {
                            Fail "WATCHLIST" "Watchlists/$wlName/$wlName.json — rawContent ($(($jsonNorm -split '`n').Count) lines) does not match companion CSV ($(($csvNorm -split '`n').Count) lines)"
                        }
                    } else {
                        Fail "WATCHLIST" "Watchlists/$wlName — missing companion CSV ($wlName.csv)"
                    }
                }
            }

            # Validate companion CSV
            if (Test-Path $csvPath) {
                Test-WatchlistCsv $csvPath "Watchlists/$wlName/$wlName.csv"
            } else {
                Fail "WATCHLIST" "Watchlists/$wlName — missing companion CSV ($wlName.csv)"
            }
        }
    }
}

# ── LEGACY: Data\Watchlists\ (should be migrated; flag as structural failure) ──
$legacyWlDir = Join-Path $SolutionRoot "Data\Watchlists"
if (Test-Path $legacyWlDir) {
    $legacyCsvs  = (Get-ChildItem -Path $legacyWlDir -Filter "*.csv"  -File).Count
    $legacyJsons = (Get-ChildItem -Path $legacyWlDir -Filter "*.json" -File).Count
    if ($legacyCsvs -gt 0 -or $legacyJsons -gt 0) {
        Fail "WATCHLIST" "Data\Watchlists\ contains $legacyCsvs CSV(s) and $legacyJsons JSON(s) — legacy location. Watchlist content must be in solution-root Watchlists\<name>\<name>.json/.csv format. Remove Data\Watchlists\ content once migration is complete."
    }
}

# ──────────────────────────────────────────────────────────────
# CHECK 7: KQL ASIM Declaration in Analytic Rule YAML
# ──────────────────────────────────────────────────────────────
Write-CheckHeader "KQL ASIM Declaration in Analytic Rules"

# Every analytic rule .yaml file's query field must declare its ASIM status
# Accepted patterns (from binding implementation contract):
#   // ASIM: imAuditEvent — native
#   // ASIM: imAuthentication — native
#   // ASIM: N/A — <reason>
#   // ASIM: custom — <parser name>
$asimPattern = '(?m)//\s*ASIM\s*:'

if (Test-Path $ruleDir) {
    $ruleFilesForAsim = Get-ChildItem -Path $ruleDir -Filter "*.yaml" -File -Recurse
    if ($ruleFilesForAsim.Count -eq 0) {
        Warn "ASIM" "No analytic rule YAML files found yet"
    } else {
        foreach ($f in $ruleFilesForAsim) {
            $rel = $f.FullName.Replace($RepoRoot, '').TrimStart('\','/')
            $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
            if (-not $content) {
                Fail "ASIM" "$rel — file is empty or unreadable"
                continue
            }
            if ($content -notmatch $asimPattern) {
                Fail "ASIM" "$rel — missing required ASIM declaration comment (e.g., '// ASIM: imAuditEvent — native' or '// ASIM: N/A — <reason>')"
            } else {
                # Validate the declaration is not trivially wrong
                $asimMatch = [regex]::Match($content, $asimPattern + '\s*(.+)')
                $declaration = $asimMatch.Groups[1].Value.Trim()

                # Forbidden: claiming PurviewAuditLogs-based ASIM (table does not exist)
                if ($content -match 'PurviewAuditLogs') {
                    Fail "ASIM" "$rel — references PurviewAuditLogs which is not a real Sentinel table. Use OfficeActivity | where OfficeWorkload == `"Purview`""
                }
                # Forbidden: claiming custom AIGS_* parsers are ASIM
                # Refined: check only the KQL query block (not description prose), and exclude
                # watchlist string references (_GetWatchlist("AIGS_...")) which are legitimate.
                # Only warn when _Im_* is called as an actual KQL function AND AIGS_* appears as
                # a non-watchlist-reference symbol, both outside of KQL comment lines.
                $queryBlock = ''
                $inQueryBlock = $false
                foreach ($ql in ($content -split "`r?`n")) {
                    if ($ql -match '^query:\s*\|') { $inQueryBlock = $true; continue }
                    if ($inQueryBlock) {
                        if ($ql.Length -gt 0 -and $ql[0] -notmatch '\s') { $inQueryBlock = $false }
                        else { $queryBlock += $ql + "`n" }
                    }
                }
                # Strip watchlist name string args so _GetWatchlist("AIGS_...") does not count as a parser call
                $kqlForCheck = $queryBlock -replace '_GetWatchlist\s*\(\s*"[^"]*"\s*\)', '_GetWatchlist("")'
                # Strip KQL comment lines (// ...) from consideration
                $kqlNoComments = ($kqlForCheck -split "`r?`n" | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
                if (($kqlNoComments -cmatch '\b_Im_\w+') -and ($kqlNoComments -match '\bAIGS_\w+')) {
                    Warn "ASIM" "$rel — query directly calls both _Im_* (ASIM) and AIGS_* (custom parser) functions; custom parsers are not ASIM."
                }
                Pass "ASIM" "$rel — ASIM declaration: $declaration"
            }
        }
    }
} else {
    Warn "ASIM" "Analytic Rules directory not yet present — skipping ASIM check"
}

# ──────────────────────────────────────────────────────────────
# CHECK 8: Documentation Presence
# ──────────────────────────────────────────────────────────────
Write-CheckHeader "Documentation Presence"

# Required documentation files for the solution
$requiredDocs = @(
    @{ Path = Join-Path $SolutionRoot "PREREQUISITES.md";  Label = "PREREQUISITES.md" },
    @{ Path = Join-Path $SolutionRoot "ReleaseNotes.md";   Label = "ReleaseNotes.md" },
    @{ Path = Join-Path $SolutionRoot "CHANGELOG.md";      Label = "CHANGELOG.md" },
    @{ Path = (Join-Path $RepoRoot "README.md");           Label = "Root README.md" }
)

foreach ($doc in $requiredDocs) {
    if (Test-Path $doc.Path) {
        # Check it is non-empty
        $size = (Get-Item $doc.Path).Length
        if ($size -lt 100) {
            Warn "DOCS" "$($doc.Label) — exists but is very small ($size bytes); may be a stub"
        } else {
            Pass "DOCS" "$($doc.Label) — present ($size bytes)"
        }
    } else {
        Fail "DOCS" "$($doc.Label) — missing at expected path: $($doc.Path)"
    }
}

# Each playbook directory must have a readme.md
$playbookBaseDir = Join-Path $SolutionRoot "Playbooks"
if (Test-Path $playbookBaseDir) {
    $playbookDirs = Get-ChildItem -Path $playbookBaseDir -Directory
    if ($playbookDirs.Count -eq 0) {
        Warn "DOCS" "Playbooks directory exists but contains no playbook subdirectories"
    } else {
        foreach ($pd in $playbookDirs) {
            $readmeCandidate = Get-ChildItem -Path $pd.FullName -Filter "readme.md" -File | Select-Object -First 1
            if (-not $readmeCandidate) {
                $readmeCandidate = Get-ChildItem -Path $pd.FullName -Filter "README.md" -File | Select-Object -First 1
            }
            if (-not $readmeCandidate) {
                Fail "DOCS" "Playbook $($pd.Name) — missing readme.md"
            } else {
                $size = $readmeCandidate.Length
                if ($size -lt 100) {
                    Warn "DOCS" "Playbook $($pd.Name)/readme.md — exists but is very small ($size bytes); may be a stub"
                } else {
                    Pass "DOCS" "Playbook $($pd.Name)/readme.md — present ($size bytes)"
                }
            }
        }
    }
} else {
    Warn "DOCS" "Playbooks directory not yet present"
}

# ──────────────────────────────────────────────────────────────
# CHECK 9: No Unexpanded Placeholders (PENDING, PLACEHOLDER, nil GUIDs)
# ──────────────────────────────────────────────────────────────
Write-CheckHeader "No Unexpanded Placeholders / PENDING Tokens"

# Placeholder patterns that must not appear in committed source files.
#
# Rules for each pattern:
#  - {{ALL_CAPS}} : unfilled template variables. Sentinel runtime substitution uses
#    camelCase/PascalCase {{ColumnName}} syntax — those are legitimate and must NOT be flagged.
#    Only ALL_CAPS_UNDERSCORE variants indicate unfilled template variables.
#  - [PENDING_*]  : URL/path placeholders that have not been filled in (e.g. [PENDING_REMOTE_URL]).
#    These appear in JSON manifests before the repo URL is known; they must be resolved before
#    any customer-facing publication of the solution.
#  - <YOUR-*>, <REPLACE-ME> : conventional placeholder annotations.
#  - nil GUID (all-zero): used as a placeholder subscription or resource ID that was never replaced.
#  - bare PLACEHOLDER: explicit unfilled slot.
#  - TODO: FILL: developer-left note indicating an unfilled value.
#
# Allowed exception: documentation examples that are unmistakably generic (e.g. values with
#  the suffix '-EXAMPLE' or 'xxxxxxxx') are in watchlist data files which are excluded below.
$placeholderPatterns = @(
    @{ Pattern = '\{\{[A-Z][A-Z0-9_]+\}\}';      Label = '{{PLACEHOLDER}} style template variable (ALL_CAPS — not a Sentinel runtime substitution)'; CaseSensitive = $true  },
    @{ Pattern = '\[PENDING[_A-Za-z0-9]*\]';      Label = '[PENDING_...] unfilled URL/path placeholder — must be resolved before publication';         CaseSensitive = $false },
    @{ Pattern = '<YOUR-[A-Za-z_-]+>';             Label = '<YOUR-VALUE> style placeholder';                                                             CaseSensitive = $false },
    @{ Pattern = '<REPLACE[_-]?ME>';               Label = '<REPLACE-ME> placeholder';                                                                   CaseSensitive = $false },
    @{ Pattern = 'TODO\s*:\s*FILL';                Label = 'TODO: FILL placeholder comment';                                                             CaseSensitive = $false },
    @{ Pattern = '(?<![_a-zA-Z])PLACEHOLDER(?![_a-zA-Z])'; Label = 'bare PLACEHOLDER text (outside a word boundary)';                                  CaseSensitive = $true  },
    @{ Pattern = '00000000-0000-0000-0000-000000000000'; Label = 'all-zero nil GUID placeholder';                                                       CaseSensitive = $false }
)

# Exclusions: this script itself (contains detection strings), and CHANGELOG (may explain conventions).
$excludeFromPlaceholderCheck = @(
    [System.IO.Path]::GetFileName($MyInvocation.MyCommand.Path),
    "CHANGELOG.md"
)

# Scan solution source AND scripts directory.
# Exclude: Package/ (generated), Data\Watchlists\ (sample data — customers fill these),
#          and the validator script itself.
$allPlaceholderTargets = @(
    Get-ChildItem -Recurse -Path $SolutionRoot -Include "*.json","*.yaml","*.yml","*.kql","*.ps1" -File |
        Where-Object {
            $_.FullName -notlike "*\Package\*" -and
            $_.FullName -notlike "*\Data\Watchlists\*" -and
            ($excludeFromPlaceholderCheck -notcontains $_.Name)
        }
)
if (Test-Path $script:ScriptsDir) {
    $allPlaceholderTargets += Get-ChildItem -Path $script:ScriptsDir -Include "*.ps1","*.json","*.yaml" -File -Recurse |
        Where-Object {
            $_.FullName -ne $script:ValidatorScriptPath -and
            ($excludeFromPlaceholderCheck -notcontains $_.Name)
        }
}

$placeholderFound = $false
foreach ($f in $allPlaceholderTargets) {
    $rel     = $f.FullName.Replace($RepoRoot, '').TrimStart('\','/')
    $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $content) { continue }

    # Strip _comment fields from JSON content before placeholder scan —
    # _comment fields are explanatory metadata and may describe placeholders by design.
    $scanContent = $content -replace '"_comment"\s*:\s*"[^"]*"', '"_comment": ""'

    foreach ($pp in $placeholderPatterns) {
        $isMatch = if ($pp.CaseSensitive) {
            $scanContent -cmatch $pp.Pattern
        } else {
            $scanContent -match $pp.Pattern
        }
        if ($isMatch) {
            $matchObj = if ($pp.CaseSensitive) {
                [regex]::Match($scanContent, $pp.Pattern)
            } else {
                [regex]::Match($scanContent, $pp.Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            }
            $start   = [Math]::Max(0, $matchObj.Index - 20)
            $len     = [Math]::Min(60, $scanContent.Length - $start)
            $context = $scanContent.Substring($start, $len) -replace "`r`n|`n", " "
            Fail "PLACEHOLDER" "$rel — $($pp.Label). Context: ...${context}..."
            $placeholderFound = $true
        }
    }
}

if (-not $placeholderFound) {
    Pass "PLACEHOLDER" "No unexpanded placeholders or PENDING tokens found in source files"
}

# ──────────────────────────────────────────────────────────────
# CHECK 10: Data Directory Structure
# ──────────────────────────────────────────────────────────────
Write-CheckHeader "Data Directory Structure (manifest JSON only; Watchlists at solution root)"

$dataDir = Join-Path $SolutionRoot "Data"

if (-not (Test-Path $dataDir)) {
    Warn "DATA-STRUCTURE" "Data/ directory not yet present"
} else {
    # Assert Data/ contains only JSON files (no subdirectories or non-JSON content).
    # Watchlist content must live at solution-root Watchlists/, not Data/Watchlists/.
    $dataItems = Get-ChildItem -Path $dataDir
    $nonJsonInData = $dataItems | Where-Object { -not $_.PSIsContainer -and $_.Extension -ne '.json' }
    $subdirs       = $dataItems | Where-Object { $_.PSIsContainer }

    if ($nonJsonInData.Count -gt 0) {
        foreach ($nj in $nonJsonInData) {
            Fail "DATA-STRUCTURE" "Data/$($nj.Name) — Data/ must contain only JSON manifest files; non-JSON file found"
        }
    }

    if ($subdirs.Count -gt 0) {
        foreach ($sd in $subdirs) {
            if ($sd.Name -ieq 'Watchlists') {
                Fail "DATA-STRUCTURE" "Data/Watchlists/ subdirectory found — watchlist content must be at solution-root Watchlists/ (not Data/Watchlists/). Move all watchlist CSV and JSON files up one level."
            } else {
                Fail "DATA-STRUCTURE" "Data/$($sd.Name)/ subdirectory found — Data/ must contain only JSON manifest files; no subdirectories are allowed"
            }
        }
    }

    if ($nonJsonInData.Count -eq 0 -and $subdirs.Count -eq 0) {
        $jsonCount = ($dataItems | Where-Object { $_.Extension -eq '.json' }).Count
        Pass "DATA-STRUCTURE" "Data/ contains $jsonCount JSON manifest file(s) and no disallowed content"
    }
}

# Assert Watchlists directory exists at solution root (not just under Data/)
$rootWatchlistDir = Join-Path $SolutionRoot "Watchlists"
if (Test-Path $rootWatchlistDir) {
    $wlFileCount = (Get-ChildItem -Path $rootWatchlistDir -File -Recurse).Count
    $wlDirCount  = (Get-ChildItem -Path $rootWatchlistDir -Directory).Count
    Pass "DATA-STRUCTURE" "solution-root Watchlists/ exists — $wlDirCount watchlist subdirectory(ies), $wlFileCount file(s) total"
} else {
    Warn "DATA-STRUCTURE" "solution-root Watchlists/ directory not yet present — required by createSolutionV3.ps1 and manifest paths"
}

# ──────────────────────────────────────────────────────────────
# CHECK 11: Manifest Path Completeness, Workbook Presence, Version, TemplateSpec
# ──────────────────────────────────────────────────────────────
Write-CheckHeader "Manifest Completeness (paths exist / Workbooks listed / Version / TemplateSpec)"

$contentManifestPath = Join-Path $SolutionRoot "Data\Solution_AIGovernance.json"

if (-not (Test-Path $contentManifestPath)) {
    Warn "MANIFEST" "Data\Solution_AIGovernance.json not yet present — skipping manifest checks"
} else {
    $manifest = $null
    try {
        $manifest = Get-Content $contentManifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Fail "MANIFEST" "Data\Solution_AIGovernance.json — JSON parse error: $($_.Exception.Message)"
    }

    if ($manifest) {
        # 1. Version must be a pure numeric three-part semver (X.Y.Z) — no pre-release suffix.
        $version = $manifest.Version
        if (-not $version) {
            Fail "MANIFEST" "Data\Solution_AIGovernance.json — missing 'Version' field"
        } elseif ($version -notmatch '^\d+\.\d+\.\d+$') {
            Fail "MANIFEST" "Data\Solution_AIGovernance.json — Version '$version' is not a pure numeric three-part version (X.Y.Z). Pre-release suffixes like '-preview.1' are not accepted by createSolutionV3.ps1."
        } else {
            Pass "MANIFEST" "Version '$version' is a valid numeric three-part version"
        }

        # 2. TemplateSpec must be a boolean. This solution requires true because V3
        # workbook content templates resolve identity/version through WorkbooksMetadata.json.
        if ($manifest.PSObject.Properties.Name -notcontains 'TemplateSpec') {
            Fail "MANIFEST" "Data\Solution_AIGovernance.json — missing 'TemplateSpec' field (must be a boolean)"
        } elseif ($manifest.TemplateSpec -isnot [bool]) {
            Fail "MANIFEST" "Data\Solution_AIGovernance.json — TemplateSpec is '$($manifest.TemplateSpec)' (type: $($manifest.TemplateSpec.GetType().Name)); must be a JSON boolean (true or false), not a string"
        } else {
            Pass "MANIFEST" "TemplateSpec is a boolean ($($manifest.TemplateSpec.ToString().ToLower()))"
        }

        if (($manifest.Workbooks | Measure-Object).Count -gt 0) {
            $workbookMetadataPath = Join-Path $RepoRoot "Workbooks\WorkbooksMetadata.json"
            if (-not $manifest.TemplateSpec) {
                Fail "MANIFEST" "Data\Solution_AIGovernance.json — TemplateSpec must be true when packaging V3 workbook content templates"
            } elseif (-not (Test-Path $workbookMetadataPath)) {
                Fail "MANIFEST" "Workbooks\WorkbooksMetadata.json — required for V3 workbook identity and version resolution"
            } else {
                try {
                    $workbookMetadata = @(Get-Content $workbookMetadataPath -Raw | ConvertFrom-Json -ErrorAction Stop)
                    foreach ($workbookPath in $manifest.Workbooks) {
                        $workbookFileName = Split-Path $workbookPath -Leaf
                        $metadataEntry = @($workbookMetadata | Where-Object {
                            $_.templateRelativePath -eq $workbookFileName
                        })
                        if ($metadataEntry.Count -ne 1) {
                            Fail "MANIFEST" "Workbooks\WorkbooksMetadata.json — expected exactly one metadata entry for '$workbookFileName'; found $($metadataEntry.Count)"
                            continue
                        }
                        $missingWorkbookMetadata = @()
                        foreach ($field in @('workbookKey', 'version', 'title', 'description', 'templateRelativePath', 'provider')) {
                            if ([string]::IsNullOrWhiteSpace([string]$metadataEntry[0].$field)) {
                                $missingWorkbookMetadata += $field
                            }
                        }
                        if ($missingWorkbookMetadata.Count -gt 0) {
                            Fail "MANIFEST" "Workbooks\WorkbooksMetadata.json — '$workbookFileName' entry has empty required field(s): $($missingWorkbookMetadata -join ', ')"
                        } else {
                            Pass "MANIFEST" "Workbooks\WorkbooksMetadata.json — '$workbookFileName' identity/version metadata is complete"
                        }

                        $workbookFullPath = Join-Path $SolutionRoot $workbookPath
                        if (Test-Path $workbookFullPath) {
                            try {
                                $workbook = Get-Content $workbookFullPath -Raw | ConvertFrom-Json -ErrorAction Stop
                                $queryItems = @(Get-WorkbookItems -Items $workbook.items | Where-Object {
                                    $_.type -eq 3 -and $_.content.query
                                })

                                $escapedUnicodeQueries = @($queryItems | Where-Object {
                                    $_.content.query -match '\\(?:U[0-9A-Fa-f]{8}|u[0-9A-Fa-f]{4})'
                                })
                                if ($escapedUnicodeQueries.Count -gt 0) {
                                    Fail "WORKBOOK" "'$workbookFileName' contains KQL Unicode escape literals in item(s): $($escapedUnicodeQueries.name -join ', ')"
                                } else {
                                    Pass "WORKBOOK" "'$workbookFileName' KQL contains no unsupported Unicode escape literals"
                                }

                                $invalidTileItems = @($queryItems | Where-Object {
                                    if ($_.content.visualization -ne 'tiles') {
                                        return $false
                                    }
                                    $titleColumn = [string]$_.content.tileSettings.titleContent.columnMatch
                                    $valueColumn = [string]$_.content.tileSettings.leftContent.columnMatch
                                    [string]::IsNullOrWhiteSpace($titleColumn) -or
                                        [string]::IsNullOrWhiteSpace($valueColumn) -or
                                        $titleColumn.Contains('*') -or
                                        $valueColumn.Contains('*')
                                })
                                if ($invalidTileItems.Count -gt 0) {
                                    Fail "WORKBOOK" "'$workbookFileName' tile item(s) require exact title and value column matches: $($invalidTileItems.name -join ', ')"
                                } else {
                                    Pass "WORKBOOK" "'$workbookFileName' tile items use exact title and value column matches"
                                }
                            } catch {
                                Fail "WORKBOOK" "'$workbookFileName' — JSON parse or quality validation error: $($_.Exception.Message)"
                            }
                        }
                    }
                } catch {
                    Fail "MANIFEST" "Workbooks\WorkbooksMetadata.json — JSON parse error: $($_.Exception.Message)"
                }
            }
        }

        # 3. Workbooks section must exist and list at least one workbook
        if ($manifest.PSObject.Properties.Name -notcontains 'Workbooks' -or
            ($manifest.Workbooks | Measure-Object).Count -eq 0) {
            Fail "MANIFEST" "Data\Solution_AIGovernance.json — 'Workbooks' section is missing or empty. The solution workbook (Workbooks/AIGovernanceSolution.json) must be listed."
        } else {
            $wbCount = ($manifest.Workbooks | Measure-Object).Count
            Pass "MANIFEST" "Workbooks section lists $wbCount workbook(s)"
        }

        # 4. Every listed path must resolve to an existing file (relative to solution root)
        $contentSections = @('Playbooks', 'Analytic Rules', 'Hunting Queries', 'Watchlists', 'Workbooks', 'Parsers', 'Data Connectors', 'Workbooks')
        $checkedPaths = @{}
        foreach ($section in $contentSections) {
            $sectionProp = $manifest.PSObject.Properties | Where-Object { $_.Name -eq $section }
            if (-not $sectionProp) { continue }
            $paths = $sectionProp.Value
            if (-not $paths) { continue }
            foreach ($relativePath in $paths) {
                if ($checkedPaths.ContainsKey($relativePath)) { continue }
                $checkedPaths[$relativePath] = $true
                $fullPath = Join-Path $SolutionRoot $relativePath
                if (Test-Path $fullPath) {
                    Pass "MANIFEST" "[$section] $relativePath — file exists"
                } else {
                    Fail "MANIFEST" "[$section] $relativePath — listed in manifest but file not found at: $fullPath"
                }
            }
        }
    }
}

# ──────────────────────────────────────────────────────────────
# CHECK 12: Package Validation (only when -PackagePath is supplied)
# ──────────────────────────────────────────────────────────────
Write-CheckHeader "Package Validation (mainTemplate.json + createUiDefinition.json)"

if (-not $PackagePath) {
    Pass "PACKAGE-CONTENT" "Skipped — no -PackagePath supplied (run with -PackagePath to validate a generated package)"
} else {
    $resolvedPackagePath = [System.IO.Path]::GetFullPath($PackagePath)
    if (-not (Test-Path $resolvedPackagePath)) {
        Fail "PACKAGE-CONTENT" "PackagePath '$resolvedPackagePath' does not exist"
    } else {
        # mainTemplate.json — required ARM template
        $mainTemplatePath = Join-Path $resolvedPackagePath "mainTemplate.json"
        if (-not (Test-Path $mainTemplatePath)) {
            Fail "PACKAGE-CONTENT" "mainTemplate.json not found in package path $resolvedPackagePath"
        } else {
            try {
                $mainTemplate = Get-Content $mainTemplatePath -Raw | ConvertFrom-Json -ErrorAction Stop
                $missingMainFields = @()
                foreach ($mf in @('$schema', 'contentVersion', 'resources')) {
                    if ($mainTemplate.PSObject.Properties.Name -notcontains $mf) {
                        $missingMainFields += $mf
                    }
                }
                if ($missingMainFields.Count -gt 0) {
                    Fail "PACKAGE-CONTENT" "mainTemplate.json — missing expected ARM template field(s): $($missingMainFields -join ', ')"
                } else {
                    $resourceCount = ($mainTemplate.resources | Measure-Object).Count
                    Pass "PACKAGE-CONTENT" "mainTemplate.json — valid ARM template with $resourceCount resource(s)"

                    $emptyIdentityVariables = @(
                        $mainTemplate.variables.PSObject.Properties |
                            Where-Object {
                                $_.Name -match '(?i)(ContentId|Version)\d+$' -and
                                [string]::IsNullOrWhiteSpace([string]$_.Value)
                            }
                    )
                    if ($emptyIdentityVariables.Count -gt 0) {
                        Fail "PACKAGE-CONTENT" "mainTemplate.json — generated content identity/version variable(s) are empty: $($emptyIdentityVariables.Name -join ', ')"
                    } else {
                        Pass "PACKAGE-CONTENT" "mainTemplate.json — generated content identity/version variables are populated"
                    }
                }
            } catch {
                Fail "PACKAGE-CONTENT" "mainTemplate.json — JSON parse error: $($_.Exception.Message)"
            }
        }

        # createUiDefinition.json — required UI definition
        $uiDefPath = Join-Path $resolvedPackagePath "createUiDefinition.json"
        if (-not (Test-Path $uiDefPath)) {
            Fail "PACKAGE-CONTENT" "createUiDefinition.json not found in package path $resolvedPackagePath"
        } else {
            try {
                $uiDef = Get-Content $uiDefPath -Raw | ConvertFrom-Json -ErrorAction Stop
                $missingUiFields = @()
                foreach ($uf in @('$schema', 'handler', 'version', 'parameters')) {
                    if ($uiDef.PSObject.Properties.Name -notcontains $uf) {
                        $missingUiFields += $uf
                    }
                }
                if ($missingUiFields.Count -gt 0) {
                    Fail "PACKAGE-CONTENT" "createUiDefinition.json — missing expected UI definition field(s): $($missingUiFields -join ', ')"
                } else {
                    Pass "PACKAGE-CONTENT" "createUiDefinition.json — valid UI definition (handler: $($uiDef.handler), version: $($uiDef.version))"
                }
            } catch {
                Fail "PACKAGE-CONTENT" "createUiDefinition.json — JSON parse error: $($_.Exception.Message)"
            }
        }
    }
}

# ──────────────────────────────────────────────────────────────
# CHECK 13: guids.json Roadmap — No Files Deployed at Roadmap Paths
# ──────────────────────────────────────────────────────────────
Write-CheckHeader "guids.json Roadmap — No Files Deployed at Roadmap Paths"

# Every artifact registered under _roadmap in guids.json is planned but not yet authored.
# If a file exists at a roadmap-registered path the guids.json entry must be promoted to
# the main body (status: "resolved") before the solution is packaged.
# A deployed file at a roadmap path would be picked up by createSolutionV3.ps1 without a
# resolved GUID registry entry, producing a packaging error or a silent GUID gap.
if (-not $script:GuidsRegistry) {
    Pass "ROADMAP" "guids.json not present or not parsed — roadmap path check skipped"
} elseif ($script:GuidsRegistry.PSObject.Properties.Name -notcontains '_roadmap') {
    Pass "ROADMAP" "guids.json has no _roadmap section — no roadmap paths to check"
} else {
    $roadmapPaths = [System.Collections.Generic.List[hashtable]]::new()

    foreach ($rmSection in @('analyticRules', 'huntingQueries')) {
        $rmObj = $script:GuidsRegistry._roadmap.$rmSection
        if (-not $rmObj) { continue }
        foreach ($rmEntry in $rmObj.PSObject.Properties) {
            $rmVal = $rmEntry.Value
            if ($rmVal -and ($rmVal.PSObject.Properties.Name -contains 'file')) {
                $roadmapPaths.Add(@{ EntryName = $rmEntry.Name; RelPath = [string]$rmVal.file })
            }
        }
    }

    if ($script:GuidsRegistry._roadmap.PSObject.Properties.Name -contains 'watchlists') {
        foreach ($rmEntry in $script:GuidsRegistry._roadmap.watchlists.PSObject.Properties) {
            $rmVal = $rmEntry.Value
            foreach ($fk in @('metadataFile', 'dataFile')) {
                if ($rmVal -and ($rmVal.PSObject.Properties.Name -contains $fk)) {
                    $roadmapPaths.Add(@{ EntryName = $rmEntry.Name; RelPath = [string]$rmVal.$fk })
                }
            }
        }
    }

    if ($roadmapPaths.Count -eq 0) {
        Pass "ROADMAP" "guids.json _roadmap section has no registered file paths"
    } else {
        $roadmapViolations = 0
        foreach ($rp in $roadmapPaths) {
            if ([string]::IsNullOrWhiteSpace($rp.RelPath)) { continue }
            $fullRmPath = Join-Path $SolutionRoot $rp.RelPath
            if (Test-Path $fullRmPath) {
                $roadmapViolations++
                Fail "ROADMAP" "_roadmap entry '$($rp.EntryName)' has file deployed at '$($rp.RelPath)' — promote guids.json entry to main body and set status: 'resolved' before packaging"
            }
        }
        if ($roadmapViolations -eq 0) {
            Pass "ROADMAP" "$($roadmapPaths.Count) roadmap path(s) checked — none deployed prematurely"
        }
    }
}

# ──────────────────────────────────────────────────────────────
# CHECK 14: Module C CopilotActivity — Forbidden Columns and Connector ID
# ──────────────────────────────────────────────────────────────
Write-CheckHeader "Module C CopilotActivity — Forbidden Columns and Connector ID"

# E6: Fail when a YAML rule or hunt whose KQL query block references CopilotActivity also uses
# column names that are unverified or invented.  These names must not appear as KQL tokens in
# the non-comment portion of the query block.
#
# Connector: if requiredDataConnectors lists a connectorId in a CopilotActivity rule it must
# equal the verified ID 'MicrosoftCopilot'.  Omitting connectorId entirely is allowed.
#
# False-positive mitigations (applied in order):
#   1. Only inspect the parsed KQL query block (YAML description/prose is excluded).
#   2. Strip KQL comment lines (// ...).
#   3. Strip _GetWatchlist-based materialize blocks (line-scanner: accumulate from
#      'let X = materialize(' through the matching ');'; discard if block contains _GetWatchlist).
#      This prevents watchlist column names (e.g. PluginId in AIGS_ApprovedCopilotPlugins)
#      from triggering false positives.
#   4. Strip remaining _GetWatchlist("...") quoted argument strings.
#   5. Only activate the forbidden-column and connector checks when CopilotActivity appears
#      as a KQL token in the cleaned text.

$copilotForbiddenColumns = @(
    'Operation',
    'AccessedResources',
    'UserKey',
    'ItemName',
    'PluginId',
    'PluginVersion',
    'PolicyName',
    'ContentFilterStatus'
)

# Collect all analytic rule and hunting query YAML files.
$allYamlFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
if ($ruleDir -and (Test-Path $ruleDir)) {
    Get-ChildItem -Path $ruleDir -Filter "*.yaml" -File -Recurse | ForEach-Object { $allYamlFiles.Add($_) }
}
if ($huntDir -and (Test-Path $huntDir)) {
    Get-ChildItem -Path $huntDir -Filter "*.yaml" -File -Recurse | ForEach-Object { $allYamlFiles.Add($_) }
}

if ($allYamlFiles.Count -eq 0) {
    Pass "MODULE-C" "No analytic rule or hunting query YAML files present — Module C checks not triggered"
} else {
    $moduleCFilesChecked = 0

    foreach ($f in $allYamlFiles) {
        $rel     = $f.FullName.Replace($RepoRoot, '').TrimStart('\','/')
        $content = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }

        # ── Step 1: Extract the KQL query block ──────────────────────────────
        $rawQueryBlock = Get-YamlQueryBlock $content

        # ── Step 2: Strip KQL comment lines ──────────────────────────────────
        $qLines = $rawQueryBlock -split "`r?`n" | Where-Object { $_ -notmatch '^\s*//' }

        # ── Step 3: Strip _GetWatchlist materialize blocks ───────────────────
        # Accumulate from 'let X = materialize(' through ');'; if the accumulated block
        # contains _GetWatchlist, discard it (watchlist context, not table column context).
        $filteredLines = [System.Collections.Generic.List[string]]::new()
        $accumBlock    = [System.Collections.Generic.List[string]]::new()
        $inAccum       = $false
        foreach ($ql in $qLines) {
            if (-not $inAccum -and $ql -match '\blet\s+\w+\s*=\s*materialize\s*\(') {
                $inAccum = $true
                $accumBlock.Clear()
                $accumBlock.Add($ql)
            } elseif ($inAccum) {
                $accumBlock.Add($ql)
                if ($ql -match '^\s*\)\s*;') {
                    $inAccum = $false
                    $blockText = $accumBlock -join "`n"
                    if ($blockText -match '\b_GetWatchlist\b') {
                        $filteredLines.Add('// [watchlist-let-stripped]')
                    } else {
                        foreach ($bl in $accumBlock) { $filteredLines.Add($bl) }
                    }
                    $accumBlock.Clear()
                }
            } else {
                $filteredLines.Add($ql)
            }
        }
        # Flush any unclosed accumulation as-is
        foreach ($bl in $accumBlock) { $filteredLines.Add($bl) }

        # ── Step 4: Strip remaining _GetWatchlist("...") quoted arguments ────
        $kqlForScan = ($filteredLines -join "`n") -replace '_GetWatchlist\s*\(\s*"[^"]*"\s*\)', '_GetWatchlist("")'

        # ── Step 5: Gate — only activate Module C checks when CopilotActivity is present ──
        if ($kqlForScan -notmatch '\bCopilotActivity\b') { continue }

        $moduleCFilesChecked++

        # ── E6a: Forbidden column names ──────────────────────────────────────
        foreach ($col in $copilotForbiddenColumns) {
            if ($kqlForScan -match "\b$([regex]::Escape($col))\b") {
                Fail "MODULE-C" "$rel — unverified CopilotActivity column '$col' in KQL query block; use only Trinity-verified columns or obtain a new schema verification"
            }
        }

        # ── E6b: LLMEventData dynamic field / index access ───────────────────
        if ($kqlForScan -match '\bLLMEventData\s*[\.\[]') {
            Fail "MODULE-C" "$rel — unverified CopilotActivity dynamic column 'LLMEventData' access in KQL query block; column is not schema-verified"
        }

        # ── E6c: Custom parser reference ─────────────────────────────────────
        if ($kqlForScan -match '\bAIGS_CopilotActivity_Normalized\b') {
            Fail "MODULE-C" "$rel — references custom parser 'AIGS_CopilotActivity_Normalized' in KQL query block; Module C rules must query CopilotActivity directly (no custom parser per x3nc0n directive 2026-07-23)"
        }

        # ── Connector ID check ────────────────────────────────────────────────
        # requiredDataConnectors.connectorId may be omitted; if present, must be 'MicrosoftCopilot'.
        $connectorMatches = [regex]::Matches($content, '(?m)^\s*-?\s*connectorId\s*:\s*(\S+)')
        $connectorFound = $false
        foreach ($cm in $connectorMatches) {
            $connId = $cm.Groups[1].Value.Trim("'`"")
            $connectorFound = $true
            if ($connId -cne 'MicrosoftCopilot') {
                Fail "MODULE-C" "$rel — CopilotActivity rule declares connectorId '$connId'; required value is 'MicrosoftCopilot' (verified connector ID)"
            } else {
                Pass "MODULE-C" "$rel — connectorId 'MicrosoftCopilot' is correct"
            }
        }
        if (-not $connectorFound) {
            Pass "MODULE-C" "$rel — no connectorId declared (permitted; connector prerequisite may be documented in PREREQUISITES.md)"
        }
    }

    if ($moduleCFilesChecked -eq 0) {
        Pass "MODULE-C" "No CopilotActivity references in query blocks — Module C forbidden-column and connector checks not triggered"
    }
}

# ──────────────────────────────────────────────────────────────
# SUMMARY
# ──────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "==================================================" -ForegroundColor White
Write-Host " Validation Summary" -ForegroundColor White
Write-Host "==================================================" -ForegroundColor White
Write-Host " Checks run : $($script:ChecksRun)"
Write-Host " Passed     : $($script:Passed.Count)" -ForegroundColor Green
Write-Host " Warnings   : $($script:Warnings.Count)" -ForegroundColor Yellow
Write-Host " Failures   : $($script:Failures.Count)" -ForegroundColor $(if ($script:Failures.Count -gt 0) { 'Red' } else { 'Green' })

if ($script:Failures.Count -gt 0) {
    Write-Host ""
    Write-Host "FAILURES:" -ForegroundColor Red
    foreach ($f in $script:Failures) {
        Write-Host "  $f" -ForegroundColor Red
    }
}

if ($script:Warnings.Count -gt 0 -and $script:Failures.Count -eq 0) {
    Write-Host ""
    Write-Host "WARNINGS (non-blocking):" -ForegroundColor Yellow
    foreach ($w in $script:Warnings) {
        Write-Host "  $w" -ForegroundColor Yellow
    }
}

Write-Host ""
if ($script:Failures.Count -gt 0) {
    Write-Host "RESULT: FAILED — $($script:Failures.Count) failure(s). Fix all failures before merging." -ForegroundColor Red
    exit 1
} elseif ($Strict -and $script:Warnings.Count -gt 0) {
    Write-Host "RESULT: FAILED (strict mode) — $($script:Warnings.Count) warning(s) treated as failures." -ForegroundColor Red
    exit 1
} else {
    Write-Host "RESULT: PASSED" -ForegroundColor Green
    if ($script:Warnings.Count -gt 0) {
        Write-Host "         $($script:Warnings.Count) warning(s) noted — solution is partially scaffolded; complete scaffolding before Gate 1a." -ForegroundColor Yellow
    }
    exit 0
}
