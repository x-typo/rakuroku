import { StyleSheet, Text, View } from "react-native";
import { colors } from "../constants";

interface EmptyStateProps {
  message: string;
}

export function EmptyState({ message }: EmptyStateProps) {
  return (
    <View style={styles.container}>
      <Text style={styles.text}>{message}</Text>
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
  text: {
    fontSize: 16,
    color: colors.textSecondary,
  },
});
