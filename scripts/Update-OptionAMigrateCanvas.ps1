# Regenerates option-a-migrate-live.canvas.tsx from newest migrate-* summary + queues.
$ErrorActionPreference = 'Continue'
$Root = 'C:\Users\My PC\Downloads\shared-apex-static'
$CanvasPath = 'C:\Users\My PC\.cursor\projects\c-Users-My-PC-Downloads-shared-apex-static\canvases\option-a-migrate-live.canvas.tsx'
$SpikeDone = 50
$BatchSizes = @{ 1 = 19; 2 = 93; 3 = 49; 4 = 97; 5 = 95; 6 = 64 }
$TotalStatic = 467

function Get-StatusFromAfter([string]$After) {
  if ([string]::IsNullOrWhiteSpace($After)) { return 'active' }
  if ($After -match '200/kv') { return 'ok' }
  if ($After -match '^200/') { return 'partial' }
  return 'error'
}

function Get-ActiveMigrateRun {
  $dirs = @(Get-ChildItem -LiteralPath (Join-Path $Root 'reports') -Directory -Filter 'migrate-20*' |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'migrate-summary.csv') } |
    Sort-Object LastWriteTime -Descending)
  foreach ($d in $dirs) {
    # skip known completed small batches that aren't the live option-A wave when a newer running one exists
    $csvPath = Join-Path $d.FullName 'migrate-summary.csv'
    $rows = @(Import-Csv -LiteralPath $csvPath | Where-Object { $_.Domain })
    if ($rows.Count -eq 0) { continue }
    $ageMin = ((Get-Date) - $d.LastWriteTime).TotalMinutes
    $proc = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -match 'Invoke-MigrateSitesToFleet' } |
      Select-Object -First 1
    $running = $null -ne $proc
    # Prefer newest dir that is either being written recently or matches running process count expectation
    $stamp = $d.Name -replace '^migrate-',''
    return [pscustomobject]@{
      Dir = $d.FullName
      Stamp = $stamp
      Rows = $rows
      LastWrite = $d.LastWriteTime
      CsvWrite = (Get-Item -LiteralPath $csvPath).LastWriteTime
      Running = $running
      ProcStart = if ($proc) {
        try { (Get-Process -Id $proc.ProcessId -ErrorAction Stop).StartTime } catch { $null }
      } else { $null }
      SitesCsvHint = if ($proc -and $proc.CommandLine -match 'remain-batch(\d)\.csv') { [int]$Matches[1] } else { $null }
    }
  }
  return $null
}

$run = Get-ActiveMigrateRun
$activeBatch = 2
if ($run -and $run.SitesCsvHint) { $activeBatch = [int]$run.SitesCsvHint }
elseif ($run) {
  # Heuristic: match row count / first domain against remain CSVs
  for ($b = 2; $b -le 6; $b++) {
    $q = @(Import-Csv -LiteralPath (Join-Path $Root "reports\option-a-queues\remain-batch$b.csv") | Select-Object -ExpandProperty Domain)
    if ($run.Rows.Count -le $q.Count -and $q -contains $run.Rows[0].Domain) { $activeBatch = $b; break }
  }
}

$runTotal = $BatchSizes[$activeBatch]
$siteRows = @()
$idx = 0
foreach ($r in @($run.Rows)) {
  $idx++
  $after = [string]$r.After
  $st = Get-StatusFromAfter $after
  $siteRows += [ordered]@{
    Idx = $idx
    Domain = [string]$r.Domain
    Status = $st
    KvCopied = [string]$r.KvCopied
    After = $after
    Warm = [string]$r.Warm
    CopyFails = 0
    Error = [string]$r.Error
  }
}

$done = $siteRows.Count
$ok = @($siteRows | Where-Object { $_.Status -eq 'ok' }).Count
$partial = @($siteRows | Where-Object { $_.Status -eq 'partial' }).Count
$fail = @($siteRows | Where-Object { $_.Status -eq 'error' }).Count
$runStatus = if ($run -and $run.Running) { 'running' }
  elseif ($run -and $done -ge $runTotal) { 'succeeded' }
  elseif ($run) { 'idle' }
  else { 'idle' }

$currentDomain = ''
$currentIdx = $done
if ($runStatus -eq 'running') {
  # Infer in-progress domain: next in remain queue after last completed
  $queue = @(Import-Csv -LiteralPath (Join-Path $Root "reports\option-a-queues\remain-batch$activeBatch.csv") | Select-Object -ExpandProperty Domain)
  if ($done -lt $queue.Count) {
    $currentIdx = $done + 1
    $currentDomain = $queue[$done]
  } elseif ($done -gt 0) {
    $currentIdx = $done
    $currentDomain = $siteRows[$done - 1].Domain
  }
} elseif ($done -gt 0) {
  $currentDomain = $siteRows[$done - 1].Domain
}

$elapsedMin = 0.0
if ($run -and $run.ProcStart) {
  $elapsedMin = [math]::Round(((Get-Date) - $run.ProcStart).TotalMinutes, 1)
} elseif ($run -and $run.Stamp -match '^(\d{8})-(\d{6})$') {
  try {
    $started = [datetime]::ParseExact($run.Stamp, 'yyyyMMdd-HHmmss', $null)
    $elapsedMin = [math]::Round(((Get-Date) - $started).TotalMinutes, 1)
  } catch {}
}

$etaMin = $null
if ($runStatus -eq 'running' -and $done -ge 2 -and $elapsedMin -gt 0) {
  $rate = $done / $elapsedMin
  $left = $runTotal - $done
  if ($rate -gt 0 -and $left -gt 0) { $etaMin = [math]::Round($left / $rate, 1) }
}

# Batch meta
$batchMeta = @()
$migratedRemain = 0
$batchMeta += [ordered]@{ Batch = 1; Total = 19; Done = 19; Status = 'audited'; Note = 'Migrate + 33-check audit PASS 19/19' }
$migratedRemain += 19

for ($b = 2; $b -le 6; $b++) {
  $total = $BatchSizes[$b]
  if ($b -eq $activeBatch -and $run) {
    $st = if ($runStatus -eq 'running') { 'migrating' }
      elseif ($done -ge $total -and $fail -eq 0) { 'migrate_done' }
      elseif ($done -ge $total) { 'migrate_done' }
      else { 'queued' }
    $note = if ($st -eq 'migrating') { "Live $currentIdx/$total $currentDomain" } else { "$ok ok / $partial soft / $fail fail" }
    $batchMeta += [ordered]@{ Batch = $b; Total = $total; Done = [math]::Min($done, $total); Status = $st; Note = $note }
    $migratedRemain += [math]::Min($done, $total)
  } else {
    $batchMeta += [ordered]@{ Batch = $b; Total = $total; Done = 0; Status = 'queued'; Note = 'Waiting' }
  }
}

$fleetTotal = $SpikeDone + $migratedRemain
$remainTotal = ($BatchSizes.Values | Measure-Object -Sum).Sum
$optionALeft = $remainTotal - $migratedRemain
$updatedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss zzz')

$snap = [ordered]@{
  updatedAt = $updatedAt
  worker = 'fleet-static-worker'
  kv = 'HTML_FLEET'
  r2 = 'fleet-static-assets'
  runStamp = if ($run) { $run.Stamp } else { '' }
  totalStatic = $TotalStatic
  spikeDone = $SpikeDone
  fleetOnShared = $fleetTotal
  optionARemainTotal = $remainTotal
  optionAMigrated = $migratedRemain
  optionALeft = $optionALeft
  activeBatch = $activeBatch
  runStatus = $runStatus
  runDone = $done
  runTotal = $runTotal
  runOk = $ok
  runPartial = $partial
  runFail = $fail
  currentIdx = $currentIdx
  currentDomain = $currentDomain
  elapsedMin = $elapsedMin
  etaMin = $etaMin
  batches = $batchMeta
  sites = $siteRows
}

$json = ($snap | ConvertTo-Json -Depth 8 -Compress)

$tsx = @'
import {
  Callout,
  Card,
  CardBody,
  CardHeader,
  Divider,
  Grid,
  H1,
  H2,
  Pill,
  Row,
  Stack,
  Stat,
  Table,
  Text,
  UsageBar,
  useHostTheme,
} from "cursor/canvas";

type SiteRow = {
  Idx: number;
  Domain: string;
  Status: "ok" | "active" | "partial" | "error" | "pending";
  KvCopied: string;
  After: string;
  Warm: string;
  CopyFails: number;
  Error?: string;
};

type BatchRow = {
  Batch: number;
  Total: number;
  Done: number;
  Status: string;
  Note: string;
};

type Snapshot = {
  updatedAt: string;
  worker: string;
  kv: string;
  r2: string;
  runStamp: string;
  totalStatic: number;
  spikeDone: number;
  fleetOnShared: number;
  optionARemainTotal: number;
  optionAMigrated: number;
  optionALeft: number;
  activeBatch: number;
  runStatus: string;
  runDone: number;
  runTotal: number;
  runOk: number;
  runPartial: number;
  runFail: number;
  currentIdx: number;
  currentDomain: string;
  elapsedMin: number;
  etaMin: number | null;
  batches: BatchRow[];
  sites: SiteRow[];
};

const SNAPSHOT: Snapshot = __SNAPSHOT__;

function batchTone(status: string): "success" | "info" | "neutral" | "warning" | "danger" {
  switch (status) {
    case "audited":
    case "migrate_done":
      return "success";
    case "migrating":
      return "info";
    case "error":
      return "danger";
    default:
      return "neutral";
  }
}

function siteTone(status: SiteRow["Status"]): "success" | "info" | "neutral" | "warning" | "danger" {
  switch (status) {
    case "ok":
      return "success";
    case "active":
      return "info";
    case "partial":
      return "warning";
    case "error":
      return "danger";
    default:
      return "neutral";
  }
}

function siteLabel(status: SiteRow["Status"]): string {
  switch (status) {
    case "ok":
      return "OK KV";
    case "active":
      return "In progress";
    case "partial":
      return "Partial";
    case "error":
      return "Error";
    default:
      return "Queued";
  }
}

export default function OptionAMigrateLive() {
  const theme = useHostTheme();
  const s = SNAPSHOT;
  const runPct = s.runTotal > 0 ? Math.round((100 * s.runDone) / s.runTotal) : 0;
  const fleetPct = Math.round((100 * s.fleetOnShared) / s.totalStatic);
  const etaText =
    s.runStatus === "running" && s.etaMin != null
      ? `~${s.etaMin} min left`
      : s.runStatus === "running"
        ? "ETA warming up"
        : "—";

  const recent = [...s.sites].reverse().slice(0, 30);

  return (
    <Stack gap={20} style={{ padding: 20, maxWidth: 1100 }}>
      <Stack gap={6}>
        <Row gap={10} align="center" justify="space-between">
          <H1>Option A fleet migration</H1>
          <Pill tone={s.runStatus === "running" ? "info" : "neutral"} active={s.runStatus === "running"}>
            {s.runStatus === "running" ? "LIVE" : s.runStatus.toUpperCase()}
          </Pill>
        </Row>
        <Text tone="secondary" size="small">
          Worker {s.worker} · KV {s.kv} · R2 {s.r2} · run {s.runStamp || "—"} · refreshed {s.updatedAt}
        </Text>
      </Stack>

      <UsageBar
        total={s.totalStatic}
        topLeftLabel={`${fleetPct}% of Batch 1–7 static on shared fleet`}
        topRightLabel={`${s.fleetOnShared} / ${s.totalStatic} sites`}
        segments={[
          { id: "spike", value: s.spikeDone, color: "blue" },
          { id: "optionA", value: s.optionAMigrated, color: "green" },
        ]}
      />

      <Grid columns={4} gap={12}>
        <Stat value={String(s.fleetOnShared)} label="On fleet now" tone="success" />
        <Stat value={`${s.runDone}/${s.runTotal}`} label={`Batch ${s.activeBatch} done`} tone="info" />
        <Stat value={String(s.runOk)} label="This run OK (kv)" />
        <Stat value={etaText} label={`Elapsed ${s.elapsedMin} min`} />
      </Grid>

      {s.runStatus === "running" ? (
        <Callout
          tone="info"
          title={`Batch ${s.activeBatch}: ${s.currentIdx}/${s.runTotal} ${s.currentDomain}`}
        >
          {runPct}% of this wave complete · {s.runOk} clear 200/kv · {s.runPartial} soft · {s.runFail} hard fail
        </Callout>
      ) : null}

      <Card>
        <CardHeader trailing={<Text size="small" tone="secondary">Spike 50 already on fleet (not in remain queues)</Text>}>
          Wave status
        </CardHeader>
        <CardBody style={{ paddingTop: 0 }}>
          <Table
            headers={["Batch", "Progress", "Status", "Note"]}
            columnAlign={["left", "left", "left", "left"]}
            rows={s.batches.map((b) => [
              `Batch ${b.Batch}`,
              `${b.Done}/${b.Total}`,
              <Pill key={`p-${b.Batch}`} tone={batchTone(b.Status)} size="sm">
                {b.Status}
              </Pill>,
              b.Note,
            ])}
          />
        </CardBody>
      </Card>

      <Divider />

      <Stack gap={8}>
        <H2>Batch {s.activeBatch} recent sites</H2>
        <Text size="small" tone="secondary">
          Newest first · source {s.runStamp ? `migrate-${s.runStamp}/migrate-summary.csv` : "—"}
        </Text>
        <Table
          headers={["#", "Domain", "Status", "KV pages", "After", "Warm"]}
          columnAlign={["right", "left", "left", "right", "left", "right"]}
          rows={recent.map((r) => [
            String(r.Idx),
            r.Domain,
            <Pill key={r.Domain} tone={siteTone(r.Status)} size="sm">
              {siteLabel(r.Status)}
            </Pill>,
            r.KvCopied || "—",
            r.After || "—",
            r.Warm || "—",
          ])}
          rowTone={recent.map((r) =>
            r.Status === "error" ? "danger" : r.Status === "active" ? "info" : undefined,
          )}
        />
      </Stack>

      <Text size="small" tone="tertiary" style={{ color: theme.secondaryText }}>
        Option A queue: {s.optionAMigrated} migrated / {s.optionARemainTotal} remain · {s.optionALeft} left after
        current progress · audits run per batch after migrate · auto-refresh ~45s
      </Text>
    </Stack>
  );
}
'@

$tsx = $tsx.Replace('__SNAPSHOT__', $json)
Set-Content -Path $CanvasPath -Value $tsx -Encoding UTF8
Write-Output "UPDATED fleet=$fleetTotal batch=$activeBatch done=$done/$runTotal status=$runStatus current=$currentIdx $currentDomain eta=$etaMin"
