chrome.runtime.sendMessage({type: "carbonyl-fixture-ping"}, response => {
  document.documentElement.dataset.carbonylExtensionContent = "loaded";
  document.documentElement.dataset.carbonylExtensionWorker = response?.worker;
  document.documentElement.dataset.carbonylExtensionStorage = String(
    response?.launchCount,
  );
});

const port = chrome.runtime.connect({name: "carbonyl-fixture-port"});
port.onMessage.addListener(message => {
  document.documentElement.dataset.carbonylExtensionPort = message?.port;
  port.disconnect();
});
port.postMessage({type: "carbonyl-fixture-port-ping"});
