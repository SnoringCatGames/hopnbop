// Cloudflare Pages Function: Google OAuth code → id_token broker.
//
// The web client never holds the Google client_secret. It POSTs
// the authorization code + PKCE verifier here; this function
// adds the secret (from a Pages secret) and exchanges with
// Google. Returns the id_token to the client, which then sends
// it to Nakama.
//
// Same-origin with the Pages site (hopnbop.net), so no CORS
// dance needed.
//
// Required Pages secret:
//   GOOGLE_OAUTH_CLIENT_SECRET   — set via:
//     wrangler pages secret put GOOGLE_OAUTH_CLIENT_SECRET \
//       --project-name=hopnbop-website
//
// Required Pages env var (non-secret, can be set the same way
// or via dashboard):
//   GOOGLE_OAUTH_CLIENT_ID       — the Web Application client_id
//
// Request body (JSON):
//   { "code": "...", "redirect_uri": "...", "code_verifier": "..." }
//
// Response on success: 200 with the same JSON Google's /token
// endpoint returns (id_token, access_token, expires_in, ...).
// On failure: pass-through Google's error code + message with
// the same HTTP status.

export async function onRequestPost(context) {
  const { request, env } = context;

  let body;
  try {
    body = await request.json();
  } catch {
    return errorJson(400, "invalid_request",
      "Body must be JSON");
  }

  const required = ["code", "redirect_uri", "code_verifier"];
  for (const k of required) {
    if (!body[k] || typeof body[k] !== "string") {
      return errorJson(400, "invalid_request",
        `Missing or non-string '${k}'`);
    }
  }

  if (!env.GOOGLE_OAUTH_CLIENT_ID || !env.GOOGLE_OAUTH_CLIENT_SECRET) {
    return errorJson(500, "server_misconfigured",
      "OAuth client_id or client_secret not set on the broker");
  }

  const form = new URLSearchParams({
    code: body.code,
    client_id: env.GOOGLE_OAUTH_CLIENT_ID,
    client_secret: env.GOOGLE_OAUTH_CLIENT_SECRET,
    redirect_uri: body.redirect_uri,
    code_verifier: body.code_verifier,
    grant_type: "authorization_code",
  });

  const upstream = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: form.toString(),
  });

  // Pass through Google's response body + status. Any error
  // surfaces with its original shape so the client can log it.
  const upstreamBody = await upstream.text();
  return new Response(upstreamBody, {
    status: upstream.status,
    headers: { "Content-Type": "application/json" },
  });
}

// Pages Functions auto-routes by HTTP method when method-named
// exports exist (onRequestGet, onRequestPost, ...). Anything else
// returns a 405 by default — no catch-all needed.

function errorJson(status, error, description) {
  return new Response(
    JSON.stringify({ error, error_description: description }),
    { status, headers: { "Content-Type": "application/json" } },
  );
}
