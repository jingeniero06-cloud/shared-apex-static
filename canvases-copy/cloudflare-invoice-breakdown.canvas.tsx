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

export default function CloudflareInvoiceBreakdown() {
  const theme = useHostTheme();

  return (
    <Stack gap={20} style={{ padding: 20 }}>
      <Stack gap={6}>
        <H1>Cloudflare invoice breakdown</H1>
        <Text style={{ color: theme.text.secondary }}>
          Invoice IN-72787322 · CityThrive LLC · Jul 25, 2026 · period covering
          Workers/R2 usage Jun 25-Jul 24 and subscriptions Jul 25-Aug 24
        </Text>
      </Stack>

      <Grid columns={3} gap={12}>
        <Stat value="$271.83" label="Total due" tone="warning" />
        <Stat value="$250.00" label="Business plan (citythrive.com)" />
        <Stat value="$5.00" label="Workers Paid (needed)" tone="success" />
      </Grid>

      <Callout tone="warning" title="You are not only paying $5">
        The $5 Workers Paid line is real and needed for static Workers/KV/R2.
        Almost all of this invoice is the separate $250 Business Website plan on
        citythrive.com, plus Texas tax.
      </Callout>

      <Stack gap={8}>
        <H2>What you actually paid</H2>
        <Table
          headers={["Line item", "Amount", "Need for shared fleet?"]}
          columnAlign={["left", "right", "left"]}
          rows={[
            [
              <Text weight="medium">Cloudflare Business Plan (citythrive.com)</Text>,
              "$250.00",
              <Pill tone="warning" size="sm">
                No - zone plan only
              </Pill>,
            ],
            [
              <Text weight="medium">Workers Paid</Text>,
              "$5.00",
              <Pill tone="success" size="sm">
                Yes - keep
              </Pill>,
            ],
            [
              "TX tax (state + local on taxable portion)",
              "$16.83",
              <Pill tone="neutral" size="sm">
                Tax only
              </Pill>,
            ],
            [
              "R2 / KV / Images / Queues / Zaraz / Vectorize / Stream usage",
              "$0.00",
              <Pill tone="neutral" size="sm">
                Listed, unused
              </Pill>,
            ],
          ]}
          rowTone={["warning", "success", "neutral", "neutral"]}
        />
        <Text style={{ color: theme.text.secondary, fontSize: 12 }}>
          Source: invoice PDF 16970d3f-3cf1-555b-8e6d-f4a3ae7688aa · Subtotal
          $255 + tax $16.83 = $271.83
        </Text>
      </Stack>

      <Divider />

      <Card>
        <CardHeader>Do you need to change anything?</CardHeader>
        <CardBody>
          <Stack gap={10}>
            <Text>
              <Text weight="medium">Keep Workers Paid ($5).</Text> Required for
              fleet-static-worker, KV HTML_FLEET, R2 assets, and the remaining
              per-site Workers. Canceling this breaks static serving.
            </Text>
            <Text>
              <Text weight="medium">Business on citythrive.com ($250) is optional for the static project.</Text>{" "}
              It is a per-zone website plan (SLA, stronger WAF/custom certs,
              priority support). It does not buy you more Workers or raise the
              500-Worker limit. Confirmed live plan today: Business Website on
              citythrive.com.
            </Text>
            <Text>
              <Text weight="medium">If citythrive.com does not need Business features,</Text>{" "}
              downgrade that one zone to Pro (~$20-25/mo) or Free to cut ~$225+/mo.
              Only do that after checking whether you rely on custom uploaded SSL,
              Business WAF rules, PCI, or the 100% uptime SLA.
            </Text>
            <Text>
              <Text weight="medium">Do not buy Workers for Platforms yet</Text> —
              shared fleet Worker is the path you chose instead.
            </Text>
          </Stack>
        </CardBody>
      </Card>

      <Stack gap={6}>
        <H2>Rough monthly picture</H2>
        <Table
          headers={["Scenario", "Est. monthly"]}
          columnAlign={["left", "right"]}
          rows={[
            ["Current (Business + Workers Paid + tax)", "~$272"],
            ["Workers Paid only (downgrade citythrive.com to Free)", "~$5 + tax"],
            ["Workers Paid + Pro on citythrive.com", "~$25-30 + tax"],
            ["Add Workers for Platforms (not recommended now)", "+ ~$25 base + script overage"],
          ]}
        />
      </Stack>
    </Stack>
  );
}
