/**
 * Fleet Model B apex static Worker — one script for many domains.
 * Keys: `{hostname}:html:{path}` and `{hostname}:asset:{path}`
 */
const ASSET_EXTENSIONS = new Set([
  ".css", ".js", ".mjs",
  ".png", ".jpg", ".jpeg", ".gif", ".webp", ".avif", ".svg", ".ico",
  ".woff", ".woff2", ".ttf", ".otf", ".eot",
  ".pdf", ".txt", ".xml",
  ".mp4", ".webm", ".mov", ".mp3", ".wav",
]);

function apexHost(hostname) {
  const h = (hostname || "").toLowerCase();
  return h.startsWith("www.") ? h.slice(4) : h;
}

function normalizePath(pathname) {
  if (!pathname || pathname === "/") return "/index.html";
  if (pathname.length > 1 && pathname.endsWith("/")) {
    pathname = pathname.slice(0, -1);
  }
  return pathname;
}

function hasAssetExtension(pathname) {
  const lower = pathname.toLowerCase();
  for (const ext of ASSET_EXTENSIONS) {
    if (lower.endsWith(ext)) return true;
  }
  return false;
}

function guessContentType(pathname) {
  const lower = pathname.toLowerCase();
  if (lower.endsWith(".html") || lower.endsWith(".htm")) return "text/html; charset=utf-8";
  if (lower.endsWith(".css")) return "text/css; charset=utf-8";
  if (lower.endsWith(".js") || lower.endsWith(".mjs")) return "application/javascript; charset=utf-8";
  if (lower.endsWith(".json")) return "application/json; charset=utf-8";
  if (lower.endsWith(".png")) return "image/png";
  if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg";
  if (lower.endsWith(".gif")) return "image/gif";
  if (lower.endsWith(".webp")) return "image/webp";
  if (lower.endsWith(".avif")) return "image/avif";
  if (lower.endsWith(".svg")) return "image/svg+xml";
  if (lower.endsWith(".ico")) return "image/x-icon";
  if (lower.endsWith(".woff")) return "font/woff";
  if (lower.endsWith(".woff2")) return "font/woff2";
  if (lower.endsWith(".ttf")) return "font/ttf";
  if (lower.endsWith(".otf")) return "font/otf";
  if (lower.endsWith(".eot")) return "application/vnd.ms-fontobject";
  if (lower.endsWith(".pdf")) return "application/pdf";
  if (lower.endsWith(".txt")) return "text/plain; charset=utf-8";
  if (lower.endsWith(".xml")) return "application/xml; charset=utf-8";
  if (lower.endsWith(".mp4")) return "video/mp4";
  if (lower.endsWith(".webm")) return "video/webm";
  if (lower.endsWith(".mov")) return "video/quicktime";
  if (lower.endsWith(".mp3")) return "audio/mpeg";
  if (lower.endsWith(".wav")) return "audio/wav";
  return "application/octet-stream";
}

function isRewritableTextAsset(pathname, contentType) {
  const lowerPath = pathname.toLowerCase();
  const lowerContentType = (contentType || guessContentType(pathname)).toLowerCase();
  return (
    lowerPath.endsWith(".css") ||
    lowerPath.endsWith(".js") ||
    lowerPath.endsWith(".mjs") ||
    lowerPath.endsWith(".json") ||
    lowerPath.endsWith(".txt") ||
    lowerContentType.startsWith("text/") ||
    lowerContentType.includes("javascript") ||
    lowerContentType.includes("json")
  );
}

function rewriteUrls(html, originHost, cloudflareDomain, originProtocol) {
  if (!originHost || !cloudflareDomain || originHost === cloudflareDomain) return html;
  const originBase = `${originProtocol}://${originHost}`;
  const cloudflareBase = `https://${cloudflareDomain}`;
  const escapeRegex = (str) => str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const escapedOriginHost = escapeRegex(originHost);
  const encodedCloudflareBase = encodeURIComponent(cloudflareBase);
  const slashEscapedCloudflareBase = cloudflareBase.split("/").join("\\/");
  const originBases = Array.from(
    new Set([originBase, `https://${originHost}`, `http://${originHost}`])
  );
  for (const candidateOriginBase of originBases) {
    html = html.replace(new RegExp(escapeRegex(candidateOriginBase), "gi"), cloudflareBase);
    html = html.replace(
      new RegExp(escapeRegex(encodeURIComponent(candidateOriginBase)), "gi"),
      encodedCloudflareBase
    );
    const slashEscapedCandidateOriginBase = candidateOriginBase.split("/").join("\\/");
    html = html.split(slashEscapedCandidateOriginBase).join(slashEscapedCloudflareBase);
  }
  html = html.replace(
    new RegExp(`//${escapedOriginHost}(?=/|"|'|\\s|>)`, "gi"),
    `//${cloudflareDomain}`
  );
  html = html
    .split(`//${originHost}`.split("/").join("\\/"))
    .join(`//${cloudflareDomain}`.split("/").join("\\/"));
  html = html.replace(new RegExp(`"${escapeRegex(originBase)}"`, "gi"), `"${cloudflareBase}"`);
  html = html.replace(new RegExp(`'${escapeRegex(originBase)}'`, "gi"), `'${cloudflareBase}'`);
  html = html.replace(
    new RegExp(`(["'])${escapedOriginHost}(["'])`, "gi"),
    `$1${cloudflareDomain}$2`
  );
  return html;
}

function siteKeys(host, normalizedPath) {
  return {
    htmlKey: `${host}:html:${normalizedPath}`,
    assetKey: `${host}:asset:${normalizedPath}`,
  };
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const host = apexHost(url.hostname);
    const cloudflareDomain = host;
    const originHost = host;
    const originProtocol = env.ORIGIN_PROTOCOL || "https";
    const normalizedPath = normalizePath(url.pathname);
    const isAsset = hasAssetExtension(normalizedPath);
    const { htmlKey, assetKey } = siteKeys(host, normalizedPath);
    const refreshHeader =
      request.headers.get("x-force-refresh") || request.headers.get("X-Force-Refresh");
    const forceRefresh =
      refreshHeader === "true" || url.searchParams.get("_refresh") === "true";

    try {
      if (!forceRefresh) {
        if (isAsset) {
          const obj = await env.ASSETS_BUCKET.get(assetKey);
          if (obj) {
            const ct =
              (obj.httpMetadata && obj.httpMetadata.contentType) ||
              guessContentType(normalizedPath);
            if (isRewritableTextAsset(normalizedPath, ct)) {
              const assetText = await obj.text();
              const rewritten = rewriteUrls(
                assetText,
                originHost,
                cloudflareDomain,
                originProtocol
              );
              return new Response(rewritten, {
                status: 200,
                headers: {
                  "content-type": ct,
                  "cache-control": "public, max-age=31536000, immutable",
                  "x-source": "r2",
                  "x-fleet-host": host,
                },
              });
            }
            return new Response(obj.body, {
              status: 200,
              headers: {
                "content-type": ct,
                "cache-control": "public, max-age=31536000, immutable",
                "x-source": "r2",
                "x-fleet-host": host,
              },
            });
          }
        } else {
          const html = await env.HTML_KV.get(htmlKey);
          if (html) {
            const rewritten = rewriteUrls(html, originHost, cloudflareDomain, originProtocol);
            return new Response(rewritten, {
              status: 200,
              headers: {
                "content-type": "text/html; charset=utf-8",
                "cache-control": "public, max-age=300",
                "x-source": "kv",
                "x-fleet-host": host,
              },
            });
          }
        }
      }

      // Origin fill: prefer https://{host}/ with resolveOverride to hosting IP
      // (correct SNI/Host). Fallback: IP URL + Host header. Origin may still 403;
      // already-static sites should hit KV/R2 above after migrate copy.
      const hostingIp = env.HOSTING_IP || "174.136.29.214";
      const originPath = `${url.pathname}${url.search}`;
      const fetchOrigin = (targetUrl, extraHeaders = {}) =>
        fetch(targetUrl, {
          method: "GET",
          headers: {
            "user-agent": "Fleet-Static-Worker/1.0",
            accept: "*/*",
            ...extraHeaders,
          },
          // @ts-ignore CF runtime
          cf: { resolveOverride: hostingIp },
        });

      let originResp;
      try {
        originResp = await fetchOrigin(`${originProtocol}://${host}${originPath}`);
      } catch (_err1) {
        try {
          originResp = await fetchOrigin(`${originProtocol}://${hostingIp}${originPath}`, {
            Host: host,
          });
        } catch (_err2) {
          originResp = null;
        }
      }

      if (!originResp || !originResp.ok) {
        if (!forceRefresh) {
          if (isAsset) {
            const staleObj = await env.ASSETS_BUCKET.get(assetKey);
            if (staleObj) {
              const ct =
                (staleObj.httpMetadata && staleObj.httpMetadata.contentType) ||
                guessContentType(normalizedPath);
              return new Response(staleObj.body, {
                status: 200,
                headers: {
                  "content-type": ct,
                  "cache-control": "public, max-age=31536000, immutable",
                  "x-source": "r2-stale",
                  "x-fleet-host": host,
                },
              });
            }
          } else {
            const staleHtml = await env.HTML_KV.get(htmlKey);
            if (staleHtml) {
              return new Response(staleHtml, {
                status: 200,
                headers: {
                  "content-type": "text/html; charset=utf-8",
                  "cache-control": "public, max-age=300",
                  "x-source": "kv-stale",
                  "x-fleet-host": host,
                },
              });
            }
          }
        }
        const status = originResp ? originResp.status : 502;
        return new Response(`Origin error ${status}`, {
          status,
          headers: {
            "x-source": "origin-error",
            "x-fleet-host": host,
          },
        });
      }

      const originContentType = originResp.headers.get("content-type") || "";

      if (originContentType.includes("text/html") || !isAsset) {
        let htmlBody = await originResp.text();
        htmlBody = rewriteUrls(htmlBody, originHost, cloudflareDomain, originProtocol);
        ctx.waitUntil(env.HTML_KV.put(htmlKey, htmlBody));
        return new Response(htmlBody, {
          status: 200,
          headers: {
            "content-type": "text/html; charset=utf-8",
            "cache-control": "public, max-age=300",
            "x-source": "origin-html",
            "x-fleet-host": host,
          },
        });
      }

      const buffer = await originResp.arrayBuffer();
      const ct = originContentType || guessContentType(normalizedPath);
      let responseBody = buffer;
      let bodyToStore = buffer;
      if (isRewritableTextAsset(normalizedPath, ct)) {
        const assetText = new TextDecoder().decode(buffer);
        const rewritten = rewriteUrls(assetText, originHost, cloudflareDomain, originProtocol);
        responseBody = rewritten;
        bodyToStore = new TextEncoder().encode(rewritten);
      }
      ctx.waitUntil(
        env.ASSETS_BUCKET.put(assetKey, bodyToStore, {
          httpMetadata: { contentType: ct },
        })
      );
      return new Response(responseBody, {
        status: 200,
        headers: {
          "content-type": ct,
          "cache-control": "public, max-age=31536000, immutable",
          "x-source": "origin-asset",
          "x-fleet-host": host,
        },
      });
    } catch (err) {
      return new Response(`Internal error: ${err.message}`, { status: 500 });
    }
  },
};
