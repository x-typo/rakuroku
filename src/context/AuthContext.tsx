import { createContext, useContext, useState, useEffect, useCallback, ReactNode } from "react";
import * as SecureStore from "expo-secure-store";
import * as WebBrowser from "expo-web-browser";
import { makeRedirectUri } from "expo-auth-session";

WebBrowser.maybeCompleteAuthSession();

const ANILIST_AUTH_URL = "https://anilist.co/api/v2/oauth/authorize";
const CLIENT_ID = process.env.EXPO_PUBLIC_ANILIST_CLIENT_ID || "";
const TOKEN_KEY = "anilist_access_token";

interface AuthContextType {
  accessToken: string | null;
  isLoading: boolean;
  isAuthenticated: boolean;
  authError: string | null;
  login: () => Promise<void>;
  logout: () => Promise<void>;
  setManualToken: (token: string) => Promise<void>;
  clearAuthError: () => void;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [accessToken, setAccessToken] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [authError, setAuthError] = useState<string | null>(null);

  useEffect(() => {
    loadToken();
  }, []);

  const loadToken = async () => {
    try {
      const token = await SecureStore.getItemAsync(TOKEN_KEY);
      setAccessToken(token);
    } catch {
      // Token load failed, user will need to login
    } finally {
      setIsLoading(false);
    }
  };

  const login = useCallback(async () => {
    if (!CLIENT_ID) {
      setAuthError("Missing AniList client id (EXPO_PUBLIC_ANILIST_CLIENT_ID).");
      return;
    }

    try {
      setAuthError(null);

      const redirectUri = makeRedirectUri({
        scheme: "rakuroku",
        path: "auth",
        native: "rakuroku://auth",
      });
      const isDev = Boolean((globalThis as any).__DEV__);
      if (isDev) {
        console.log(`[Auth] redirectUri=${redirectUri}`);
      }

      const authUrl =
        `${ANILIST_AUTH_URL}?client_id=${encodeURIComponent(CLIENT_ID)}` +
        `&response_type=token&redirect_uri=${encodeURIComponent(redirectUri)}`;

      const result = await WebBrowser.openAuthSessionAsync(authUrl, redirectUri);

      if (result.type === "success" && result.url) {
        // AniList returns token in URL fragment: #access_token=xxx&token_type=Bearer&expires_in=xxx
        const url = result.url;
        const fragmentIndex = url.indexOf("#");
        if (fragmentIndex !== -1) {
          const fragment = url.substring(fragmentIndex + 1);
          const params = new URLSearchParams(fragment);
          const token = params.get("access_token");

          if (token) {
            await SecureStore.setItemAsync(TOKEN_KEY, token);
            setAccessToken(token);
            return;
          }
        }
        setAuthError("AniList login succeeded but access token was missing.");
        return;
      }
      if (result.type === "cancel" || result.type === "dismiss") {
        setAuthError("Login cancelled.");
        return;
      }
      setAuthError(`Login failed (${result.type}).`);
    } catch {
      setAuthError("Login failed. Try again or use manual token paste.");
    }
  }, []);

  const logout = useCallback(async () => {
    try {
      await SecureStore.deleteItemAsync(TOKEN_KEY);
      setAccessToken(null);
    } catch {
      // Logout failed silently
    }
  }, []);

  const setManualToken = useCallback(async (token: string) => {
    const normalized = token.trim();
    if (!normalized) {
      setAuthError("Token cannot be empty.");
      return;
    }
    try {
      await SecureStore.setItemAsync(TOKEN_KEY, normalized);
      setAccessToken(normalized);
      setAuthError(null);
    } catch {
      setAuthError("Failed to save token.");
    }
  }, []);

  const clearAuthError = useCallback(() => setAuthError(null), []);

  return (
    <AuthContext.Provider
      value={{
        accessToken,
        isLoading,
        isAuthenticated: !!accessToken,
        authError,
        login,
        logout,
        setManualToken,
        clearAuthError,
      }}
    >
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error("useAuth must be used within an AuthProvider");
  }
  return context;
}
