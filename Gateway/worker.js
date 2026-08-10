const FIREWORKS_ORIGIN = "https://api.fireworks.ai";
const YOUCAM_ORIGIN = "https://yce-api-01.makeupar.com";

const YOUCAM_PATH = /^\/s2s\/v2\.0\/(file\/upload|credit\/feature-cost|task\/[A-Za-z0-9_./-]+)$/;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "GET" && url.pathname === "/health") {
      return Response.json({ status: "ok" });
    }

    const user = await authenticatedFirebaseUser(request, env);
    if (!user) return jsonError(401, "Authentication required");
    if (!(await withinRateLimit(user.localId, env))) {
      return jsonError(429, "Request limit reached");
    }

    if (url.pathname === "/v1/fireworks/chat/completions" && request.method === "POST") {
      return proxy(request, `${FIREWORKS_ORIGIN}/inference/v1/chat/completions`, {
        Authorization: `Bearer ${env.FIREWORKS_API_KEY}`,
      });
    }

    if (url.pathname.startsWith("/v1/youcam/")) {
      const upstreamPath = `/${url.pathname.slice("/v1/youcam/".length)}`;
      const methodAllowed = ["GET", "POST"].includes(request.method)
        || (request.method === "DELETE" && upstreamPath.startsWith("/s2s/v2.0/task/"));
      if (!YOUCAM_PATH.test(upstreamPath) || !methodAllowed) {
        return jsonError(404, "Unsupported YouCam operation");
      }
      return proxy(request, `${YOUCAM_ORIGIN}${upstreamPath}${url.search}`, {
        Authorization: `Bearer ${env.YOUCAM_API_KEY}`,
      });
    }

    return jsonError(404, "Not found");
  },
};

async function authenticatedFirebaseUser(request, env) {
  const header = request.headers.get("Authorization") || "";
  if (!header.startsWith("Bearer ") || !env.FIREBASE_WEB_API_KEY) return null;
  const idToken = header.slice(7);
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${encodeURIComponent(env.FIREBASE_WEB_API_KEY)}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ idToken }),
    },
  );
  if (!response.ok) return null;
  const payload = await response.json();
  const user = payload.users?.[0];
  return user?.localId ? user : null;
}

async function withinRateLimit(userID, env) {
  if (!env.RATE_LIMITS) return true;
  const minute = Math.floor(Date.now() / 60000);
  const key = `${userID}:${minute}`;
  const count = Number((await env.RATE_LIMITS.get(key)) || "0");
  if (count >= 20) return false;
  await env.RATE_LIMITS.put(key, String(count + 1), { expirationTtl: 120 });
  return true;
}

async function proxy(request, upstreamURL, injectedHeaders) {
  const length = Number(request.headers.get("Content-Length") || "0");
  if (length > 25_000_000) return jsonError(413, "Request too large");

  const headers = new Headers();
  const contentType = request.headers.get("Content-Type");
  if (contentType) headers.set("Content-Type", contentType);
  const accept = request.headers.get("Accept");
  if (accept) headers.set("Accept", accept);
  for (const [name, value] of Object.entries(injectedHeaders)) headers.set(name, value);

  const response = await fetch(upstreamURL, {
    method: request.method,
    headers,
    body: request.method === "GET" ? undefined : request.body,
    redirect: "manual",
  });
  const safeHeaders = new Headers();
  const responseType = response.headers.get("Content-Type");
  if (responseType) safeHeaders.set("Content-Type", responseType);
  const retryAfter = response.headers.get("Retry-After");
  if (retryAfter) safeHeaders.set("Retry-After", retryAfter);
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers: safeHeaders,
  });
}

function jsonError(status, message) {
  return Response.json({ error: message }, { status });
}
