chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type !== "carbonyl-fixture-ping") {
    return false;
  }

  chrome.storage.local.get({launchCount: 0}).then(({launchCount}) => {
    const nextLaunchCount = launchCount + 1;
    return chrome.storage.local.set({launchCount: nextLaunchCount}).then(() => {
      sendResponse({worker: "ready", launchCount: nextLaunchCount});
    });
  });
  return true;
});

chrome.runtime.onConnect.addListener(port => {
  if (port.name !== "carbonyl-fixture-port") {
    return;
  }
  port.onMessage.addListener(message => {
    if (message?.type === "carbonyl-fixture-port-ping") {
      port.postMessage({port: "ready"});
    }
  });
});

chrome.action.setTitle({title: "Carbonyl fixture action ready"});
chrome.action.setBadgeText({text: "QA"});
