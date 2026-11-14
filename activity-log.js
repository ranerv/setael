(function () {
  const config = window.ACTIVITY_LOG_CONFIG || {};
  const supabaseUrl = typeof config.supabaseUrl === "string"
    ? config.supabaseUrl.replace(/\/+$/, "")
    : "";
  const publishableKey = typeof config.publishableKey === "string"
    ? config.publishableKey.trim()
    : "";
  const page = window.location.pathname.split("/").pop() || "index.html";
  const isConfigured = supabaseUrl.startsWith("https://") &&
    !supabaseUrl.includes("YOUR-PROJECT-REF") &&
    publishableKey &&
    !publishableKey.includes("YOUR_SUPABASE_PUBLISHABLE_KEY");
  let configurationWarningShown = false;

  window.ACTIVITY_LOG_READY = isConfigured;

  function reportFailure(error) {
    console.error("Could not save the shared activity log.", error);
    window.dispatchEvent(new CustomEvent("activitylogerror", {
      detail: "This event could not be sent to the shared activity log."
    }));
  }

  async function getDeviceModel() {
    const userAgentData = navigator.userAgentData;
    if (!userAgentData || typeof userAgentData.getHighEntropyValues !== "function") {
      return "unknown";
    }

    try {
      const details = await userAgentData.getHighEntropyValues(["model"]);
      return typeof details.model === "string" && details.model.trim()
        ? details.model.trim().slice(0, 100)
        : "unknown";
    } catch (error) {
      console.warn("Could not read device model from browser.", error);
      return "unknown";
    }
  }

  window.logActivity = async function (action, target) {
    if (action === "Login succeeded" && typeof window.gtag === "function") {
      window.gtag("event", "login", {
        method: "site_password"
      });
    }

    if (!isConfigured) {
      if (!configurationWarningShown) {
        configurationWarningShown = true;
        reportFailure(new Error("Add the Supabase project URL and publishable key to activity-log-config.js."));
      }
      return false;
    }

    const deviceModel = await getDeviceModel();
    const record = {
      action: action,
      page: page,
      target: typeof target === "string" ? target.slice(0, 100) : "",
      device_model: deviceModel
    };

    try {
      const response = await fetch(supabaseUrl + "/rest/v1/activity_logs", {
        method: "POST",
        headers: {
          apikey: publishableKey,
          "Content-Type": "application/json",
          Prefer: "return=minimal"
        },
        body: JSON.stringify(record),
        keepalive: true
      });
      if (!response.ok) {
        throw new Error(`Activity log request failed (${response.status}): ${await response.text()}`);
      }
      window.dispatchEvent(new CustomEvent("activitylogchange"));
      return true;
    } catch (error) {
      reportFailure(error);
      return false;
    }
  };

  document.addEventListener("click", function (event) {
    const clicked = event.target instanceof Element ? event.target : null;
    const control = clicked && clicked.closest("button, a, [role='button']");
    if (!control || control.closest("label") || control.matches(":disabled")) {
      return;
    }

    const label = control.getAttribute("data-log-target") ||
      control.getAttribute("aria-label") ||
      control.getAttribute("title") ||
      control.textContent.trim().replace(/\s+/g, " ");
    window.logActivity("Click", label || control.tagName.toLowerCase());
  });
}());
