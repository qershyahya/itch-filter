// onboarding page: give the administrator a way into the (key-protected) settings
document.getElementById("cf-admin").addEventListener("click", (e) => {
  e.preventDefault();
  if (chrome.runtime.openOptionsPage) chrome.runtime.openOptionsPage();
  else window.open(chrome.runtime.getURL("options.html"));
});
