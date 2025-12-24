import { StyleSheet, View, ActivityIndicator } from "react-native";
import { colors } from "../constants";

export function LoadingState() {
  return (
    <View style={styles.container}>
      <ActivityIndicator size="large" color={colors.primary} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    paddingVertical: 100,
  },
});
