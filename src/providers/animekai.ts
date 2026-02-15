const ANIMEKAI_BASE_URL = "https://animekai.to";
const ANIMEKAI_USER_AGENT = "rakuroku/1.0 (animekai-resolver)";

export const ANIMEKAI_HOME_URL = `${ANIMEKAI_BASE_URL}/home`;

export type AnimeKaiCandidate = {
  watchPath: string;
  title: string | null;
};

export function buildAnimeKaiSearchUrl(keyword: string): string {
  return `${ANIMEKAI_BASE_URL}/browser?keyword=${encodeURIComponent(keyword)}`;
}

export function buildAnimeKaiEpisodeUrl(watchPath: string, episode: number): string {
  const cleanPath = normalizeAnimeKaiWatchPathInput(watchPath) ?? watchPath;
  return `${ANIMEKAI_BASE_URL}${cleanPath}#ep=${episode}`;
}

type FetchTextParams = {
  timeoutMs?: number;
};

type FetchTextResult = {
  ok: boolean;
  status: number;
  text: string;
  error?: string;
};

async function fetchText(url: string, params: FetchTextParams = {}): Promise<FetchTextResult> {
  const timeoutMs = params.timeoutMs ?? 15000;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const response = await fetch(url, {
      method: "GET",
      headers: {
        Accept: "text/html",
        "Accept-Language": "en-US,en;q=0.9",
        "User-Agent": ANIMEKAI_USER_AGENT,
      },
      signal: controller.signal,
    });

    const text = await response.text();
    return { ok: response.ok, status: response.status, text };
  } catch (err) {
    return {
      ok: false,
      status: 0,
      text: "",
      error: err instanceof Error ? err.message : String(err),
    };
  } finally {
    clearTimeout(timeout);
  }
}

function normalizeSearchHtml(html: string): string {
  // Some responses embed paths in JSON strings where slashes are escaped (e.g. \/watch\/...).
  // Also handle unicode-escaped slashes (e.g. \u002Fwatch\u002F...).
  return html.replace(/\\\//g, "/").replace(/\\u002[fF]/g, "/");
}

export function extractWatchPathsFromSearchHtml(html: string): string[] {
  const normalizedHtml = normalizeSearchHtml(html);

  const ordered: string[] = [];
  const seen = new Set<string>();

  const add = (raw: string | undefined | null) => {
    if (!raw) return;
    let path = raw;
    if (path.startsWith("watch/")) {
      path = `/${path}`;
    }
    if (!path.startsWith("/watch/")) return;
    if (seen.has(path)) return;
    seen.add(path);
    ordered.push(path);
  };

  // href="/watch/slug" or href='/watch/slug'
  for (const m of normalizedHtml.matchAll(
    /href\s*=\s*(?:'|")(?<path>\/watch\/[^'"?#\s]+)(?:'|")/gi
  )) {
    add(m.groups?.path);
  }

  // href=/watch/slug (unquoted)
  for (const m of normalizedHtml.matchAll(/href\s*=\s*(?<path>\/watch\/[^'"?#\s>]+)/gi)) {
    add(m.groups?.path);
  }

  // Last resort: any /watch/slug occurrences (e.g. embedded in script or JSON).
  for (const m of normalizedHtml.matchAll(/\/watch\/[a-z0-9][a-z0-9-]*/gi)) {
    add(m[0]);
  }

  return ordered;
}

export function extractCandidatesFromSearchHtml(html: string): AnimeKaiCandidate[] {
  const normalizedHtml = normalizeSearchHtml(html);

  const ordered: AnimeKaiCandidate[] = [];
  const seen = new Set<string>();

  const add = (watchPathRaw: string | undefined | null, title: string | null) => {
    if (!watchPathRaw) return;
    let watchPath = watchPathRaw;
    if (watchPath.startsWith("watch/")) {
      watchPath = `/${watchPath}`;
    }
    if (!watchPath.startsWith("/watch/")) return;
    if (seen.has(watchPath)) return;
    seen.add(watchPath);
    ordered.push({ watchPath, title });
  };

  for (const m of normalizedHtml.matchAll(
    /href\s*=\s*(?:'|")(?<path>\/watch\/[^'"?#\s]+)(?:'|")/gi
  )) {
    const path = m.groups?.path ?? null;
    if (!path) continue;

    const idx = typeof m.index === "number" ? m.index : normalizedHtml.indexOf(path);
    const windowStart = idx >= 0 ? idx : 0;
    const window = normalizedHtml.slice(windowStart, windowStart + 900);

    let title: string | null = null;
    const titleText = window.match(/<a[^>]*class=(?:'|")title(?:'|")[^>]*>(?<t>[^<]+)<\/a>/i);
    if (titleText?.groups?.t) {
      title = titleText.groups.t.trim();
    }
    if (!title) {
      const titleAttr = window.match(/<a[^>]*class=(?:'|")title(?:'|")[^>]*title=(?:'|")(?<t>[^'"]+)(?:'|")/i);
      if (titleAttr?.groups?.t) {
        title = titleAttr.groups.t.trim();
      }
    }

    add(path, title);
  }

  // If no title-bearing anchors were found, fall back to path-only extraction.
  if (ordered.length === 0) {
    for (const watchPath of extractWatchPathsFromSearchHtml(normalizedHtml)) {
      add(watchPath, null);
    }
  }

  return ordered;
}

function extractAniListIdsFromHtml(html: string): number[] {
  return Array.from(html.matchAll(/anilist\.co\/anime\/(?<id>\d+)/gi), (m) =>
    Number(m.groups?.id)
  ).filter((n) => Number.isFinite(n));
}

export function pageMentionsAniListId(html: string, anilistId: number): boolean {
  return extractAniListIdsFromHtml(html).includes(anilistId);
}

export type AnimeKaiResolveResult = {
  watchPath: string | null;
  debugLog: string;
  candidates: AnimeKaiCandidate[];
};

async function mapWithConcurrency<TInput, TOutput>(
  inputs: TInput[],
  concurrency: number,
  worker: (input: TInput, index: number) => Promise<TOutput>
): Promise<TOutput[]> {
  const out: TOutput[] = new Array(inputs.length);
  let nextIndex = 0;

  const run = async () => {
    for (;;) {
      const idx = nextIndex;
      nextIndex += 1;
      if (idx >= inputs.length) return;
      out[idx] = await worker(inputs[idx], idx);
    }
  };

  const runners = Array.from({ length: Math.max(1, Math.min(concurrency, inputs.length)) }, () =>
    run()
  );
  await Promise.all(runners);
  return out;
}

export async function resolveAnimeKaiWatchPathStrictWithDebug(params: {
  anilistId: number;
  title: string;
  maxCandidates?: number;
  concurrency?: number;
  timeoutMs?: number;
}): Promise<AnimeKaiResolveResult> {
  const debug: string[] = [];

  debug.push(
    `[AnimeKai] start anilistId=${params.anilistId} title=${JSON.stringify(params.title)}`
  );

  const keyword = params.title.trim();
  if (!keyword) {
    debug.push("[AnimeKai] empty title keyword");
    return { watchPath: null, debugLog: debug.join("\n"), candidates: [] };
  }

  const maxCandidates = params.maxCandidates ?? 10;
  const concurrency = params.concurrency ?? 3;
  const timeoutMs = params.timeoutMs ?? 15000;
  const watchTimeoutMs = Math.min(timeoutMs, 8000);

  const searchUrl = buildAnimeKaiSearchUrl(keyword);
  debug.push(`[AnimeKai] GET search ${searchUrl}`);

  const searchRes = await fetchText(searchUrl, { timeoutMs });
  debug.push(
    `[AnimeKai] search status=${searchRes.status} ok=${searchRes.ok} len=${searchRes.text.length}${
      searchRes.error ? ` error=${JSON.stringify(searchRes.error)}` : ""
    }`
  );

  const allCandidateInfo = extractCandidatesFromSearchHtml(searchRes.text);
  const allCandidates = allCandidateInfo.map((c) => c.watchPath);
  const hasWatchSubstring =
    searchRes.text.includes("/watch/") ||
    searchRes.text.includes("\\/watch\\/") ||
    /\\u002fwatch\\u002f/i.test(searchRes.text);
  debug.push(`[AnimeKai] search hasWatchSubstring=${hasWatchSubstring}`);
  debug.push(`[AnimeKai] candidates=${allCandidates.length} maxCandidates=${maxCandidates}`);

  const candidates = allCandidateInfo.slice(0, maxCandidates);
  debug.push(
    `[AnimeKai] candidatePreview=${JSON.stringify(
      candidates.slice(0, 6).map((c) => ({ watchPath: c.watchPath, title: c.title }))
    )}`
  );

  const watchResults = await mapWithConcurrency(
    candidates,
    concurrency,
    async (candidate): Promise<{ candidate: AnimeKaiCandidate; matched: boolean; ids: number[]; res: FetchTextResult }> => {
      const watchUrl = `${ANIMEKAI_BASE_URL}${candidate.watchPath}`;
      debug.push(`[AnimeKai] GET watch ${watchUrl}`);

      const watchRes = await fetchText(watchUrl, { timeoutMs: watchTimeoutMs });
      const ids = extractAniListIdsFromHtml(watchRes.text);
      const matched = ids.includes(params.anilistId);

      debug.push(
        `[AnimeKai] watch status=${watchRes.status} ok=${watchRes.ok} len=${watchRes.text.length} ids=${ids
          .slice(0, 6)
          .join(",")}${matched ? " MATCH" : ""}${
          watchRes.error ? ` error=${JSON.stringify(watchRes.error)}` : ""
        }`
      );

      return { candidate, matched, ids, res: watchRes };
    }
  );

  const firstMatch = watchResults.find((r) => r.matched);
  const resolved = firstMatch?.candidate.watchPath ?? null;

  debug.push(`[AnimeKai] result=${resolved ?? "null"} fallbackUsed=false`);

  return { watchPath: resolved, debugLog: debug.join("\n"), candidates };
}

export async function resolveAnimeKaiWatchPathStrict(params: {
  anilistId: number;
  title: string;
  maxCandidates?: number;
  concurrency?: number;
  timeoutMs?: number;
}): Promise<string | null> {
  const { watchPath, debugLog } = await resolveAnimeKaiWatchPathStrictWithDebug(params);
  const isDev = Boolean((globalThis as any).__DEV__);
  if (isDev) {
    console.log(debugLog);
  }
  return watchPath;
}

export function normalizeAnimeKaiWatchPathInput(input: string): string | null {
  const trimmed = input.trim();
  if (!trimmed) return null;

  // Full URL: https://animekai.to/watch/<slug>#ep=2
  try {
    const url = new URL(trimmed);
    if (url.hostname.endsWith("animekai.to") && url.pathname.startsWith("/watch/")) {
      return url.pathname;
    }
  } catch {
    // Not a URL; try parsing as a path/slug.
  }

  // Path: /watch/<slug>
  if (trimmed.startsWith("/watch/")) {
    const cut = trimmed.split(/[?#]/, 1)[0];
    return cut || null;
  }

  // Embedded somewhere in a longer string
  const idx = trimmed.indexOf("/watch/");
  if (idx >= 0) {
    const after = trimmed.slice(idx);
    const cut = after.split(/[?#\s]/, 1)[0];
    return cut || null;
  }

  // Slug only: lagrange-the-flower-of-rin-ne-3qmw
  if (/^[a-z0-9][a-z0-9-]*$/i.test(trimmed)) {
    return `/watch/${trimmed}`;
  }

  return null;
}
