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
  updatedAt: "2026-08-12T05:59:56.5996861+08:00",
  runStamp: "migrate-20260812-merged",
  currentIdx: 49,
  currentDomain: "brentwoodtnfoundationrepair.com",
  total: 50,
  ok: 50,
  fail: 0,
  done: 50,
  worker: "fleet-static-worker",
  kv: "HTML_FLEET",
  r2: "fleet-static-assets",
  sites: [{"Domain":"bedfordtreeservicecompany.com","Batch":"3","SiteName":"Bedford Tree Service Company","Status":"ok","KvCopied":"27","After":"200/kv/fleet=bedfordtreeservicecompany.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"beechwoodvillagefoundationrepair.com","Batch":"3","SiteName":"Beechwood Village Foundation Repair","Status":"ok","KvCopied":"42","After":"200/kv/fleet=beechwoodvillagefoundationrepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"belenfoundationrepair.com","Batch":"3","SiteName":"Belen Foundation Repair","Status":"ok","KvCopied":"49","After":"200/kv/fleet=belenfoundationrepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"bellaireconcreterepairandleveling.com","Batch":"3","SiteName":"Bellaire Concrete Repair and Leveling","Status":"ok","KvCopied":"34","After":"200/kv/fleet=bellaireconcreterepairandleveling.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"bellairmeadowbrookterracefoundationrepair.com","Batch":"3","SiteName":"Bellair-Meadowbrook Terrace Foundation Repair","Status":"ok","KvCopied":"32","After":"200/kv/fleet=bellairmeadowbrookterracefoundationrepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"belleairbluffsfoundationrepair.com","Batch":"3","SiteName":"Belleair Bluffs Foundation Repair","Status":"ok","KvCopied":"32","After":"200/kv/fleet=belleairbluffsfoundationrepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"belleairfoundationrepair.com","Batch":"3","SiteName":"Belleair Foundation Repair","Status":"ok","KvCopied":"35","After":"200/kv/fleet=belleairfoundationrepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"bellegladefoundationrepair.com","Batch":"3","SiteName":"Belle Glade Foundation Repair","Status":"ok","KvCopied":"43","After":"200/kv/fleet=bellegladefoundationrepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"belleviewcrawlspacerepair.com","Batch":"3","SiteName":"Belleview Crawl Space Repair","Status":"ok","KvCopied":"24","After":"200/kv/fleet=belleviewcrawlspacerepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"belleviewfoundationrepair.com","Batch":"3","SiteName":"Belleview Foundation Repair","Status":"ok","KvCopied":"47","After":"200/kv/fleet=belleviewfoundationrepair.com","Asset":"200/r2","Warm":"24","Error":""},{"Domain":"beltonfoundationrepair.com","Batch":"3","SiteName":"Belton Foundation Repair","Status":"ok","KvCopied":"40","After":"200/kv/fleet=beltonfoundationrepair.com","Asset":"200/r2","Warm":"28","Error":""},{"Domain":"benbrookfoundationrepair.com","Batch":"3","SiteName":"Benbrook Foundation Repair","Status":"ok","KvCopied":"54","After":"200/kv/fleet=benbrookfoundationrepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"benbrooktreeservice.com","Batch":"3","SiteName":"Benbrook Tree Service","Status":"ok","KvCopied":"22","After":"200/kv/fleet=benbrooktreeservice.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"bensonfoundationrepair.com","Batch":"3","SiteName":"Benson Foundation Repair","Status":"ok","KvCopied":"47","After":"200/kv/fleet=bensonfoundationrepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"bentonfoundationrepairexperts.com","Batch":"3","SiteName":"Benton Foundation Repair Experts","Status":"ok","KvCopied":"35","After":"200/kv/fleet=bentonfoundationrepairexperts.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"berlinbasementwaterproofing.com","Batch":"3","SiteName":"Berlin Basement Waterproofing","Status":"ok","KvCopied":"15","After":"200/kv/fleet=berlinbasementwaterproofing.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"berlinfoundationrepair.com","Batch":"3","SiteName":"Berlin Foundation Repair","Status":"ok","KvCopied":"71","After":"200/kv/fleet=berlinfoundationrepair.com","Asset":"200/r2","Warm":"25","Error":""},{"Domain":"bernalillofoundationrepair.com","Batch":"3","SiteName":"Bernalillo Foundation Repair","Status":"ok","KvCopied":"48","After":"200/kv/fleet=bernalillofoundationrepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"bicknellfoundationrepair.com","Batch":"3","SiteName":"Bicknell Foundation Repair","Status":"ok","KvCopied":"70","After":"200/kv/fleet=bicknellfoundationrepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"bigsandyfoundationrepair.com","Batch":"3","SiteName":"Big Sandy Foundation Repair","Status":"ok","KvCopied":"41","After":"200/kv/fleet=bigsandyfoundationrepair.com","Asset":"200/r2","Warm":"22","Error":""},{"Domain":"bigspringbasementwaterproofing.com","Batch":"3","SiteName":"Big Spring Basement Waterproofing","Status":"ok","KvCopied":"23","After":"200/kv/fleet=bigspringbasementwaterproofing.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"bigspringconcreterepairandleveling.com","Batch":"3","SiteName":"Big Spring Concrete Repair And Leveling","Status":"ok","KvCopied":"33","After":"200/kv/fleet=bigspringconcreterepairandleveling.com","Asset":"200/r2","Warm":"26","Error":""},{"Domain":"bigspringcrawlspacerepair.com","Batch":"3","SiteName":"Big Spring Crawl Space Repair","Status":"ok","KvCopied":"24","After":"200/kv/fleet=bigspringcrawlspacerepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"bigspringfoundationrepair.com","Batch":"3","SiteName":"Big Spring Foundation Repair","Status":"ok","KvCopied":"34","After":"200/kv/fleet=bigspringfoundationrepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"blancofoundationrepair.com","Batch":"3","SiteName":"Blanco Foundation Repair","Status":"ok","KvCopied":"34","After":"200/kv/fleet=blancofoundationrepair.com","Asset":"200/r2","Warm":"27","Error":""},{"Domain":"blountstownfoundationrepair.com","Batch":"3","SiteName":"Blountstown Foundation Repair","Status":"ok","KvCopied":"35","After":"200/kv/fleet=blountstownfoundationrepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"bluespringsfoundationrepair.com","Batch":"3","SiteName":"Blue Springs Foundation Repair","Status":"ok","KvCopied":"80","After":"200/kv/fleet=bluespringsfoundationrepair.com","Asset":"200/r2","Warm":"25","Error":""},{"Domain":"bocaratonfoundationrepair.com","Batch":"3","SiteName":"Boca Raton Foundation Repair","Status":"ok","KvCopied":"32","After":"200/kv/fleet=bocaratonfoundationrepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"boernefoundationrepairpros.com","Batch":"3","SiteName":"Boerne Foundation Repair","Status":"ok","KvCopied":"55","After":"200/kv/fleet=boernefoundationrepairpros.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"bolivarfoundationrepair.com","Batch":"3","SiteName":"Bolivar Foundation Repair","Status":"ok","KvCopied":"70","After":"200/kv/fleet=bolivarfoundationrepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"bolivarfoundationrepairpros.com","Batch":"3","SiteName":"Bolivar Foundation Repair Pros","Status":"ok","KvCopied":"42","After":"200/kv/fleet=bolivarfoundationrepairpros.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"bonitaspringsfoundationrepair.com","Batch":"3","SiteName":"Bonita Springs Foundation Repair","Status":"ok","KvCopied":"38","After":"200/kv/fleet=bonitaspringsfoundationrepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"borgerconcreterepairandleveling.com","Batch":"3","SiteName":"Borger Concrete Repair And Leveling","Status":"ok","KvCopied":"24","After":"200/kv/fleet=borgerconcreterepairandleveling.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"borgerfoundationrepair.com","Batch":"3","SiteName":"Borger Foundation Repair","Status":"ok","KvCopied":"60","After":"200/kv/fleet=borgerfoundationrepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"bossiercityfoundationrepairexperts.com","Batch":"3","SiteName":"Bossier City Foundation Repair Experts","Status":"ok","KvCopied":"43","After":"200/kv/fleet=bossiercityfoundationrepairexperts.com","Asset":"200/r2","Warm":"24","Error":""},{"Domain":"bowlinggreenkyfoundationrepair.com","Batch":"3","SiteName":"Bowling Green Foundation Repair","Status":"ok","KvCopied":"18","After":"200/kv/fleet=bowlinggreenkyfoundationrepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"boyntonbeachfoundationrepair.com","Batch":"3","SiteName":"Boynton Beach Foundation Repair","Status":"ok","KvCopied":"34","After":"200/kv/fleet=boyntonbeachfoundationrepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"bradentonbeachcrawlspacerepair.com","Batch":"3","SiteName":"Bradenton Beach Crawl Space Repair","Status":"ok","KvCopied":"25","After":"200/kv/fleet=bradentonbeachcrawlspacerepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"bradentonbeachfoundationrepair.com","Batch":"3","SiteName":"Bradenton Beach Foundation Repair","Status":"ok","KvCopied":"17","After":"200/kv/fleet=bradentonbeachfoundationrepair.com","Asset":"200/r2","Warm":"22","Error":""},{"Domain":"bradentoncrawlspacerepair.com","Batch":"3","SiteName":"Bradenton Crawl Space Repair","Status":"ok","KvCopied":"23","After":"200/kv/fleet=bradentoncrawlspacerepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"bradentonfoundationrepair.com","Batch":"3","SiteName":"Bradenton Foundation Repair","Status":"ok","KvCopied":"50","After":"200/kv/fleet=bradentonfoundationrepair.com","Asset":"200/r2","Warm":"28","Error":""},{"Domain":"brandenburgfoundationrepair.com","Batch":"3","SiteName":"Brandenburg Foundation Repair","Status":"ok","KvCopied":"43","After":"200/kv/fleet=brandenburgfoundationrepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"brandoncrawlspacerepair.com","Batch":"3","SiteName":"Brandon Crawl Space Repair","Status":"ok","KvCopied":"23","After":"200/kv/fleet=brandoncrawlspacerepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"brandondrainagesolutions.com","Batch":"3","SiteName":"Brandon Drainage Solutions","Status":"ok","KvCopied":"16","After":"200/kv/fleet=brandondrainagesolutions.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"brandonfrenchdraininstallation.com","Batch":"3","SiteName":"Brandon French Drain Installation","Status":"ok","KvCopied":"22","After":"200/kv/fleet=brandonfrenchdraininstallation.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"bransonfoundationrepair.com","Batch":"3","SiteName":"Branson Foundation Repair","Status":"ok","KvCopied":"76","After":"200/kv/fleet=bransonfoundationrepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"breckenridgetreeservice.com","Batch":"3","SiteName":"Breckenridge Tree Service","Status":"ok","KvCopied":"23","After":"200/kv/fleet=breckenridgetreeservice.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"brenhamfoundationrepairexperts.com","Batch":"3","SiteName":"Brenham Foundation Repair Experts","Status":"ok","KvCopied":"33","After":"200/kv/fleet=brenhamfoundationrepairexperts.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"brentwoodtnfoundationrepair.com","Batch":"3","SiteName":"Brentwood Foundation Repair","Status":"ok","KvCopied":"65","After":"200/kv/fleet=brentwoodtnfoundationrepair.com","Asset":"200/r2","Warm":"29","Error":""},{"Domain":"bridgeportfoundationrepairsolutions.com","Batch":"3","SiteName":"Bridgeport Foundation Repair Solutions","Status":"ok","KvCopied":"54","After":"200/kv/fleet=bridgeportfoundationrepairsolutions.com","Asset":"200/r2","Warm":"29","Error":""}] as SiteRow[],
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