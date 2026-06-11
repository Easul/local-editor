const HOST_NAME = "local_editor";

function sendNative(payload) {
  return browser.runtime.sendNativeMessage(HOST_NAME, payload);
}

browser.runtime.onMessage.addListener((message) => {
  if (!message || typeof message !== "object") {
    return undefined;
  }

  if (message.type === "local-editor-native") {
    return sendNative(message.payload);
  }

  return undefined;
});
