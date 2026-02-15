import {
  buildAnimeKaiEpisodeUrl,
  extractCandidatesFromSearchHtml,
  extractWatchPathsFromSearchHtml,
  normalizeAnimeKaiWatchPathInput,
  resolveAnimeKaiWatchPathStrictWithDebug,
} from "./animekai";

describe("normalizeAnimeKaiWatchPathInput", () => {
  test("returns pathname for full URL", () => {
    expect(
      normalizeAnimeKaiWatchPathInput("https://animekai.to/watch/lagrange-the-flower-of-rin-ne-3qmw#ep=2")
    ).toBe("/watch/lagrange-the-flower-of-rin-ne-3qmw");
  });

  test("returns cleaned path for /watch input", () => {
    expect(normalizeAnimeKaiWatchPathInput("/watch/foo-bar?x=1")).toBe("/watch/foo-bar");
  });

  test("parses slug-only input", () => {
    expect(normalizeAnimeKaiWatchPathInput("foo-bar")).toBe("/watch/foo-bar");
  });

  test("returns null for invalid input", () => {
    expect(normalizeAnimeKaiWatchPathInput("not a url")).toBeNull();
  });
});

describe("buildAnimeKaiEpisodeUrl", () => {
  test("builds full episode URL from watch path", () => {
    expect(buildAnimeKaiEpisodeUrl("/watch/foo-bar", 7)).toBe("https://animekai.to/watch/foo-bar#ep=7");
  });
});

describe("extractWatchPathsFromSearchHtml", () => {
  test("extracts paths from standard hrefs", () => {
    const html = `<a href="/watch/a-1"></a><a href='/watch/b-2'></a>`;
    expect(extractWatchPathsFromSearchHtml(html)).toEqual(["/watch/a-1", "/watch/b-2"]);
  });

  test("extracts paths from escaped slashes and unicode escapes", () => {
    const html = `href="\\/watch\\/a-1" href="\\u002Fwatch\\u002Fb-2"`;
    expect(extractWatchPathsFromSearchHtml(html)).toEqual(["/watch/a-1", "/watch/b-2"]);
  });
});

describe("extractCandidatesFromSearchHtml", () => {
  test("extracts candidates with titles when present", () => {
    const html =
      `<a href="/watch/a-1" class="poster"></a>` +
      `<a class="title" title="Show A">Show A</a>` +
      `<a href="/watch/b-2" class="poster"></a>` +
      `<a class="title" title="Show B">Show B</a>`;

    expect(extractCandidatesFromSearchHtml(html)).toEqual([
      { watchPath: "/watch/a-1", title: "Show A" },
      { watchPath: "/watch/b-2", title: "Show B" },
    ]);
  });
});

describe("resolveAnimeKaiWatchPathStrictWithDebug", () => {
  const realFetch = global.fetch;

  afterEach(() => {
    global.fetch = realFetch;
  });

  test("resolves when a candidate watch page contains the AniList id", async () => {
    const searchHtml =
      `<a href="/watch/a-1" class="poster"></a>` +
      `<a class="title" title="Show A">Show A</a>` +
      `<a href="/watch/b-2" class="poster"></a>` +
      `<a class="title" title="Show B">Show B</a>`;

    global.fetch = jest.fn(async (url: string) => {
      if (url.startsWith("https://animekai.to/browser?keyword=")) {
        return { ok: true, status: 200, text: async () => searchHtml } as any;
      }
      if (url === "https://animekai.to/watch/a-1") {
        return { ok: true, status: 200, text: async () => `<a href="https://anilist.co/anime/123"></a>` } as any;
      }
      if (url === "https://animekai.to/watch/b-2") {
        return { ok: true, status: 200, text: async () => `<a href="https://anilist.co/anime/999"></a>` } as any;
      }
      return { ok: false, status: 404, text: async () => "" } as any;
    }) as any;

    const res = await resolveAnimeKaiWatchPathStrictWithDebug({ anilistId: 123, title: "Show A", maxCandidates: 5 });
    expect(res.watchPath).toBe("/watch/a-1");
    expect(res.candidates.length).toBeGreaterThan(0);
  });

  test("returns null when no candidates match", async () => {
    const searchHtml = `<a href="/watch/a-1" class="poster"></a><a class="title">Show A</a>`;

    global.fetch = jest.fn(async (url: string) => {
      if (url.startsWith("https://animekai.to/browser?keyword=")) {
        return { ok: true, status: 200, text: async () => searchHtml } as any;
      }
      if (url === "https://animekai.to/watch/a-1") {
        return { ok: true, status: 200, text: async () => `<div>no anilist id</div>` } as any;
      }
      return { ok: false, status: 404, text: async () => "" } as any;
    }) as any;

    const res = await resolveAnimeKaiWatchPathStrictWithDebug({ anilistId: 999, title: "Show A", maxCandidates: 5 });
    expect(res.watchPath).toBeNull();
    expect(res.candidates).toEqual([{ watchPath: "/watch/a-1", title: "Show A" }]);
  });
});

