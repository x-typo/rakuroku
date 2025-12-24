import {
  StyleSheet,
  Text,
  View,
  Modal,
  TouchableOpacity,
  Pressable,
} from "react-native";
import { colors } from "../constants";

interface FilterModalProps<T extends string> {
  visible: boolean;
  onClose: () => void;
  title: string;
  filters: readonly T[];
  selectedFilter: T;
  onSelectFilter: (filter: T) => void;
}

export function FilterModal<T extends string>({
  visible,
  onClose,
  title,
  filters,
  selectedFilter,
  onSelectFilter,
}: FilterModalProps<T>) {
  return (
    <Modal
      visible={visible}
      transparent
      animationType="fade"
      onRequestClose={onClose}
    >
      <Pressable style={styles.overlay} onPress={onClose}>
        <View style={styles.content}>
          <Text style={styles.title}>{title}</Text>
          {filters.map((filter) => (
            <TouchableOpacity
              key={filter}
              style={[
                styles.option,
                selectedFilter === filter && styles.optionSelected,
              ]}
              onPress={() => onSelectFilter(filter)}
            >
              <Text
                style={[
                  styles.optionText,
                  selectedFilter === filter && styles.optionTextSelected,
                ]}
              >
                {filter}
              </Text>
            </TouchableOpacity>
          ))}
        </View>
      </Pressable>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: colors.overlay,
    justifyContent: "flex-end",
  },
  content: {
    backgroundColor: colors.surface,
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    paddingTop: 20,
    paddingBottom: 40,
    paddingHorizontal: 16,
  },
  title: {
    fontSize: 20,
    fontWeight: "bold",
    color: colors.textPrimary,
    textAlign: "center",
    marginBottom: 20,
  },
  option: {
    paddingVertical: 16,
    paddingHorizontal: 16,
    borderRadius: 10,
  },
  optionSelected: {
    backgroundColor: colors.primary,
  },
  optionText: {
    fontSize: 18,
    color: colors.textPrimary,
  },
  optionTextSelected: {
    fontWeight: "bold",
  },
});
