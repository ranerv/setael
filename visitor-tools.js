(() => {
  const config = window.ACTIVITY_LOG_CONFIG || {};
  const supabaseUrl = typeof config.supabaseUrl === "string" ? config.supabaseUrl.replace(/\/+$/, "") : "";
  const publishableKey = typeof config.publishableKey === "string" ? config.publishableKey.trim() : "";
  const zone = "Asia/Manila";
  const guideKey = "sachel-schedule-guide-dismissed";
  const personalScheduleKey = "sachel-personal-schedule";
  const scheduleModesKey = "sachel-schedule-modes";
  const threadTokenKey = "sachel-visitor-chat-token";
  const threadNameKey = "sachel-visitor-chat-name";
  const days = [
    { value: 1, label: "Monday" },
    { value: 2, label: "Tuesday" },
    { value: 3, label: "Wednesday" },
    { value: 4, label: "Thursday" },
    { value: 5, label: "Friday" },
    { value: 6, label: "Saturday" },
    { value: 7, label: "Sunday" }
  ];
  const scheduleState = {
    events: [], selectedDate: "", weekStart: "", modes: {},
    personalEvents: [], editingPersonalId: null, timer: null
  };
  const threadState = {
    token: "", posts: [], comments: {}, reactions: {},
    timer: null, saving: false, editingId: null,
    imagePath: null, mediaType: null
  };

  function getElement(id) { return document.getElementById(id); }

  function getPhtParts(date) {
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone: zone, year: "numeric", month: "2-digit", day: "2-digit",
      weekday: "short", hour: "2-digit", minute: "2-digit", hourCycle: "h23"
    }).formatToParts(date);
    return Object.fromEntries(parts.map((part) => [part.type, part.value]));
  }

  function phtDateKey(date) {
    const parts = getPhtParts(date);
    return `${parts.year}-${parts.month}-${parts.day}`;
  }

  function weekdayForDate(dateKey) { return new Date(`${dateKey}T12:00:00Z`).getUTCDay() || 7; }

  function addDays(dateKey, amount) {
    const date = new Date(`${dateKey}T12:00:00Z`);
    date.setUTCDate(date.getUTCDate() + amount);
    return date.toISOString().slice(0, 10);
  }

  function mondayOf(dateKey) { return addDays(dateKey, 1 - weekdayForDate(dateKey)); }

  function dateLabel(dateKey, options) {
    return new Intl.DateTimeFormat("en-PH", { timeZone: zone, ...options })
      .format(new Date(`${dateKey}T12:00:00Z`));
  }

  function timeLabel(value) {
    const [hourText, minute] = value.slice(0, 5).split(":");
    const hour = Number(hourText);
    return `${hour % 12 || 12}:${minute} ${hour < 12 ? "AM" : "PM"}`;
  }

  function minutesOf(value) {
    const [hour, minute] = value.slice(0, 5).split(":").map(Number);
    return hour * 60 + minute;
  }

  function statusFor(item, selectedDate, currentDate, currentMinutes) {
    const itemDate = item.event_date || selectedDate;
    if (itemDate < currentDate) return "done";
    if (itemDate > currentDate) return "upcoming";
    const end = minutesOf(item.end_time);
    const start = minutesOf(item.start_time);
    if (currentMinutes >= end) return "done";
    if (currentMinutes >= start) return "in-progress";
    return "upcoming";
  }

  function setStatus(element, message, isError) {
    element.textContent = message;
    element.dataset.error = isError ? "true" : "false";
  }

  function readPersonalEvents() {
    try {
      const saved = JSON.parse(localStorage.getItem(personalScheduleKey) || "[]");
      if (!Array.isArray(saved)) throw new Error("Personal schedule data has an unexpected format.");
      scheduleState.personalEvents = saved.filter((item) =>
        item && typeof item.id === "string" && typeof item.title === "string"
        && typeof item.event_date === "string" && typeof item.start_time === "string"
        && typeof item.end_time === "string"
      );
    } catch (error) {
      console.error("Could not read personal schedule reminders.", error);
      setStatus(getElement("schedule-status"), "Your saved reminders could not be read.", true);
      scheduleState.personalEvents = [];
    }
  }

  function savePersonalEvents() {
    try {
      localStorage.setItem(personalScheduleKey, JSON.stringify(scheduleState.personalEvents));
    } catch (error) {
      console.error("Could not save personal schedule reminders.", error);
      setStatus(getElement("schedule-status"), "Your reminder could not be saved in this browser.", true);
      return false;
    }
    return true;
  }

  function weeklyDate(event, dateKey) { return event.weekday === weekdayForDate(dateKey); }

  function eventsForDate(dateKey) {
    return [
      ...scheduleState.events.filter((event) => event.is_active !== false
        && (event.event_date === dateKey
          || (event.weekday !== null && event.weekday !== undefined && weeklyDate(event, dateKey))))
        .map((event) => ({ ...event, origin: "shared" })),
      ...scheduleState.personalEvents
        .filter((event) => event.event_date === dateKey)
        .map((event) => ({ ...event, origin: "personal" }))
    ].sort((a, b) => a.start_time.localeCompare(b.start_time) || a.title.localeCompare(b.title));
  }

  function eventsForSelectedDate() { return eventsForDate(scheduleState.selectedDate); }

  function readScheduleModes() {
    try {
      const saved = JSON.parse(localStorage.getItem(scheduleModesKey) || "{}");
      if (!saved || typeof saved !== "object" || Array.isArray(saved)) throw new Error("Invalid format.");
      scheduleState.modes = Object.fromEntries(Object.entries(saved).filter(([, mode]) =>
        mode === "face_to_face" || mode === "online"));
    } catch (error) {
      console.error("Could not read class-format preferences.", error);
      scheduleState.modes = {};
    }
  }

  function saveScheduleModes() {
    try {
      localStorage.setItem(scheduleModesKey, JSON.stringify(scheduleState.modes));
      setStatus(getElement("schedule-status"), "Your class format was saved on this browser and device.", false);
    } catch (error) {
      console.error("Could not save the class-format preference.", error);
    }
  }

  function createModeSelect(event) {
    const select = document.createElement("select");
    const eventId = String(event.id);
    select.className = "schedule-format-select";
    select.setAttribute("aria-label", `Choose the format for ${event.title}`);
    [["", "Choose format"], ["face_to_face", "Face to face"], ["online", "Online"]].forEach(([value, label]) => {
      const option = document.createElement("option");
      option.value = value;
      option.textContent = label;
      select.append(option);
    });
    select.value = scheduleState.modes[eventId] || "";
    select.addEventListener("change", () => {
      if (!select.value) return;
      scheduleState.modes[eventId] = select.value;
      saveScheduleModes();
      if (!getElement("page-schedule").hidden) renderSchedule();
      else renderHomeSchedule();
    });
    return select;
  }

  function formatLabel(mode) {
    if (mode === "online") return "Online";
    if (mode === "face_to_face") return "Face to face";
    return "Format not chosen";
  }

  function allocateLanes(events) {
    const laneEnds = [];
    return events.map((event) => {
      const start = minutesOf(event.start_time);
      const end = minutesOf(event.end_time);
      let lane = laneEnds.findIndex((laneEnd) => laneEnd <= start);
      if (lane < 0) lane = laneEnds.length;
      laneEnds[lane] = end;
      return { event, lane, laneCount: 0 };
    }).map((positioned) => {
      positioned.laneCount = Math.max(1, laneEnds.length);
      return positioned;
    });
  }

  function renderSchedule() {
    const timeline = getElement("schedule-timeline");
    if (!timeline) return;
    const now = new Date();
    const currentParts = getPhtParts(now);
    const todayKey = `${currentParts.year}-${currentParts.month}-${currentParts.day}`;
    const currentMinutes = Number(currentParts.hour) * 60 + Number(currentParts.minute);
    const selectedDay = weekdayForDate(scheduleState.selectedDate);

    getElement("schedule-week-label").textContent =
      `${dateLabel(scheduleState.weekStart, { month: "short", day: "numeric" })} – ${dateLabel(addDays(scheduleState.weekStart, 6), { month: "short", day: "numeric", year: "numeric" })}`;
    getElement("schedule-selected-date").textContent = dateLabel(scheduleState.selectedDate, {
      weekday: "long", month: "long", day: "numeric", year: "numeric"
    });
    getElement("schedule-current-time").textContent = `Current time in the Philippines: ${timeLabel(`${currentParts.hour}:${currentParts.minute}`)}`;

    const tabs = getElement("schedule-day-tabs");
    tabs.replaceChildren();
    days.forEach((day) => {
      const dateKey = addDays(scheduleState.weekStart, day.value - 1);
      const tab = document.createElement("button");
      tab.className = "schedule-day-tab";
      tab.type = "button";
      tab.setAttribute("role", "tab");
      tab.setAttribute("aria-selected", String(dateKey === scheduleState.selectedDate));
      tab.setAttribute("aria-label", `${day.label}, ${dateLabel(dateKey, { month: "long", day: "numeric" })}`);
      const name = document.createElement("span");
      name.textContent = day.label.slice(0, 3);
      const number = document.createElement("strong");
      number.textContent = dateLabel(dateKey, { day: "numeric" });
      tab.append(name, number);
      tab.addEventListener("click", () => { scheduleState.selectedDate = dateKey; renderSchedule(); });
      tabs.append(tab);
    });

    timeline.replaceChildren();
    const track = document.createElement("div");
    track.className = "schedule-track";
    const labels = document.createElement("div");
    labels.className = "schedule-hour-labels";
    for (let hour = 7; hour <= 19; hour += 1) {
      const label = document.createElement("span");
      label.textContent = `${hour % 12 || 12}:00 ${hour < 12 ? "AM" : "PM"}`;
      labels.append(label);
    }
    const eventArea = document.createElement("div");
    eventArea.className = "schedule-event-area";
    const items = eventsForSelectedDate();
    if (!items.length) {
      const empty = document.createElement("p");
      empty.className = "schedule-empty";
      empty.textContent = "Nothing scheduled. Add a personal reminder below if you like.";
      eventArea.append(empty);
    }
    allocateLanes(items).forEach(({ event, lane, laneCount }) => {
      const start = minutesOf(event.start_time);
      const end = minutesOf(event.end_time);
      const block = document.createElement("article");
      const itemStatus = statusFor(event, scheduleState.selectedDate, todayKey, currentMinutes);
      block.className = `schedule-event ${itemStatus}`;
      block.style.top = `${(start - 420) * 0.75}px`;
      block.style.height = `${Math.max((end - start) * 0.75, 38)}px`;
      block.style.left = `calc(${lane * 100 / laneCount}% + 4px)`;
      block.style.width = `calc(${100 / laneCount}% - 8px)`;
      const title = document.createElement("strong");
      title.textContent = event.course_code ? `${event.course_code} · ${event.title}` : event.title;
      const time = document.createElement("span");
      time.textContent = `${timeLabel(event.start_time)}–${timeLabel(event.end_time)}`;
      const details = document.createElement("span");
      details.textContent = `${event.origin === "shared" ? "" : formatLabel(event.delivery_mode)}${event.location ? `${event.origin === "shared" ? "" : " · "}${event.location}` : ""}`;
      const state = document.createElement("span");
      state.className = "schedule-event-state";
      state.textContent = itemStatus === "done" ? "Done" : itemStatus === "in-progress" ? "In progress" : "Upcoming";
      block.append(title, time);
      if (event.origin === "shared") block.append(createModeSelect(event));
      if (details.textContent) block.append(details);
      block.append(state);
      if (event.origin === "personal") {
        const actions = document.createElement("span");
        actions.className = "schedule-personal-actions";
        const edit = document.createElement("button");
        edit.type = "button"; edit.textContent = "Edit";
        edit.addEventListener("click", (e) => { e.stopPropagation(); editPersonalEvent(event.id); });
        const remove = document.createElement("button");
        remove.type = "button"; remove.textContent = "Remove";
        remove.addEventListener("click", (e) => { e.stopPropagation(); removePersonalEvent(event.id); });
        actions.append(edit, remove);
        block.append(actions);
      }
      eventArea.append(block);
    });
    if (scheduleState.selectedDate === todayKey && currentMinutes >= 420 && currentMinutes <= 1140) {
      const marker = document.createElement("span");
      marker.className = "schedule-now-marker";
      marker.setAttribute("aria-label", "Current time");
      marker.style.top = `${(currentMinutes - 420) * 0.75}px`;
      eventArea.append(marker);
    }
    track.append(labels, eventArea);
    timeline.append(track);
    getElement("schedule-day-tabs").setAttribute("aria-label", `Days of the week; ${days[selectedDay - 1].label} selected`);
    renderHomeSchedule();
  }

  function renderHomeSchedule() {
    const container = getElement("home-schedule-list");
    if (!container) return;
    const now = new Date();
    const parts = getPhtParts(now);
    const todayKey = `${parts.year}-${parts.month}-${parts.day}`;
    const currentMinutes = Number(parts.hour) * 60 + Number(parts.minute);
    getElement("home-schedule-date").textContent =
      `Current time in the Philippines: ${dateLabel(todayKey, { weekday: "long", month: "long", day: "numeric" })}, ${timeLabel(`${parts.hour}:${parts.minute}`)}`;
    container.replaceChildren();
    const todayItems = eventsForDate(todayKey);
    const currentEvent = todayItems.find((e) =>
      minutesOf(e.start_time) <= currentMinutes && currentMinutes < minutesOf(e.end_time));
    let nextEvent = null;
    for (let offset = 0; offset < 7 && !nextEvent; offset += 1) {
      const eventDate = addDays(todayKey, offset);
      nextEvent = eventsForDate(eventDate).filter((e) => {
        const s = minutesOf(e.start_time);
        if (offset > 0) return true;
        return currentEvent ? s >= minutesOf(currentEvent.end_time) : s > currentMinutes;
      }).map((e) => ({ ...e, scheduleDate: eventDate }))[0] || null;
    }
    [
      { event: currentEvent ? { ...currentEvent, scheduleDate: todayKey } : null, label: "Current", emptyTitle: "No class in progress", emptyDetails: "There is no class happening right now.", status: "in-progress" },
      { event: nextEvent, label: "Up next", emptyTitle: "No upcoming class scheduled", emptyDetails: "Check the Schedule tab for your full calendar.", status: "upcoming" }
    ].forEach(({ event, label, emptyTitle, emptyDetails, status }) => {
      const item = document.createElement("article");
      item.className = `home-schedule-item ${event ? status : "empty"}`;
      const state = document.createElement("span");
      state.className = "home-schedule-label";
      state.textContent = label;
      const description = document.createElement("div");
      const title = document.createElement("div");
      title.className = "home-schedule-title";
      const detail = document.createElement("div");
      detail.className = "home-schedule-detail";
      if (event) {
        title.textContent = event.course_code ? `${event.course_code} · ${event.title}` : event.title;
        const eventDate = event.scheduleDate === todayKey ? "" : dateLabel(event.scheduleDate, { weekday: "short", month: "short", day: "numeric" });
        const time = `${timeLabel(event.start_time)}–${timeLabel(event.end_time)}`;
        const deliveryMode = event.origin === "shared" ? scheduleState.modes[String(event.id)] : event.delivery_mode;
        detail.textContent = [eventDate, time, deliveryMode ? formatLabel(deliveryMode) : "", event.location || ""].filter(Boolean).join(" · ");
      } else { title.textContent = emptyTitle; detail.textContent = emptyDetails; }
      description.append(title, detail);
      item.append(state, description);
      container.append(item);
    });
  }

  async function loadSchedule() {
    const status = getElement("schedule-status");
    if (!supabaseUrl || !publishableKey) {
      setStatus(status, "Schedule is unavailable because the content service is not configured.", true);
      return;
    }
    try {
      const response = await fetch(
        `${supabaseUrl}/rest/v1/site_schedule_events?select=id,title,course_code,weekday,event_date,start_time,end_time,location,is_active&is_active=eq.true&order=weekday.asc,event_date.asc,start_time.asc`,
        { headers: { apikey: publishableKey } }
      );
      if (!response.ok) throw new Error(`Schedule could not be loaded (${response.status}).`);
      const events = await response.json();
      if (!Array.isArray(events)) throw new Error("The schedule returned an unexpected response.");
      scheduleState.events = events;
      setStatus(status, "", false);
    } catch (error) {
      console.error("Could not load the shared class schedule.", error);
      setStatus(status, error.message || "The shared class schedule could not be loaded.", true);
    }
    renderSchedule();
  }

  function resetPersonalForm() {
    scheduleState.editingPersonalId = null;
    getElement("personal-schedule-form").reset();
    getElement("personal-schedule-date").value = scheduleState.selectedDate;
    getElement("save-personal-schedule").textContent = "Add reminder";
    getElement("cancel-personal-schedule-edit").hidden = true;
  }

  function editPersonalEvent(id) {
    const event = scheduleState.personalEvents.find((item) => item.id === id);
    if (!event) return;
    scheduleState.editingPersonalId = id;
    getElement("personal-schedule-title").value = event.title;
    getElement("personal-schedule-date").value = event.event_date;
    getElement("personal-schedule-start").value = event.start_time.slice(0, 5);
    getElement("personal-schedule-end").value = event.end_time.slice(0, 5);
    getElement("personal-schedule-mode").value = event.delivery_mode || "face_to_face";
    getElement("personal-schedule-location").value = event.location || "";
    getElement("save-personal-schedule").textContent = "Save changes";
    getElement("cancel-personal-schedule-edit").hidden = false;
    getElement("personal-schedule-form").scrollIntoView({ behavior: "smooth", block: "center" });
  }

  function removePersonalEvent(id) {
    scheduleState.personalEvents = scheduleState.personalEvents.filter((e) => e.id !== id);
    if (savePersonalEvents()) {
      renderSchedule();
      setStatus(getElement("schedule-status"), "Personal reminder removed.", false);
    }
  }

  function handlePersonalScheduleSubmit(event) {
    event.preventDefault();
    const start = getElement("personal-schedule-start").value;
    const end = getElement("personal-schedule-end").value;
    const startMinutes = minutesOf(start);
    const endMinutes = minutesOf(end);
    if (startMinutes < 420 || endMinutes > 1140 || startMinutes >= endMinutes) {
      setStatus(getElement("schedule-status"), "Choose a start and end between 7:00 AM and 7:00 PM; the end must be later.", true);
      return;
    }
    const isEditing = Boolean(scheduleState.editingPersonalId);
    const updatedEvent = {
      id: scheduleState.editingPersonalId || crypto.randomUUID(),
      title: getElement("personal-schedule-title").value.trim(),
      event_date: getElement("personal-schedule-date").value,
      start_time: start, end_time: end,
      delivery_mode: getElement("personal-schedule-mode").value,
      location: getElement("personal-schedule-location").value.trim()
    };
    if (!updatedEvent.title || !updatedEvent.event_date) {
      setStatus(getElement("schedule-status"), "Enter an activity and date.", true);
      return;
    }
    if (scheduleState.editingPersonalId) {
      scheduleState.personalEvents = scheduleState.personalEvents.map((item) =>
        item.id === scheduleState.editingPersonalId ? updatedEvent : item);
    } else {
      scheduleState.personalEvents.push(updatedEvent);
    }
    if (!savePersonalEvents()) return;
    scheduleState.selectedDate = updatedEvent.event_date;
    scheduleState.weekStart = mondayOf(updatedEvent.event_date);
    resetPersonalForm();
    renderSchedule();
    setStatus(getElement("schedule-status"), "Personal reminder saved on this browser and device.", false);
    if (typeof window.logActivity === "function") {
      const target = `${updatedEvent.title} · ${updatedEvent.event_date} · ${timeLabel(start)}–${timeLabel(end)} · ${formatLabel(updatedEvent.delivery_mode)}`;
      window.logActivity(isEditing ? "Reminder updated" : "Reminder added", target);
    }
  }

  function initSchedule() {
    const todayKey = phtDateKey(new Date());
    scheduleState.selectedDate = todayKey;
    scheduleState.weekStart = mondayOf(todayKey);
    readPersonalEvents();
    readScheduleModes();
    try { if (localStorage.getItem(guideKey) !== "true") getElement("schedule-guide").hidden = false; } catch (e) {}
    getElement("personal-schedule-date").value = todayKey;
    getElement("dismiss-schedule-guide").addEventListener("click", () => {
      try { localStorage.setItem(guideKey, "true"); } catch (e) {}
      getElement("schedule-guide").hidden = true;
    });
    getElement("schedule-previous-week").addEventListener("click", () => {
      scheduleState.weekStart = addDays(scheduleState.weekStart, -7);
      scheduleState.selectedDate = scheduleState.weekStart;
      renderSchedule();
    });
    getElement("schedule-next-week").addEventListener("click", () => {
      scheduleState.weekStart = addDays(scheduleState.weekStart, 7);
      scheduleState.selectedDate = scheduleState.weekStart;
      renderSchedule();
    });
    getElement("schedule-today").addEventListener("click", () => {
      scheduleState.selectedDate = phtDateKey(new Date());
      scheduleState.weekStart = mondayOf(scheduleState.selectedDate);
      renderSchedule();
    });
    getElement("personal-schedule-form").addEventListener("submit", handlePersonalScheduleSubmit);
    getElement("cancel-personal-schedule-edit").addEventListener("click", resetPersonalForm);
    renderSchedule();
    loadSchedule();
    scheduleState.timer = window.setInterval(renderSchedule, 30000);
  }

  // ── Token & RPC ──────────────────────────────────────────────────────────

  function visitorToken() {
    if (threadState.token) return threadState.token;
    let token = localStorage.getItem(threadTokenKey);
    if (!token) {
      if (!window.crypto || typeof window.crypto.randomUUID !== "function")
        throw new Error("This browser cannot create a secure session. Please update your browser.");
      token = window.crypto.randomUUID();
      localStorage.setItem(threadTokenKey, token);
    }
    threadState.token = token;
    return token;
  }

  async function callVisitorRpc(name, payload) {
    const response = await fetch(`${supabaseUrl}/rest/v1/rpc/${name}`, {
      method: "POST",
      headers: { apikey: publishableKey, "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    });
    const text = await response.text();
    let result;
    try { result = text ? JSON.parse(text) : null; } catch (e) {
      throw new Error("The thread service returned an unexpected response.");
    }
    if (!response.ok) throw new Error((result && (result.message || result.msg)) || `The request failed (${response.status}).`);
    return result;
  }

  function readLikeResult(result) {
    const row = Array.isArray(result) ? result[0] : result;
    if (!row || !Number.isFinite(Number(row.like_count)) || typeof row.liked !== "boolean")
      throw new Error("The like service returned an unexpected response.");
    return { count: Number(row.like_count), liked: row.liked };
  }

  async function loadContentLikeStatus(contentType, contentId) {
    const result = await callVisitorRpc("get_daily_content_like_status", {
      p_visitor_token: visitorToken(), p_content_type: contentType, p_content_id: String(contentId)
    });
    return readLikeResult(result);
  }

  async function toggleContentLike(contentType, contentId) {
    const result = await callVisitorRpc("toggle_daily_content_like", {
      p_visitor_token: visitorToken(), p_content_type: contentType, p_content_id: String(contentId)
    });
    return readLikeResult(result);
  }

  async function submitVisitorCheckin(answer, message) {
    return callVisitorRpc("submit_visitor_checkin", {
      p_visitor_token: visitorToken(), p_answer: answer, p_message: message
    });
  }

  // ── Thread media ─────────────────────────────────────────────────────────

  function threadImageUrl(path) {
    return `${supabaseUrl}/storage/v1/object/public/visitor-thread-images/${path.split("/").map(encodeURIComponent).join("/")}`;
  }

  const threadMediaExtensions = {
    "image/jpeg": "jpg", "image/png": "png", "image/gif": "gif",
    "image/webp": "webp", "image/avif": "avif",
    "video/mp4": "mp4", "video/webm": "webm", "video/quicktime": "mov"
  };

  async function uploadThreadMedia(file, token) {
    if (!threadMediaExtensions[file.type]) throw new Error("Unsupported file type.");
    const isVideo = file.type.startsWith("video/");
    const maxSize = isVideo ? 100 * 1024 * 1024 : 5 * 1024 * 1024;
    if (file.size > maxSize) throw new Error(isVideo ? "Video must be 100 MB or smaller." : "Photo must be 5 MB or smaller.");
    const path = `${token}/${window.crypto.randomUUID()}.${threadMediaExtensions[file.type]}`;
    const response = await fetch(`${supabaseUrl}/storage/v1/object/visitor-thread-images/${path.split("/").map(encodeURIComponent).join("/")}`, {
      method: "POST",
      headers: { apikey: publishableKey, Authorization: `Bearer ${publishableKey}`, "Content-Type": file.type, "x-upsert": "false" },
      body: file
    });
    if (!response.ok) {
      const r = await response.json().catch(() => ({}));
      throw new Error(r.message || r.error || `Upload failed (${response.status}).`);
    }
    return { path, mediaType: isVideo ? "video" : "image" };
  }

  function createMediaElement(mediaPath, mediaType, legacyImagePath) {
    const path = mediaPath || legacyImagePath;
    if (!path) return null;
    const url = threadImageUrl(path);
    const type = mediaPath ? mediaType : "image";
    if (type === "video") {
      const video = document.createElement("video");
      video.src = url; video.controls = true; video.playsInline = true;
      video.preload = "metadata"; video.className = "visitor-thread-image";
      video.style.maxHeight = "360px";
      return video;
    }
    const img = document.createElement("img");
    img.src = url; img.alt = "Attached media"; img.loading = "lazy";
    img.className = "visitor-thread-image";
    return img;
  }

  function threadDateLabel(value) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "";
    return new Intl.DateTimeFormat("en-PH", {
      timeZone: zone, month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit"
    }).format(date);
  }

  // ── Reactions ────────────────────────────────────────────────────────────

  const EMOJIS = [
    { key: "like", label: "Like", icon: "👍" },
    { key: "love", label: "Love", icon: "❤️" },
    { key: "haha", label: "Haha", icon: "😂" },
    { key: "wow",  label: "Wow",  icon: "😮" },
    { key: "sad",  label: "Sad",  icon: "😢" }
  ];

  // threadState.reactions = { "thread-123": { like: 2, love: 1, myReaction: "like" }, ... }
  // key format: "thread-{id}" or "comment-{id}"

  async function loadReactions(targetType, targetIds) {
    if (!targetIds.length) return;
    try {
      const result = await callVisitorRpc("get_thread_reactions", {
        p_visitor_token: visitorToken(),
        p_target_type: targetType,
        p_target_ids: targetIds
      });
      if (!Array.isArray(result)) return;
      // Build reaction map
      result.forEach((row) => {
        const key = `${targetType}-${row.target_id}`;
        if (!threadState.reactions[key]) threadState.reactions[key] = { myReaction: null };
        threadState.reactions[key][row.emoji] = Number(row.reaction_count);
        if (row.my_reaction) threadState.reactions[key].myReaction = row.my_reaction;
      });
    } catch (error) {
      console.error("Could not load reactions.", error);
    }
  }

  function buildReactionBar(targetType, targetId) {
    const key = `${targetType}-${targetId}`;
    const data = threadState.reactions[key] || {};
    const bar = document.createElement("div");
    bar.className = "thread-reaction-bar";
    bar.dataset.targetType = targetType;
    bar.dataset.targetId = String(targetId);

    // Show existing reaction counts
    const summary = document.createElement("div");
    summary.className = "thread-reaction-summary";
    EMOJIS.forEach(({ key: emojiKey, icon }) => {
      const count = data[emojiKey] || 0;
      if (count > 0) {
        const badge = document.createElement("span");
        badge.className = "reaction-badge" + (data.myReaction === emojiKey ? " mine" : "");
        badge.textContent = `${icon} ${count}`;
        badge.dataset.emoji = emojiKey;
        summary.append(badge);
      }
    });

    // React button that reveals picker
    const reactBtn = document.createElement("button");
    reactBtn.type = "button";
    reactBtn.className = "reaction-btn";
    reactBtn.textContent = data.myReaction
      ? (EMOJIS.find((e) => e.key === data.myReaction)?.icon || "React")
      : "React";
    reactBtn.setAttribute("aria-label", "Add reaction");

    const picker = document.createElement("div");
    picker.className = "reaction-picker";
    picker.hidden = true;
    EMOJIS.forEach(({ key: emojiKey, icon, label }) => {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "reaction-pick" + (data.myReaction === emojiKey ? " active" : "");
      btn.textContent = icon;
      btn.title = label;
      btn.dataset.emoji = emojiKey;
      btn.setAttribute("aria-label", label);
      picker.append(btn);
    });

    reactBtn.addEventListener("click", (e) => {
      e.stopPropagation();
      // Close all other open pickers first
      document.querySelectorAll(".reaction-picker:not([hidden])").forEach((p) => { p.hidden = true; });
      picker.hidden = !picker.hidden;
      if (!picker.hidden) {
        const rect = reactBtn.getBoundingClientRect();
        picker.style.position = "fixed";
        picker.style.top = (rect.top - 52) + "px";
        picker.style.left = rect.left + "px";
        picker.style.zIndex = "9999";
      }
    });

    // Direct click on picker emoji buttons
    picker.addEventListener("click", (e) => {
      e.stopPropagation();
      const btn = e.target.closest("button[data-emoji]");
      if (!btn) return;
      picker.hidden = true;
      handleReaction(targetType, targetId, btn.dataset.emoji);
    });

    bar.append(summary, reactBtn, picker);
    return bar;
  }

  async function handleReaction(targetType, targetId, emoji) {
    try {
      await callVisitorRpc("toggle_thread_reaction", {
        p_visitor_token: visitorToken(),
        p_target_type: targetType,
        p_target_id: Number(targetId),
        p_emoji: emoji
      });
      // Reload reactions for this target only
      const key = `${targetType}-${targetId}`;
      delete threadState.reactions[key];
      await loadReactions(targetType, [Number(targetId)]);
      // Re-render just the reaction bar without full reload
      const bar = document.querySelector(`.thread-reaction-bar[data-target-type="${targetType}"][data-target-id="${targetId}"]`);
      if (bar) {
        const newBar = buildReactionBar(targetType, targetId);
        bar.replaceWith(newBar);
      }
    } catch (error) {
      console.error("Could not save reaction.", error);
    }
  }

  // ── Render threads ───────────────────────────────────────────────────────

  function buildCommentForm(threadId, parentCommentId, placeholder) {
    const form = document.createElement("form");
    form.className = "visitor-thread-comment-form";
    form.dataset.threadId = String(threadId);
    if (parentCommentId) form.dataset.parentCommentId = String(parentCommentId);

    const textarea = document.createElement("textarea");
    textarea.className = "comment-textarea";
    textarea.rows = 2;
    textarea.placeholder = placeholder || "Write a comment...";
    textarea.setAttribute("aria-label", "Write a comment");
    textarea.style.cssText = "width:100%;resize:vertical;min-height:60px;padding:8px 11px;border:1px solid #e7dfe4;border-radius:10px;font:inherit;font-size:.86rem;line-height:1.5;";

    const fileLabel = document.createElement("label");
    fileLabel.style.cssText = "display:flex;align-items:center;gap:6px;margin-top:6px;font-size:.76rem;color:#827d85;cursor:pointer;";
    const fileInput = document.createElement("input");
    fileInput.type = "file";
    fileInput.className = "comment-media-input";
    fileInput.accept = "image/jpeg,image/png,image/gif,image/webp,image/avif,video/mp4,video/webm,video/quicktime";
    fileInput.style.cssText = "max-width:180px;font-size:.74rem;";
    fileLabel.append("\uD83D\uDCCE Attach photo/video", fileInput);

    const actions = document.createElement("div");
    actions.style.cssText = "display:flex;gap:8px;margin-top:6px;";
    const submitBtn = document.createElement("button");
    submitBtn.type = "submit";
    submitBtn.textContent = parentCommentId ? "Reply" : "Comment";
    submitBtn.style.cssText = "min-height:36px;padding:7px 14px;border:1px solid #e999b1;border-radius:11px;background:#f3a9c0;color:#fff;cursor:pointer;font:inherit;font-size:.82rem;font-weight:700;";
    if (parentCommentId) {
      const cancelBtn = document.createElement("button");
      cancelBtn.type = "button";
      cancelBtn.textContent = "Cancel";
      cancelBtn.style.cssText = "min-height:36px;padding:7px 14px;border:1px solid #e7dfe4;border-radius:11px;background:#fff;color:#70656d;cursor:pointer;font:inherit;font-size:.82rem;";
      cancelBtn.addEventListener("click", () => form.remove());
      actions.append(submitBtn, cancelBtn);
    } else {
      actions.append(submitBtn);
    }

    form.append(textarea, fileLabel, actions);
    return form;
  }

  function renderThreads() {
    const feed = getElement("visitor-thread-feed");
    feed.replaceChildren();
    if (!threadState.posts.length) {
      const empty = document.createElement("p");
      empty.className = "thread-empty";
      empty.textContent = "No threads yet. Whenever you're ready, start one above.";
      feed.append(empty);
      return;
    }

    const myToken = threadState.token || localStorage.getItem(threadTokenKey) || "";

    threadState.posts.forEach((post) => {
      const isOwn = post.visitor_token && String(post.visitor_token) === myToken;
      const card = document.createElement("article");
      card.className = "visitor-thread-card";
      if (post.is_owner_post) card.style.borderLeft = "4px solid #f3a9c0";

      // Header
      const header = document.createElement("div");
      header.className = "visitor-thread-head";
      const author = document.createElement("div");
      const name = document.createElement("p");
      name.className = "visitor-thread-author";
      name.textContent = (post.is_owner_post ? "Owner: " : "") + (post.display_name || "Visitor");
      const date = document.createElement("p");
      date.className = "visitor-thread-date";
      date.textContent = threadDateLabel(post.created_at);
      author.append(name, date);
      header.append(author);
      if (isOwn && !post.is_owner_post) {
        const actions = document.createElement("div");
        actions.className = "visitor-thread-actions";
        const edit = document.createElement("button");
        edit.type = "button"; edit.dataset.action = "edit"; edit.dataset.threadId = String(post.id); edit.textContent = "Edit";
        const remove = document.createElement("button");
        remove.type = "button"; remove.dataset.action = "delete"; remove.dataset.threadId = String(post.id); remove.textContent = "Delete";
        actions.append(edit, remove);
        header.append(actions);
      }
      card.append(header);

      // Content
      if (post.content) {
        const content = document.createElement("p");
        content.className = "visitor-thread-content";
        content.textContent = post.content;
        card.append(content);
      }
      const threadMedia = createMediaElement(post.media_path, post.media_type, post.image_path);
      if (threadMedia) card.append(threadMedia);

      // Thread reaction bar
      card.append(buildReactionBar("thread", post.id));

      // Comments
      const allComments = threadState.comments[String(post.id)] || [];
      // Build a map of top-level and replies
      const topLevel = allComments.filter((c) => !c.parent_comment_id);
      const replies = allComments.filter((c) => c.parent_comment_id);

      const commentsDiv = document.createElement("div");
      commentsDiv.className = "visitor-thread-comments";

      function renderComment(comment, isReply) {
        const item = document.createElement("article");
        item.className = "visitor-thread-comment" + (comment.sender === "owner" ? " owner" : "") + (isReply ? " reply" : "");
        if (isReply) item.style.cssText = "margin-left:24px;border-left:3px solid #f0e9ed;padding-left:10px;";

        const commentHeader = document.createElement("div");
        commentHeader.className = "visitor-thread-comment-head";
        const commentAuthor = document.createElement("strong");
        commentAuthor.textContent = comment.sender_label || (comment.sender === "owner" ? "Owner" : "Visitor");
        const commentDate = document.createElement("time");
        commentDate.textContent = threadDateLabel(comment.created_at);
        commentHeader.append(commentAuthor, commentDate);

        const isOwnComment = comment.sender === "visitor" && comment.visitor_token && String(comment.visitor_token) === myToken;
        if (isOwnComment) {
          const editBtn = document.createElement("button");
          editBtn.type = "button"; editBtn.dataset.action = "edit-comment";
          editBtn.dataset.commentId = String(comment.id); editBtn.dataset.commentContent = comment.content;
          editBtn.textContent = "Edit";
          editBtn.style.cssText = "margin-left:auto;padding:2px 6px;border:1px solid #e7dfe4;border-radius:6px;background:transparent;color:#a64e68;cursor:pointer;font-size:.7rem;font-weight:700;";
          const delBtn = document.createElement("button");
          delBtn.type = "button"; delBtn.dataset.action = "delete-comment";
          delBtn.dataset.commentId = String(comment.id); delBtn.textContent = "Delete";
          delBtn.style.cssText = "padding:2px 6px;border:0;background:transparent;color:#a64e68;cursor:pointer;font-size:.7rem;font-weight:700;";
          commentHeader.append(editBtn, delBtn);
        }

        const body = document.createElement("p");
        body.textContent = comment.content;
        item.append(commentHeader, body);

        const commentMedia = createMediaElement(comment.media_path, comment.media_type, null);
        if (commentMedia) item.append(commentMedia);

        // Comment reaction bar
        item.append(buildReactionBar("comment", comment.id));

        // Reply button
        if (!isReply) {
          const replyBtn = document.createElement("button");
          replyBtn.type = "button";
          replyBtn.textContent = "Reply";
          replyBtn.style.cssText = "padding:2px 8px;border:0;background:transparent;color:#a64e68;cursor:pointer;font-size:.75rem;font-weight:700;";
          replyBtn.addEventListener("click", () => {
            // Remove any existing reply form for this comment
            const existing = item.querySelector(".visitor-thread-comment-form");
            if (existing) { existing.remove(); return; }
            const replyForm = buildCommentForm(post.id, comment.id, "Write your reply...");
            // Quote box showing original message
            const quoteBox = document.createElement("div");
            quoteBox.style.cssText = "margin-bottom:8px;padding:8px 12px;border-left:3px solid #f3a9c0;background:#fff8fa;border-radius:0 8px 8px 0;font-size:.82rem;color:#70656d;";
            const quoteAuthor = document.createElement("strong");
            quoteAuthor.style.cssText = "display:block;margin-bottom:3px;font-size:.75rem;color:#a64e68;";
            quoteAuthor.textContent = (comment.sender_label || (comment.sender === "owner" ? "Owner" : "Visitor"));
            const quoteText = document.createElement("p");
            quoteText.style.cssText = "margin:0;white-space:pre-wrap;overflow-wrap:anywhere;max-height:60px;overflow:hidden;font-style:italic;";
            quoteText.textContent = comment.content || "(media attachment)";
            quoteBox.append(quoteAuthor, quoteText);
            replyForm.prepend(quoteBox);
            item.append(replyForm);
            replyForm.querySelector("textarea").focus();
          });
          item.append(replyBtn);
        }

        return item;
      }

      topLevel.forEach((comment) => {
        commentsDiv.append(renderComment(comment, false));
        // Append replies to this comment
        replies.filter((r) => String(r.parent_comment_id) === String(comment.id))
          .forEach((reply) => commentsDiv.append(renderComment(reply, true)));
      });

      // Main comment form
      commentsDiv.append(buildCommentForm(post.id, null, `Comment on ${post.display_name || "this"} thread...`));
      card.append(commentsDiv);
      feed.append(card);
    });
  }

  async function loadThreads() {
    if (!supabaseUrl || !publishableKey)
      throw new Error("Threads are unavailable because the content service is not configured.");

    setStatus(getElement("visitor-thread-status"), "Loading threads...", false);
    const posts = await callVisitorRpc("get_all_visitor_threads", {});
    if (!Array.isArray(posts)) throw new Error("Threads returned an unexpected response.");
    threadState.posts = posts;

    const commentResults = await Promise.all(posts.map(async (post) => {
      const comments = await callVisitorRpc("get_all_thread_comments", { p_thread_id: post.id });
      if (!Array.isArray(comments)) throw new Error("Thread comments returned an unexpected response.");
      return [String(post.id), comments];
    }));
    threadState.comments = Object.fromEntries(commentResults);

    // Load reactions for all threads and comments
    const threadIds = posts.map((p) => p.id);
    const commentIds = Object.values(threadState.comments).flat().map((c) => c.id);
    threadState.reactions = {};
    await Promise.all([
      threadIds.length ? loadReactions("thread", threadIds) : Promise.resolve(),
      commentIds.length ? loadReactions("comment", commentIds) : Promise.resolve()
    ]);

    renderThreads();
    setStatus(getElement("visitor-thread-status"), "", false);
  }

  function resetThreadForm() {
    threadState.editingId = null;
    threadState.imagePath = null;
    threadState.mediaType = null;
    getElement("visitor-thread-form").reset();
    getElement("visitor-thread-name").value = localStorage.getItem(threadNameKey) || "";
    getElement("visitor-thread-remove-image-field").hidden = true;
    getElement("save-visitor-thread").textContent = "Post thread";
    getElement("cancel-visitor-thread-edit").hidden = true;
  }

  function editThread(id) {
    const post = threadState.posts.find((item) => String(item.id) === id);
    if (!post) return;
    threadState.editingId = post.id;
    threadState.imagePath = post.image_path || null;
    threadState.mediaType = post.media_type || (post.image_path ? "image" : null);
    getElement("visitor-thread-name").value = post.display_name || "";
    getElement("visitor-thread-content").value = post.content || "";
    getElement("visitor-thread-image").value = "";
    getElement("visitor-thread-remove-image").checked = false;
    getElement("visitor-thread-remove-image-field").hidden = !post.image_path;
    getElement("save-visitor-thread").textContent = "Save changes";
    getElement("cancel-visitor-thread-edit").hidden = false;
    getElement("visitor-thread-form").scrollIntoView({ behavior: "smooth", block: "center" });
  }

  async function saveThread(event) {
    event.preventDefault();
    if (threadState.saving) return;
    const content = getElement("visitor-thread-content").value.trim();
    const name = getElement("visitor-thread-name").value.trim() || "Visitor";
    const file = getElement("visitor-thread-image").files[0] || null;
    const removeImage = getElement("visitor-thread-remove-image").checked;
    const wasEditing = Boolean(threadState.editingId);

    threadState.saving = true;
    const saveButton = getElement("save-visitor-thread");
    saveButton.disabled = true;
    setStatus(getElement("visitor-thread-status"), threadState.editingId ? "Saving your changes..." : "Posting your thread...", false);
    try {
      const token = visitorToken();
      let mediaSavePath = threadState.imagePath;
      let mediaSaveType = threadState.mediaType || "image";
      if (removeImage) { mediaSavePath = null; mediaSaveType = null; }
      if (file) {
        const uploaded = await uploadThreadMedia(file, token);
        mediaSavePath = uploaded.path;
        mediaSaveType = uploaded.mediaType;
      }
      if (!content && !mediaSavePath) {
        setStatus(getElement("visitor-thread-status"), "Write something or add media before posting.", true);
        return;
      }
      const imagePath = (mediaSaveType === "image" || !mediaSavePath) ? mediaSavePath : null;
      await callVisitorRpc(
        threadState.editingId ? "update_visitor_thread" : "create_visitor_thread",
        threadState.editingId
          ? { p_visitor_token: token, p_thread_id: threadState.editingId, p_display_name: name, p_content: content, p_image_path: imagePath, p_media_path: mediaSavePath, p_media_type: mediaSaveType }
          : { p_visitor_token: token, p_display_name: name, p_content: content, p_image_path: imagePath, p_media_path: mediaSavePath, p_media_type: mediaSaveType }
      );
      localStorage.setItem(threadNameKey, name);
      resetThreadForm();
      await loadThreads();
      setStatus(getElement("visitor-thread-status"), wasEditing ? "Thread updated." : "Thread posted.", false);
    } catch (error) {
      console.error("Could not save the visitor thread.", error);
      setStatus(getElement("visitor-thread-status"), error.message || "Your thread could not be saved.", true);
    } finally {
      threadState.saving = false;
      saveButton.disabled = false;
    }
  }

  async function deleteThread(id) {
    const post = threadState.posts.find((item) => String(item.id) === id);
    if (!post) return;
    setStatus(getElement("visitor-thread-status"), "Deleting thread...", false);
    try {
      await callVisitorRpc("delete_visitor_thread", { p_visitor_token: visitorToken(), p_thread_id: post.id });
      await loadThreads();
      setStatus(getElement("visitor-thread-status"), "Thread deleted.", false);
    } catch (error) {
      console.error("Could not delete the visitor thread.", error);
      setStatus(getElement("visitor-thread-status"), error.message || "The thread could not be deleted.", true);
    }
  }

  async function deleteComment(commentId) {
    
    setStatus(getElement("visitor-thread-status"), "Deleting comment...", false);
    try {
      await callVisitorRpc("delete_visitor_thread_comment", { p_visitor_token: visitorToken(), p_comment_id: Number(commentId) });
      await loadThreads();
      setStatus(getElement("visitor-thread-status"), "Comment deleted.", false);
    } catch (error) {
      console.error("Could not delete the visitor thread comment.", error);
      setStatus(getElement("visitor-thread-status"), error.message || "The comment could not be deleted.", true);
    }
  }

  async function editComment(commentId, currentContent) {
    const newContent = window.prompt("Edit your comment:", currentContent);
    if (newContent === null) return;
    const trimmed = newContent.trim();
    if (!trimmed) { alert("Comment cannot be empty."); return; }
    setStatus(getElement("visitor-thread-status"), "Saving edit...", false);
    try {
      await callVisitorRpc("edit_visitor_thread_comment", { p_visitor_token: visitorToken(), p_comment_id: Number(commentId), p_content: trimmed });
      await loadThreads();
      setStatus(getElement("visitor-thread-status"), "Comment updated.", false);
    } catch (error) {
      console.error("Could not edit the visitor thread comment.", error);
      setStatus(getElement("visitor-thread-status"), error.message || "The comment could not be edited.", true);
    }
  }

  async function sendThreadComment(event) {
    event.preventDefault();
    const form = event.target;
    if (!(form instanceof HTMLFormElement) || !form.matches(".visitor-thread-comment-form")) return;
    const textarea = form.querySelector("textarea.comment-textarea");
    const fileInput = form.querySelector(".comment-media-input");
    const button = form.querySelector("button[type='submit']");
    const content = textarea ? textarea.value.trim() : "";
    const file = fileInput ? (fileInput.files[0] || null) : null;
    if (!content && !file) return;
    const savedValue = textarea ? textarea.value : "";
    if (button) button.disabled = true;
    try {
      const token = visitorToken();
      let commentMediaPath = null;
      let commentMediaType = null;
      if (file) {
        const uploaded = await uploadThreadMedia(file, token);
        commentMediaPath = uploaded.path;
        commentMediaType = uploaded.mediaType;
      }
      const parentId = form.dataset.parentCommentId ? Number(form.dataset.parentCommentId) : null;
      await callVisitorRpc("add_comment_to_thread", {
        p_visitor_token: token,
        p_thread_id: Number(form.dataset.threadId),
        p_display_name: getElement("visitor-thread-name").value.trim() || localStorage.getItem(threadNameKey) || "Visitor",
        p_content: content,
        p_media_path: commentMediaPath,
        p_media_type: commentMediaType,
        p_parent_comment_id: parentId
      });
      if (textarea) textarea.value = "";
      if (fileInput) fileInput.value = "";
      // If this was a reply form (has parent), remove it after posting
      if (parentId) form.remove();
      await loadThreads();
      setStatus(getElement("visitor-thread-status"), "Comment added.", false);
    } catch (error) {
      console.error("Could not add the visitor thread comment.", error);
      if (textarea) textarea.value = savedValue;
      setStatus(getElement("visitor-thread-status"), error.message || "Your comment could not be added.", true);
    } finally {
      if (button) button.disabled = false;
    }
  }

  function refreshThreads() {
    // Save all in-progress textarea drafts keyed by threadId
    const drafts = {};
    document.querySelectorAll(".visitor-thread-comment-form").forEach((form) => {
      const ta = form.querySelector("textarea.comment-textarea");
      if (ta && ta.value.trim()) drafts[form.dataset.threadId] = ta.value;
    });

    loadThreads().then(() => {
      // Restore drafts
      Object.keys(drafts).forEach((threadId) => {
        const form = document.querySelector(`.visitor-thread-comment-form:not([data-parent-comment-id])[data-thread-id="${threadId}"]`);
        if (form) {
          const ta = form.querySelector("textarea.comment-textarea");
          if (ta) ta.value = drafts[threadId];
        }
      });
    }).catch((error) => {
      console.error("Could not load visitor threads.", error);
      setStatus(getElement("visitor-thread-status"), error.message || "Threads could not be loaded.", true);
    });
  }

  function startThreadPolling() {
    // No automatic polling — threads only refresh when the user clicks Refresh
    // or navigates to the threads tab
  }

  function initThreads() {
    try {
      const token = localStorage.getItem(threadTokenKey);
      if (token) threadState.token = token;
      getElement("visitor-thread-name").value = localStorage.getItem(threadNameKey) || "";
      getElement("visitor-thread-form").addEventListener("submit", saveThread);
      getElement("cancel-visitor-thread-edit").addEventListener("click", resetThreadForm);
      const feed = getElement("visitor-thread-feed");
      feed.addEventListener("click", (event) => {
        const button = event.target.closest("button[data-action]");
        if (button) {
          if (button.dataset.action === "edit") editThread(button.dataset.threadId);
          if (button.dataset.action === "delete") deleteThread(button.dataset.threadId);
          if (button.dataset.action === "delete-comment") deleteComment(button.dataset.commentId);
          if (button.dataset.action === "edit-comment") editComment(button.dataset.commentId, button.dataset.commentContent);
          return;
        }
        // Close open pickers when clicking outside them
        document.querySelectorAll(".reaction-picker:not([hidden])").forEach((p) => {
          if (!p.contains(event.target)) p.hidden = true;
        });
      });
      feed.addEventListener("submit", sendThreadComment);
      startThreadPolling();
    } catch (error) {
      console.error("Could not initialize visitor threads.", error);
      setStatus(getElement("visitor-thread-status"), error.message || "Threads could not be initialized.", true);
    }
  }

  if (getElement("page-schedule") && getElement("page-threads")) {
    initSchedule();
    initThreads();
    window.VisitorTools = {
      loadSchedule,
      refreshSchedule: loadSchedule,
      refreshThreads,
      loadContentLikeStatus,
      toggleContentLike,
      submitVisitorCheckin,
      getToken: visitorToken
    };
    document.addEventListener("visibilitychange", () => {
      if (!document.hidden) {
        renderSchedule();
        if (!getElement("page-threads").hidden) refreshThreads();
      }
    });
  }
})();
