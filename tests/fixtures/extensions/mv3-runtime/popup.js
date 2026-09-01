document.documentElement.dataset.carbonylExtensionPopup = "ready";
document.querySelector("#popup-action").addEventListener("click", () => {
  document.documentElement.dataset.carbonylExtensionPopupClicked = "true";
  document.body.style.background = "rgb(32, 160, 80)";
});
