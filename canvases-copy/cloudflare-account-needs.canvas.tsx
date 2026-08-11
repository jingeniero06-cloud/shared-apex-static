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
  Stack,
  Stat,
  Table,
  Text,
  useHostTheme,
} from "cursor/canvas";

export default function CloudflareAccountNeeds() {
  const theme = useHostTheme();

  return (
    <Stack gap={20} style={{ padding: 20 }}>
      <Stack gap={6}>
        <H1>What Michael's Cloudflare account actually needs</H1>
        <Text style={{ color: theme.text.secondary }}>
          Account f215f8ca... (Michael@citythrive.com) · audited Aug 12, 2026 ·
          compared to invoice IN-72787322 ($271.83)
        </Text>
      </Stack>

      <Grid columns={4} gap={12}>
        <Stat value="1,628" label="Zones total" />
        <Stat value="500" label="Workers (at Paid cap)" tone="warning" />
        <Stat value="654" label="KV namespaces" />
        <Stat value="653" label="R2 buckets" />
      </Grid>

      <Callout tone="info" title="Short answer">
        Keep Workers Paid ($5). The $250 Business plan on citythrive.com is not
        required for the static fleet, and this zone is not using Business-only
        features. Everything else on the invoice was $0 usage.
      </Callout>

      <Stack gap={8}>
        <H2>Paid products vs need</H2>
        <Table
          headers={["Product", "Invoice", "Account reality", "Verdict"]}
          columnAlign={["left", "right", "left", "left"]}
          rows={[
            [
              <Text weight="medium">Workers Paid</Text>,
              "$5",
              "500 Workers + fleet-static-worker + HTML_FLEET + R2 assets",
              <Pill tone="success" size="sm">
                Required
              </Pill>,
            ],
            [
              <Text weight="medium">Business (citythrive.com)</Text>,
              "$250",
              "Only paid zone of 1,628; rest Free",
              <Pill tone="warning" size="sm">
                Not needed for fleet
              </Pill>,
            ],
            [
              "R2 Paid",
              "$0",
              "653 buckets incl. fleet-static-assets; usage under free tier",
              <Pill tone="success" size="sm">
                Keep (free base)
              </Pill>,
            ],
            [
              "Images / Queues / Zaraz / Vectorize / Stream",
              "$0",
              "Listed on invoice; zero billable usage",
              <Pill tone="neutral" size="sm">
                Ignore
              </Pill>,
            ],
            [
              "Workers for Platforms",
              "not on invoice",
              "Not subscribed; shared fleet Worker is the alternative",
              <Pill tone="neutral" size="sm">
                Do not buy
              </Pill>,
            ],
          ]}
          rowTone={["success", "warning", "success", "neutral", "neutral"]}
        />
      </Stack>

      <Divider />

      <Card>
        <CardHeader trailing={<Pill size="sm">citythrive.com</Pill>}>
          Why Business looks unnecessary here
        </CardHeader>
        <CardBody>
          <Stack gap={8}>
            <Text>
              Live plan is Business Website, but the zone is configured like a
              normal site:
            </Text>
            <Table
              headers={["Check", "Found"]}
              rows={[
                ["Custom uploaded SSL certs", "0 (Business specialty unused)"],
                ["Page Rules", "0"],
                ["Legacy WAF managed toggle", "off"],
                ["Custom firewall rules", "4 (Pro can do this)"],
                ["SSL mode", "flexible"],
                ["Security level", "medium"],
              ]}
            />
            <Text style={{ color: theme.text.secondary, fontSize: 12 }}>
              Custom rules present: challenge WP login/admin, block CN/RU/KP,
              block .test subdomains, disabled Azure scanner rule. All fine on
              Pro.
            </Text>
          </Stack>
        </CardBody>
      </Card>

      <Stack gap={8}>
        <H2>Recommended changes</H2>
        <Table
          headers={["Action", "Save / impact"]}
          rows={[
            [
              "Keep Workers Paid",
              "Required for static Workers/KV/R2. Canceling breaks sites.",
            ],
            [
              "Downgrade citythrive.com Business -> Pro (or Free)",
              "Saves ~$225-250/mo if you do not need SLA / custom certs / Business support.",
            ],
            [
              "Continue shared fleet migrate (50 spike done)",
              "Lets you delete old per-site Workers later and stay under the 500 cap.",
            ],
            [
              "Do not buy Workers for Platforms",
              "Avoids ~$25+ /mo; fleet Worker path already proven on 50 sites.",
            ],
          ]}
        />
      </Stack>

      <Text style={{ color: theme.text.secondary, fontSize: 12 }}>
        Zone plan mix: 1,627 Free + 1 Business. Fleet infra present:
        fleet-static-worker, KV HTML_FLEET
        (b5179c7b51b243b08248005087441527), R2 fleet-static-assets.
      </Text>
    </Stack>
  );
}
