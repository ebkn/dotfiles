// The bridge plugin itself is one registration: the logic lives in
// bridge.mjs so the node suite can drive it without importing the plugin
// host. @opencode/plugin is resolved by OpenCode itself for local plugins —
// the loader refuses to give a plugin any other runtime module, so there is
// no package.json here to install it into.
import { Plugin } from "@opencode/plugin"
import { registerGuardBridge } from "./bridge.mjs"

export default Plugin.define({
  id: "guard-bridge",
  setup(ctx) {
    return registerGuardBridge(ctx)
  },
})
