# Next.js (App Router)

Read `references/typescript.md` first — package.json, `.npmrc`, biome, vitest and knip come from there. This file adds only what is Next.js-specific.

Resolve every version at scaffold time — see the rule in SKILL.md.

## Boilerplate

Create the official App Router boilerplate from the `vercel/next.js` template at `packages/create-next-app/templates/app/ts/`.

Fetch it with WebFetch against raw.githubusercontent.com **at the release tag matching the `next` version you are installing**, never from `main`:

```
https://raw.githubusercontent.com/vercel/next.js/v{next-version}/packages/create-next-app/templates/app/ts/{file}
```

Run `npm view next version` to resolve the tag. A `main`/`HEAD` URL is a mutable reference — the same supply-chain hole this skill closes for GitHub Actions — and it drifts out of sync with the pinned `next` release. Read what you fetch before writing it; this step copies third-party code into the project.

Create:

- `next.config.ts` — empty Next.js config (replaced by the security-headers version below)
- `tsconfig.json` — TypeScript config with Next.js plugin and `@/*` path alias
- `app/layout.tsx` — root layout with Geist fonts
- `app/page.tsx` — default home page
- `app/globals.css` — global styles
- `app/page.module.css` — page-level CSS module
- `public/` — SVG assets (`file.svg`, `globe.svg`, `next.svg`, `vercel.svg`, `window.svg`)

## Runtime dependencies

```bash
npm install next react react-dom
npm install -D typescript @types/node @types/react @types/react-dom vitest
```

Install the newest TypeScript this Next.js release actually supports — do not assume `latest` is safe. Next.js declares no `typescript` peer dependency, so npm stays silent on a mismatch and a TypeScript major that Next.js has not adopted yet fails only at build, as an opaque error rather than a version complaint (observed with Next.js 16.2.10 + TypeScript 7.0.2: `next build` dies with `The "id" argument must be of type string. Received undefined`, while the same tree builds on 5.x). The `npm run build` at the end of this file is the check. If it fails, install the newest major that does build (`npm install -D typescript@{major}`) and record the constraint in the CLAUDE.md Development section, so the next person does not helpfully bump it back.

## Error & loading boundaries

`create-next-app` does not add these; without them a runtime error is a white screen. Create minimal, correct-by-default stubs:

`app/error.tsx`:

```tsx
"use client";

export default function Error({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <div role="alert">
      <h2>Something went wrong</h2>
      <button type="button" onClick={() => reset()}>Try again</button>
    </div>
  );
}
```

`app/global-error.tsx` (catches errors in the root layout; must render its own `<html>`/`<body>`):

```tsx
"use client";

export default function GlobalError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <html lang="en">
      <body>
        <h2>Something went wrong</h2>
        <button type="button" onClick={() => reset()}>Try again</button>
      </body>
    </html>
  );
}
```

`app/not-found.tsx`:

```tsx
import Link from "next/link";

export default function NotFound() {
  return (
    <div>
      <h2>Not found</h2>
      <Link href="/">Return home</Link>
    </div>
  );
}
```

`app/loading.tsx`:

```tsx
export default function Loading() {
  return <p>Loading…</p>;
}
```

## Security headers

Add a static baseline header set to `next.config.ts`. **Do not add a Content-Security-Policy here** — a permissive/`unsafe-inline` CSP is a false safeguard; a real nonce-based CSP belongs in middleware once the app's script/style sources are known (left as a TODO in the CLAUDE.md Launch Readiness section). HSTS only takes effect over HTTPS, so it is inert in local dev.

```ts
import type { NextConfig } from "next";

const securityHeaders = [
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "X-Frame-Options", value: "SAMEORIGIN" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "Strict-Transport-Security", value: "max-age=63072000; includeSubDomains; preload" },
];

const nextConfig: NextConfig = {
  async headers() {
    return [{ source: "/:path*", headers: securityHeaders }];
  },
};

export default nextConfig;
```

`preload` commits the apex domain to the HSTS preload list, which is slow and painful to reverse. Keep it only if the project will genuinely serve every subdomain over HTTPS forever; drop it otherwise.

## SEO scaffold — `public-web` only

Skip for `internal-web`, `api`, and `library`/`cli`.

For an **internal tool**, do the opposite: keep crawlers out. `robots.ts` alone is not enough — `robots.txt` asks crawlers not to *crawl*, but a URL linked from elsewhere can still be indexed. Send `X-Robots-Tag: noindex` from the `next.config.ts` header block above for a real gate.

Replace the default `metadata` export in `app/layout.tsx` (the template already imports `Metadata`) so `metadataBase` and base metadata resolve to the real origin, not the preview/localhost domain:

```ts
export const metadata: Metadata = {
  metadataBase: new URL(process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000"),
  title: { default: "{project-name}", template: "%s | {project-name}" },
  description: "{one-line description}",
};
```

`app/robots.ts`:

```ts
import type { MetadataRoute } from "next";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: "*", allow: "/", disallow: "/api/" },
    sitemap: `${siteUrl}/sitemap.xml`,
  };
}
```

`app/sitemap.ts`:

```ts
import type { MetadataRoute } from "next";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000";

export default function sitemap(): MetadataRoute.Sitemap {
  return [{ url: siteUrl, lastModified: new Date() }];
}
```

The scaffolded code reads `NEXT_PUBLIC_SITE_URL`. Create `.env.example` (or append to it) documenting it — without a real value, canonical/OG/sitemap URLs fall back to `localhost`:

```
NEXT_PUBLIC_SITE_URL=https://example.com
```

`.env.example` is the only env file the `.gitignore` keeps tracked; real values belong in `.env`, which is ignored.

## Health endpoint

Applies to any served web app or API. Skip for `library`/`cli`. The deploy orchestrator uses it for readiness checks; a trivial 200 is correct-by-default and cheap now.

`app/api/health/route.ts`:

```ts
export const dynamic = "force-dynamic";

export function GET() {
  return Response.json({ status: "ok" });
}
```

## Verification

```bash
npm run build
```

This both verifies the setup and generates `next-env.d.ts`. Then run the rest of the toolchain from `references/typescript.md`.
