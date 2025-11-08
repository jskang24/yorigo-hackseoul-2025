import { Tabs } from "expo-router";
import { Text, TextInput } from "react-native";
import { useFonts } from "expo-font";
import {
  Inter_400Regular,
  Inter_500Medium,
  Inter_600SemiBold,
  Inter_700Bold,
} from "@expo-google-fonts/inter";

export default function RootLayout() {
  const [fontsLoaded] = useFonts({
    Inter_400Regular,
    Inter_500Medium,
    Inter_600SemiBold,
    Inter_700Bold,
  });

  if (!fontsLoaded) return null;

  // Set global default fonts (cast to any to avoid TS error on defaultProps)
  const RNText = Text as any;
  const RNTextInput = TextInput as any;
  if (!RNText.defaultProps) RNText.defaultProps = {};
  if (!RNTextInput.defaultProps) RNTextInput.defaultProps = {};
  RNText.defaultProps.style = [RNText.defaultProps.style, { fontFamily: "Inter_400Regular" }].filter(Boolean);
  RNTextInput.defaultProps.style = [RNTextInput.defaultProps.style, { fontFamily: "Inter_400Regular" }].filter(Boolean);

  return (
    <Tabs
      screenOptions={{
        headerShown: false,
        tabBarStyle: { display: 'none' }, // Hide default tab bar since we have custom one
      }}
    />
  );
}
