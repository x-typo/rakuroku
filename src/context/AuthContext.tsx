import { createContext, useContext, useState, useEffect, useCallback, ReactNode } from "react";
import * as SecureStore from "expo-secure-store";
import * as WebBrowser from "expo-web-browser";

WebBrowser.maybeCompleteAuthSession();

const ANILIST_AUTH_URL = "https://anilist.co/api/v2/oauth/authorize";
const CLIENT_ID = process.env.EXPO_PUBLIC_ANILIST_CLIENT_ID || "";
const TOKEN_KEY = "anilist_access_token";

interface AuthContextType {
  accessToken: string | null;
  isLoading: boolean;
  isAuthenticated: boolean;
  login: () => Promise<void>;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [accessToken, setAccessToken] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  // Use custom scheme directly for native builds
  const redirectUri = "rakuroku://";

  // Log the redirect URI for setting up AniList OAuth
  useEffect(() => {
    console.log("OAuth Redirect URI:", redirectUri);
  }, []);

  useEffect(() => {
    loadToken();
  }, []);

  const loadToken = async () => {
    try {
      const token = await SecureStore.getItemAsync(TOKEN_KEY);
      setAccessToken(token);
    } catch (error) {
      console.error("Failed to load token:", error);
    } finally {
      setIsLoading(false);
    }
  };

  const login = useCallback(async () => {
    if (!CLIENT_ID) {
      console.error("EXPO_PUBLIC_ANILIST_CLIENT_ID is not set");
      return;
    }

    try {
      // AniList implicit flow doesn't use redirect_uri in the auth URL
      // The redirect is configured in the AniList app settings
      const authUrl = `${ANILIST_AUTH_URL}?client_id=${CLIENT_ID}&response_type=token`;

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
          }
        }
      }
    } catch (error) {
      console.error("Login failed:", error);
    }
  }, [redirectUri]);

  const logout = useCallback(async () => {
    try {
      await SecureStore.deleteItemAsync(TOKEN_KEY);
      setAccessToken(null);
    } catch (error) {
      console.error("Logout failed:", error);
    }
  }, []);

  return (
    <AuthContext.Provider
      value={{
        accessToken,
        isLoading,
        isAuthenticated: !!accessToken,
        login,
        logout,
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
