import { StyleSheet, Text, View } from "react-native";

export default function MangaScreen() {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>Manga</Text>
      <Text style={styles.subtitle}>Your manga list will appear here</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: "#000",
    alignItems: "center",
    justifyContent: "center",
  },
  title: {
    fontSize: 24,
    fontWeight: "bold",
    marginBottom: 8,
    color: "#fff",
  },
  subtitle: {
    fontSize: 16,
    color: "#9CA3AF",
  },
});
