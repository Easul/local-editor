const HOST_NAME = "local_editor";

function sendNative(payload) {
  return new Promise((resolve, reject) => {
    chrome.runtime.sendNativeMessage(HOST_NAME, payload, (response) => {
      const error = chrome.runtime.lastError;
      if (error) {
        reject(new Error(error.message));
        return;
      }

      resolve(response);
    });
  });
}

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (!message || typeof message !== "object") {
    return undefined;
  }

  if (message.type === "local-editor-native") {
    sendNative(message.payload)
      .then((response) => sendResponse(response))
      .catch((error) => sendResponse({ error: error.message }));
    return true;
  }

  return undefined;
});
