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
  Domain: string;
  Batch: string;
  SiteName: string;
  Status: "ok" | "active" | "pending" | "error" | "partial";
  KvCopied: string;
  After: string;
  Asset: string;
  Warm: string;
  Error: string;
};

const SNAPSHOT = {
  updatedAt: __UPDATED_AT__,
  runStamp: __RUN_STAMP__,
  currentIdx: __CURRENT_IDX__,
  currentDomain: __CURRENT_DOMAIN__,
  total: __TOTAL__,
  ok: __OK__,
  fail: __FAIL__,
  done: __DONE__,
  worker: __WORKER__,
  kv: __KV__,
  r2: __R2__,
  sites: __SITES_JSON__ as SiteRow[],
};

function statusTone(
  status: SiteRow["Status"],
): "success" | "info" | "neutral" | "danger" | "warning" {
  switch (status) {
    case "ok":
      return "success";
    case "active":
      return "info";
    case "error":
      return "danger";
    case "partial":
      return "warning";
    default:
      return "neutral";
  }
}

function statusLabel(status: SiteRow["Status"]): string {
  switch (status) {
    case "ok":
      return "OK - fleet KV";
    case "active":
      return "In progress";
    case "error":
      return "Error";
    case "partial":
      return "Partial";
    default:
      return "Queued";
  }
}

export default function FleetMigrate50() {
  const theme = useHostTheme();
  const pending = SNAPSHOT.sites.filter((s) => s.Status === "pending").length;
  const active = SNAPSHOT.sites.filter((s) => s.Status === "active").length;
  const pct = Math.round((SNAPSHOT.ok / SNAPSHOT.total) * 100);
  const topLeft = pct + "% verified on fleet";
  const topRight =
    SNAPSHOT.ok +
    " OK - " +
    active +
    " active - " +
    pending +
    " queued - " +
    SNAPSHOT.fail +
    " failed / " +
    SNAPSHOT.total;
  const verifiedLabel = SNAPSHOT.ok + "/" + SNAPSHOT.total;

  const tableRows = SNAPSHOT.sites.map((s) => [
    <Text key="n" weight="medium">
      {s.SiteName}
    </Text>,
    <Text key="d" style={{ color: theme.text.secondary, fontSize: 12 }}>
      {s.Domain}
    </Text>,
    <Pill key="st" tone={statusTone(s.Status)} size="sm">
      {statusLabel(s.Status)}
    </Pill>,
    <Text key="kv">{s.KvCopied || "-"}</Text>,
    <Text key="warm">{s.Warm || "-"}</Text>,
    <Text key="asset" style={{ fontSize: 12 }}>
      {s.Asset || "-"}
    </Text>,
  ]);

  return (
    <Stack gap={20} style={{ padding: 20 }}>
      <Stack gap={6}>
        <H1>Fleet migrate - 50-site spike</H1>
        <Text style={{ color: theme.text.secondary }}>
          Copy page HTML into shared KV, switch routes to {SNAPSHOT.worker},
          verify x-source:kv. Snapshot {SNAPSHOT.updatedAt} - run{" "}
          {SNAPSHOT.runStamp}
        </Text>
      </Stack>

      <UsageBar
        total={SNAPSHOT.total}
        topLeftLabel={topLeft}
        topRightLabel={topRight}
        segments={[
          { id: "ok", value: SNAPSHOT.ok, color: "green" },
          { id: "active", value: active, color: "blue" },
          { id: "fail", value: SNAPSHOT.fail, color: "orange" },
        ]}
      />

      <Grid columns={4} gap={12}>
        <Stat value={verifiedLabel} label="Verified OK" tone="success" />
        <Stat value={String(SNAPSHOT.currentIdx)} label="Current index" />
        <Stat
          value={String(SNAPSHOT.fail)}
          label="Failures"
          tone={SNAPSHOT.fail > 0 ? "danger" : "neutral"}
        />
        <Stat value={String(pending)} label="Still queued" />
      </Grid>

      {active > 0 ? (
        <Callout tone="info" title="Currently migrating">
          [{SNAPSHOT.currentIdx}/{SNAPSHOT.total}] {SNAPSHOT.currentDomain}
        </Callout>
      ) : SNAPSHOT.ok >= SNAPSHOT.total ? (
        <Callout tone="success" title="Spike complete">
          All {SNAPSHOT.total} sites verified with fleet KV responses.
        </Callout>
      ) : null}

      <Card>
        <CardHeader
          trailing={
            <Pill size="sm">{SNAPSHOT.worker}</Pill>
          }
        >
          Shared fleet infra
        </CardHeader>
        <CardBody>
          <Row gap={16} wrap>
            <Text style={{ fontSize: 13 }}>KV - {SNAPSHOT.kv}</Text>
            <Text style={{ fontSize: 13 }}>R2 - {SNAPSHOT.r2}</Text>
          </Row>
        </CardBody>
      </Card>

      <Divider />

      <Stack gap={8}>
        <H2>Site checklist</H2>
        <Text style={{ color: theme.text.secondary, fontSize: 12 }}>
          Source: reports/{SNAPSHOT.runStamp}/migrate-summary.csv +
          spike-50-sites.csv - Warm = assets warmed after cutover
        </Text>
        <Table
          headers={["Site", "Domain", "Status", "KV pages", "Warm", "Asset"]}
          rows={tableRows}
          rowTone={SNAPSHOT.sites.map((s) => statusTone(s.Status))}
          columnAlign={["left", "left", "left", "right", "right", "left"]}
        />
      </Stack>
    </Stack>
  );
}