import { useSyncExternalStore } from "react";

type MuseStatus = { signedIn: boolean; message: string };
let state: MuseStatus = { signedIn: false, message: "checking usage..." };
const listeners = new Set<() => void>();

export function useMuseQuota() {
  return useSyncExternalStore(
    (listener) => { listeners.add(listener); return () => listeners.delete(listener); },
    () => state,
  );
}

export async function fetchMuseQuota() {
  state = await window.babyMenu!.capabilities.invoke<MuseStatus>("muse-quota", "getQuota");
  for (const listener of listeners) listener();
}
