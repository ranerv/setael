(function () {
  const storageKey = "activity-logs";
  const maxEntries = 1000;
  const page = window.location.pathname.split("/").pop() || "index.html";

  function readLogs() {
    const storedLogs = window.localStorage.getItem(storageKey);
    const logs = storedLogs ? JSON.parse(storedLogs) : [];
    if (!Array.isArray(logs)) {
      throw new Error("Saved activity logs are not in the expected format.");
    }
    return logs;
  }

  window.logActivity = function (action, target) {
    try {
      const logs = readLogs();
      logs.push({
        timestamp: new Date().toISOString(),
        action: action,
        page: page,
        target: typeof target === "string" ? target.slice(0, 100) : ""
      });
      window.localStorage.setItem(storageKey, JSON.stringify(logs.slice(-maxEntries)));
      window.dispatchEvent(new CustomEvent("activitylogchange"));
    } catch (error) {
      console.error("Could not save the activity log.", error);
    }
  };

  document.addEventListener("click", function (event) {
    const clicked = event.target instanceof Element ? event.target : null;
    const control = clicked && clicked.closest("button, a, [role='button']");
    if (!control || control.closest("label") || control.matches(":disabled")) {
      return;
    }

    const label = control.getAttribute("aria-label") ||
      control.getAttribute("title") ||
      control.textContent.trim().replace(/\s+/g, " ");
    window.logActivity("Click", label || control.tagName.toLowerCase());
  });
}());
