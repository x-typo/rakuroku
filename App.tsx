import { StatusBar } from "expo-status-bar";
import { NavigationContainer, DarkTheme } from "@react-navigation/native";
import { createBottomTabNavigator } from "@react-navigation/bottom-tabs";
import { Ionicons, FontAwesome, FontAwesome6 } from "@expo/vector-icons";
import {
  DiscoverScreen,
  AnimeScreen,
  MangaScreen,
  ScheduleScreen,
  ProfileScreen,
} from "./src/screens";

const Tab = createBottomTabNavigator();

export default function App() {
  return (
    <NavigationContainer theme={DarkTheme}>
      <StatusBar style="light" />
      <Tab.Navigator
        screenOptions={{
          tabBarActiveTintColor: "#3B82F6",
          tabBarInactiveTintColor: "#9CA3AF",
          headerTitleAlign: "center",
          headerStyle: { backgroundColor: "#1c1c1e" },
          headerTintColor: "#fff",
          tabBarStyle: { backgroundColor: "#1c1c1e" },
          tabBarShowLabel: false,
        }}
      >
        <Tab.Screen
          name="Discover"
          component={DiscoverScreen}
          options={{
            tabBarIcon: ({ color }) => (
              <FontAwesome name="search" size={24} color={color} />
            ),
          }}
        />
        <Tab.Screen
          name="Anime"
          component={AnimeScreen}
          options={{
            tabBarIcon: ({ color }) => (
              <Ionicons name="tv" size={24} color={color} />
            ),
          }}
        />
        <Tab.Screen
          name="Manga"
          component={MangaScreen}
          options={{
            tabBarIcon: ({ color }) => (
              <FontAwesome6 name="book-open" size={24} color={color} />
            ),
          }}
        />
        <Tab.Screen
          name="Schedule"
          component={ScheduleScreen}
          options={{
            tabBarIcon: ({ color }) => (
              <Ionicons name="calendar" size={24} color={color} />
            ),
          }}
        />
        <Tab.Screen
          name="Profile"
          component={ProfileScreen}
          options={{
            tabBarIcon: ({ color }) => (
              <Ionicons name="person" size={24} color={color} />
            ),
          }}
        />
      </Tab.Navigator>
    </NavigationContainer>
  );
}
