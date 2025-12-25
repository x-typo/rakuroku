import { useState } from "react";
import { StatusBar } from "expo-status-bar";
import { NavigationContainer, DarkTheme } from "@react-navigation/native";
import { createBottomTabNavigator } from "@react-navigation/bottom-tabs";
import { createNativeStackNavigator } from "@react-navigation/native-stack";
import { GestureHandlerRootView } from "react-native-gesture-handler";
import { Ionicons, FontAwesome } from "@expo/vector-icons";
import {
  DiscoverScreen,
  AnimeScreen,
  MangaScreen,
  ScheduleScreen,
  ProfileScreen,
  MediaDetailScreen,
  StudioScreen,
  SeasonListScreen,
} from "./src/screens";
import { colors } from "./src/constants";
import { AuthProvider } from "./src/context";

import { Season } from "./src/types";

export type TabParamList = {
  Discover: undefined;
  Anime: undefined;
  Manga: undefined;
  Schedule: undefined;
  Profile: undefined;
};

export type RootStackParamList = {
  MainTabs: undefined;
  MediaDetail: { mediaId: number };
  Studio: { studioId: number; studioName: string };
  SeasonList: { season: Season; year: number; label: string };
};

const Tab = createBottomTabNavigator<TabParamList>();
const Stack = createNativeStackNavigator<RootStackParamList>();

function MainTabs() {
  const [showAnimeFilter, setShowAnimeFilter] = useState(false);
  const [showMangaFilter, setShowMangaFilter] = useState(false);

  return (
    <Tab.Navigator
      initialRouteName="Anime"
      screenOptions={{
        tabBarActiveTintColor: colors.primary,
        tabBarInactiveTintColor: colors.textSecondary,
        headerTitleAlign: "center",
        headerStyle: { backgroundColor: colors.surface },
        headerTintColor: colors.textPrimary,
        tabBarStyle: {
          backgroundColor: colors.surface,
          paddingTop: 10,
          height: 80,
        },
        tabBarShowLabel: false,
      }}
    >
      <Tab.Screen
        name="Discover"
        component={DiscoverScreen}
        options={{
          tabBarIcon: ({ color }) => (
            <FontAwesome name="search" size={30} color={color} />
          ),
        }}
      />
      <Tab.Screen
        name="Anime"
        options={{
          tabBarIcon: ({ color }) => (
            <Ionicons name="tv" size={30} color={color} />
          ),
        }}
        listeners={({ navigation }) => ({
          tabPress: (e) => {
            if (navigation.isFocused()) {
              e.preventDefault();
              setShowAnimeFilter(true);
            }
          },
        })}
      >
        {() => (
          <AnimeScreen
            showFilterModal={showAnimeFilter}
            onCloseFilterModal={() => setShowAnimeFilter(false)}
          />
        )}
      </Tab.Screen>
      <Tab.Screen
        name="Manga"
        options={{
          tabBarIcon: ({ color }) => (
            <Ionicons name="book" size={30} color={color} />
          ),
        }}
        listeners={({ navigation }) => ({
          tabPress: (e) => {
            if (navigation.isFocused()) {
              e.preventDefault();
              setShowMangaFilter(true);
            }
          },
        })}
      >
        {() => (
          <MangaScreen
            showFilterModal={showMangaFilter}
            onCloseFilterModal={() => setShowMangaFilter(false)}
          />
        )}
      </Tab.Screen>
      <Tab.Screen
        name="Schedule"
        component={ScheduleScreen}
        options={{
          tabBarIcon: ({ color }) => (
            <Ionicons name="calendar" size={30} color={color} />
          ),
        }}
      />
      <Tab.Screen
        name="Profile"
        component={ProfileScreen}
        options={{
          tabBarIcon: ({ color }) => (
            <Ionicons name="person" size={30} color={color} />
          ),
        }}
      />
    </Tab.Navigator>
  );
}

export default function App() {
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <AuthProvider>
        <NavigationContainer theme={DarkTheme}>
          <StatusBar style="light" />
          <Stack.Navigator
            screenOptions={{
              headerShown: false,
              gestureEnabled: true,
              animation: "slide_from_right",
            }}
          >
            <Stack.Screen name="MainTabs" component={MainTabs} />
            <Stack.Screen name="MediaDetail" component={MediaDetailScreen} />
            <Stack.Screen name="Studio" component={StudioScreen} />
            <Stack.Screen name="SeasonList" component={SeasonListScreen} />
          </Stack.Navigator>
        </NavigationContainer>
      </AuthProvider>
    </GestureHandlerRootView>
  );
}
