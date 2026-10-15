import net from "net";

const DEFAULT_BRIDGE_PORT = 6008;
const DEFAULT_HOST = "127.0.0.1";
const TIMEOUT_MS = 2000;

/**
 * Send a JSON-RPC / JSON command to Godot Editor Bridge via TCP
 */
export async function sendCommandToEditor(command, payload = {}, port = DEFAULT_BRIDGE_PORT) {
  return new Promise((resolve) => {
    const socket = new net.Socket();
    let receivedData = "";
    let isResolved = false;

    socket.setTimeout(TIMEOUT_MS);

    socket.connect(port, DEFAULT_HOST, () => {
      const message = JSON.stringify({ command, payload }) + "\n";
      socket.write(message);
    });

    socket.on("data", (data) => {
      receivedData += data.toString("utf-8");
      if (receivedData.includes("\n")) {
        try {
          const parsed = JSON.parse(receivedData.trim());
          isResolved = true;
          socket.destroy();
          resolve({ success: true, connected: true, response: parsed });
        } catch (err) {
          isResolved = true;
          socket.destroy();
          resolve({ success: false, connected: true, error: "Invalid JSON from editor: " + err.message });
        }
      }
    });

    socket.on("timeout", () => {
      if (!isResolved) {
        isResolved = true;
        socket.destroy();
        resolve({
          success: false,
          connected: false,
          error: "Godot Editor Bridge connection timed out (is Godot editor open with the addon enabled?)"
        });
      }
    });

    socket.on("error", (err) => {
      if (!isResolved) {
        isResolved = true;
        socket.destroy();
        resolve({
          success: false,
          connected: false,
          error: `Godot Editor Bridge offline (${err.code || err.message}). Fallback to direct file mode.`
        });
      }
    });
  });
}
