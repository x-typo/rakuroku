import { StyleSheet, View, TextInput, TouchableOpacity, Keyboard, useColorScheme } from "react-native";
import { Ionicons } from "@expo/vector-icons";
import { colors } from "../constants";

interface SearchBarProps {
  value: string;
  onChangeText: (text: string) => void;
  onClear: () => void;
  autoFocus?: boolean;
}

export function SearchBar({
  value,
  onChangeText,
  onClear,
  autoFocus = false,
}: SearchBarProps) {
  const colorScheme = useColorScheme();

  return (
    <View style={styles.container}>
      <TextInput
        style={styles.input}
        placeholder="Search"
        placeholderTextColor={colors.textSecondary}
        value={value}
        onChangeText={onChangeText}
        autoFocus={autoFocus}
        returnKeyType="search"
        onSubmitEditing={() => Keyboard.dismiss()}
        keyboardAppearance={colorScheme === "dark" ? "dark" : "light"}
      />
      {value.length > 0 && (
        <TouchableOpacity style={styles.clearButton} onPress={onClear}>
          <Ionicons name="close-circle" size={20} color={colors.textSecondary} />
        </TouchableOpacity>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: "row",
    alignItems: "center",
    marginHorizontal: 16,
    marginBottom: 8,
  },
  input: {
    flex: 1,
    backgroundColor: colors.surface,
    color: colors.textPrimary,
    paddingHorizontal: 16,
    paddingVertical: 12,
    paddingRight: 40,
    borderRadius: 10,
    fontSize: 16,
  },
  clearButton: {
    position: "absolute",
    right: 12,
    top: 0,
    bottom: 0,
    justifyContent: "center",
  },
});
