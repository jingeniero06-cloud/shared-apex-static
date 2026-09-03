const ALLOW = new Set([
  "coconutcreekfoundationrepair.com",
  "static.coconutcreekfoundationrepair.com",
]);

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/api/probe") {
      if (request.method !== "GET") {
        return Response.json({ error: "method not allowed" }, { status: 405 });
      }
      const host = (url.searchParams.get("host") || "").toLowerCase();
      const path = url.searchParams.get("path") || "/";
      if (!ALLOW.has(host)) {
        return Response.json({ error: "host not allowed" }, { status: 400 });
      }
      if (!/^\/[A-Za-z0-9._/-]*$/.test(path)) {
        return Response.json({ error: "bad path" }, { status: 400 });
      }
      const target = `https://${host}${path}`;
      const r = await fetch(target, {
        method: "GET",
        headers: { "user-agent": "Mozilla/5.0 (compatible; CityThriveDocs/1.0)" },
        redirect: "follow",
      });
      if (r.body) {
        r.body.cancel();
      }
      return Response.json(
        {
          url: target,
          status: r.status,
          source: r.headers.get("x-source"),
          fleetHost: r.headers.get("x-fleet-host"),
          contentType: r.headers.get("content-type"),
        },
        { headers: { "cache-control": "no-store" } }
      );
    }
    return env.ASSETS.fetch(request);
  },
};
