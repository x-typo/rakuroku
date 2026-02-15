import { createContext, useCallback, useContext, useEffect, useMemo, useState, ReactNode } from "react";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { AnimeKaiCandidate, resolveAnimeKaiWatchPathStrict, resolveAnimeKaiWatchPathStrictWithDebug } from "../providers/animekai";

type WatchPathMap = Record<string, string>;

const RESOLVED_KEY = "animekai:resolvedPathByMediaId:v1";
const OVERRIDE_KEY = "animekai:overridePathByMediaId:v1";

interface AnimeKaiContextType {
  getWatchPath: (mediaId: number) => string | null;
  getOverrideWatchPath: (mediaId: number) => string | null;
  resolveWatchPath: (params: { mediaId: number; title: string }) => Promise<string | null>;
  resolveWatchPathWithDebug: (params: { mediaId: number; title: string }) => Promise<{ watchPath: string | null; debugLog: string; candidates: AnimeKaiCandidate[] }>;
  setOverrideWatchPath: (mediaId: number, watchPath: string) => Promise<void>;
  clearOverrideWatchPath: (mediaId: number) => Promise<void>;
}

const AnimeKaiContext = createContext<AnimeKaiContextType | undefined>(undefined);

export function AnimeKaiProvider({ children }: { children: ReactNode }) {
  const [resolvedByMediaId, setResolvedByMediaId] = useState<WatchPathMap>({});
  const [overridesByMediaId, setOverridesByMediaId] = useState<WatchPathMap>({});

  useEffect(() => {
    const load = async () => {
      try {
        const [resolvedRaw, overrideRaw] = await Promise.all([
          AsyncStorage.getItem(RESOLVED_KEY),
          AsyncStorage.getItem(OVERRIDE_KEY),
        ]);

        if (resolvedRaw) {
          const parsed = JSON.parse(resolvedRaw) as unknown;
          if (parsed && typeof parsed === "object") {
            setResolvedByMediaId(parsed as WatchPathMap);
          }
        }

        if (overrideRaw) {
          const parsed = JSON.parse(overrideRaw) as unknown;
          if (parsed && typeof parsed === "object") {
            setOverridesByMediaId(parsed as WatchPathMap);
          }
        }
      } catch {
        // Ignore storage errors; app will re-resolve as needed
      }
    };

    void load();
  }, []);

  const persistResolved = useCallback((next: WatchPathMap) => {
    void AsyncStorage.setItem(RESOLVED_KEY, JSON.stringify(next));
  }, []);

  const persistOverrides = useCallback((next: WatchPathMap) => {
    void AsyncStorage.setItem(OVERRIDE_KEY, JSON.stringify(next));
  }, []);

  const getOverrideWatchPath = useCallback(
    (mediaId: number): string | null => {
      return overridesByMediaId[String(mediaId)] ?? null;
    },
    [overridesByMediaId]
  );

  const getWatchPath = useCallback(
    (mediaId: number): string | null => {
      const key = String(mediaId);
      return overridesByMediaId[key] ?? resolvedByMediaId[key] ?? null;
    },
    [overridesByMediaId, resolvedByMediaId]
  );

  const resolveWatchPath = useCallback(
    async (params: { mediaId: number; title: string }): Promise<string | null> => {
      const key = String(params.mediaId);

      const override = overridesByMediaId[key];
      if (override) return override;

      const cached = resolvedByMediaId[key];
      if (cached) return cached;

      let resolved: string | null = null;
      try {
        resolved = await resolveAnimeKaiWatchPathStrict({
          anilistId: params.mediaId,
          title: params.title,
        });
      } catch {
        return null;
      }

      if (resolved) {
        setResolvedByMediaId((prev) => {
          const next = { ...prev, [key]: resolved };
          persistResolved(next);
          return next;
        });
      }

      return resolved;
    },
    [overridesByMediaId, resolvedByMediaId, persistResolved]
  );

  const resolveWatchPathWithDebug = useCallback(
    async (params: { mediaId: number; title: string }): Promise<{ watchPath: string | null; debugLog: string; candidates: AnimeKaiCandidate[] }> => {
      const key = String(params.mediaId);

      const override = overridesByMediaId[key];
      if (override) {
        return {
          watchPath: override,
          debugLog: `[AnimeKai] override hit mediaId=${params.mediaId} path=${override}`,
          candidates: [],
        };
      }

      const cached = resolvedByMediaId[key];
      if (cached) {
        return { watchPath: cached, debugLog: `[AnimeKai] cache hit mediaId=${params.mediaId} path=${cached}`, candidates: [] };
      }

      try {
        const resolved = await resolveAnimeKaiWatchPathStrictWithDebug({
          anilistId: params.mediaId,
          title: params.title,
        });

        if (resolved.watchPath) {
          setResolvedByMediaId((prev) => {
            const next = { ...prev, [key]: resolved.watchPath as string };
            persistResolved(next);
            return next;
          });
        }

        return resolved;
      } catch (err) {
        return {
          watchPath: null,
          debugLog: `[AnimeKai] resolveWatchPathWithDebug failed: ${
            err instanceof Error ? err.message : String(err)
          }`,
          candidates: [],
        };
      }
    },
    [overridesByMediaId, resolvedByMediaId, persistResolved]
  );

  const setOverrideWatchPath = useCallback(
    async (mediaId: number, watchPath: string) => {
      const key = String(mediaId);
      setOverridesByMediaId((prev) => {
        const next = { ...prev, [key]: watchPath };
        persistOverrides(next);
        return next;
      });
    },
    [persistOverrides]
  );

  const clearOverrideWatchPath = useCallback(
    async (mediaId: number) => {
      const key = String(mediaId);
      setOverridesByMediaId((prev) => {
        if (!prev[key]) return prev;
        const { [key]: _removed, ...rest } = prev;
        persistOverrides(rest);
        return rest;
      });
    },
    [persistOverrides]
  );

  const value = useMemo<AnimeKaiContextType>(
    () => ({
      getWatchPath,
      getOverrideWatchPath,
      resolveWatchPath,
      resolveWatchPathWithDebug,
      setOverrideWatchPath,
      clearOverrideWatchPath,
    }),
    [
      getWatchPath,
      getOverrideWatchPath,
      resolveWatchPath,
      resolveWatchPathWithDebug,
      setOverrideWatchPath,
      clearOverrideWatchPath,
    ]
  );

  return <AnimeKaiContext.Provider value={value}>{children}</AnimeKaiContext.Provider>;
}

export function useAnimeKai() {
  const context = useContext(AnimeKaiContext);
  if (!context) {
    throw new Error("useAnimeKai must be used within an AnimeKaiProvider");
  }
  return context;
}
