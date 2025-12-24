import { useState } from "react";
import { StatusBar } from "expo-status-bar";
import { NavigationContainer, DarkTheme } from "@react-navigation/native";
import { createBottomTabNavigator } from "@react-navigation/bottom-tabs";
import { Ionicons, FontAwesome } from "@expo/vector-icons";
import {
  DiscoverScreen,
  AnimeScreen,
  MangaScreen,
  ScheduleScreen,
  ProfileScreen,
} from "./src/screens";
import { colors } from "./src/constants";

const Tab = createBottomTabNavigator();

export default function App() {
  const [showAnimeFilter, setShowAnimeFilter] = useState(false);
  const [showMangaFilter, setShowMangaFilter] = useState(false);

  return (
    <NavigationContainer theme={DarkTheme}>
      <StatusBar style="light" />
      <Tab.Navigator
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
    </NavigationContainer>
  );
}
