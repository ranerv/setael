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
    events: [],
    selectedDate: "",
    weekStart: "",
    modes: {},
    personalEvents: [],
    editingPersonalId: null,
    timer: null
  };
  const threadState = {
    token: "",
    posts: [],
    comments: {},
    timer: null,
    saving: false,
    editingId: null,
    imagePath: null,
    mediaType: null
  };

  function getElement(id) {
    return document.getElementById(id);
  }

  function getPhtParts(date) {
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone: zone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      weekday: "short",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23"
    }).formatToParts(date);
    return Object.fromEntries(parts.map((part) => [part.type, part.value]));
  }

  function phtDateKey(date) {
    const parts = getPhtParts(date);
    return `${parts.year}-${parts.month}-${parts.day}`;
  }

  function weekdayForDate(dateKey) {
    return new Date(`${dateKey}T12:00:00Z`).getUTCDay() || 7;
  }

  function addDays(dateKey, amount) {
    const date = new Date(`${dateKey}T12:00:00Z`);
    date.setUTCDate(date.getUTCDate() + amount);
    return date.toISOString().slice(0, 10);
  }

  function mondayOf(dateKey) {
    return addDays(dateKey, 1 - weekdayForDate(dateKey));
  }

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
      setStatus(getElement("schedule-status"), "Your saved reminders could not be read. Clear this site's stored schedule data or use another browser.", true);
      scheduleState.personalEvents = [];
    }
  }

  function savePersonalEvents() {
    try {
      localStorage.setItem(personalScheduleKey, JSON.stringify(scheduleState.personalEvents));
    } catch (error) {
      console.error("Could not save personal schedule reminders.", error);
      setStatus(getElement("schedule-status"), "Your reminder could not be saved in this browser. Check device storage and try again.", true);
      return false;
    }
    return true;
  }

  function weeklyDate(event, dateKey) {
    return event.weekday === weekdayForDate(dateKey);
  }

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

  function eventsForSelectedDate() {
    return eventsForDate(scheduleState.selectedDate);
  }

  function readScheduleModes() {
    try {
      const saved = JSON.parse(localStorage.getItem(scheduleModesKey) || "{}");
      if (!saved || typeof saved !== "object" || Array.isArray(saved)) {
        throw new Error("Saved class-format preferences have an unexpected format.");
      }
      scheduleState.modes = Object.fromEntries(Object.entries(saved).filter(([, mode]) =>
        mode === "face_to_face" || mode === "online"));
    } catch (error) {
      console.error("Could not read class-format preferences.", error);
      setStatus(getElement("schedule-status"), "Your saved class-format choices could not be read. Clear this site's stored schedule data or use another browser.", true);
      scheduleState.modes = {};
    }
  }

  function saveScheduleModes() {
    try {
      localStorage.setItem(scheduleModesKey, JSON.stringify(scheduleState.modes));
      setStatus(getElement("schedule-status"), "Your class format was saved on this browser and device.", false);
    } catch (error) {
      console.error("Could not save the class-format preference.", error);
      setStatus(getElement("schedule-status"), "Your class format could not be saved in this browser. Check device storage and try again.", true);
    }
  }

  function createModeSelect(event) {
    const select = document.createElement("select");
    const eventId = String(event.id);
    select.className = "schedule-format-select";
    select.setAttribute("aria-label", `Choose the format for ${event.title}`);
    [
      ["", "Choose format"],
      ["face_to_face", "Face to face"],
      ["online", "Online"]
    ].forEach(([value, label]) => {
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
      tab.addEventListener("click", () => {
        scheduleState.selectedDate = dateKey;
        renderSchedule();
      });
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
        edit.type = "button";
        edit.textContent = "Edit";
        edit.addEventListener("click", (clickEvent) => {
          clickEvent.stopPropagation();
          editPersonalEvent(event.id);
        });
        const remove = document.createElement("button");
        remove.type = "button";
        remove.textContent = "Remove";
        remove.addEventListener("click", (clickEvent) => {
          clickEvent.stopPropagation();
          removePersonalEvent(event.id);
        });
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
    const dateText = dateLabel(todayKey, { weekday: "long", month: "long", day: "numeric" });
    getElement("home-schedule-date").textContent =
      `Current time in the Philippines: ${dateText}, ${timeLabel(`${parts.hour}:${parts.minute}`)}`;
    container.replaceChildren();

    const todayItems = eventsForDate(todayKey);
    const currentEvent = todayItems.find((event) =>
      minutesOf(event.start_time) <= currentMinutes && currentMinutes < minutesOf(event.end_time)
    );
    let nextEvent = null;
    for (let offset = 0; offset < 7 && !nextEvent; offset += 1) {
      const eventDate = addDays(todayKey, offset);
      nextEvent = eventsForDate(eventDate)
        .filter((event) => {
          const start = minutesOf(event.start_time);
          if (offset > 0) return true;
          return currentEvent ? start >= minutesOf(currentEvent.end_time) : start > currentMinutes;
        })
        .map((event) => ({ ...event, scheduleDate: eventDate }))[0] || null;
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
      } else {
        title.textContent = emptyTitle;
        detail.textContent = emptyDetails;
      }
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
      if (!response.ok) throw new Error(`Schedule could not be loaded (${response.status}). Apply the latest Supabase SQL setup and try again.`);
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
    scheduleState.personalEvents = scheduleState.personalEvents.filter((event) => event.id !== id);
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
      start_time: start,
      end_time: end,
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
    try {
      if (localStorage.getItem(guideKey) !== "true") getElement("schedule-guide").hidden = false;
    } catch (error) {
      console.error("Could not read the schedule guide preference.", error);
    }
    getElement("personal-schedule-date").value = todayKey;
    getElement("dismiss-schedule-guide").addEventListener("click", () => {
      try { localStorage.setItem(guideKey, "true"); } catch (error) { console.error("Could not save the schedule guide preference.", error); }
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

  // ── Token ────────────────────────────────────────────────────────────────

  function visitorToken() {
    if (threadState.token) return threadState.token;
    let token = localStorage.getItem(threadTokenKey);
    if (!token) {
      if (!window.crypto || typeof window.crypto.randomUUID !== "function") {
        throw new Error("This browser cannot create a secure private-thread session. Please update your browser.");
      }
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
    try {
      result = text ? JSON.parse(text) : null;
    } catch (error) {
      throw new Error("The private-thread service returned an unexpected response.");
    }
    if (!response.ok) {
      throw new Error((result && (result.message || result.msg)) || `The request failed (${response.status}).`);
    }
    return result;
  }

  function readLikeResult(result) {
    const row = Array.isArray(result) ? result[0] : result;
    if (!row || !Number.isFinite(Number(row.like_count)) || typeof row.liked !== "boolean") {
      throw new Error("The like service returned an unexpected response.");
    }
    return { count: Number(row.like_count), liked: row.liked };
  }

  async function loadContentLikeStatus(contentType, contentId) {
    const result = await callVisitorRpc("get_daily_content_like_status", {
      p_visitor_token: visitorToken(),
      p_content_type: contentType,
      p_content_id: String(contentId)
    });
    return readLikeResult(result);
  }

  async function toggleContentLike(contentType, contentId) {
    const result = await callVisitorRpc("toggle_daily_content_like", {
      p_visitor_token: visitorToken(),
      p_content_type: contentType,
      p_content_id: String(contentId)
    });
    return readLikeResult(result);
  }

  async function submitVisitorCheckin(answer, message) {
    return callVisitorRpc("submit_visitor_checkin", {
      p_visitor_token: visitorToken(),
      p_answer: answer,
      p_message: message
    });
  }

  // ── Threads ──────────────────────────────────────────────────────────────

  function threadImageUrl(path) {
    const safePath = path.split("/").map(encodeURIComponent).join("/");
    return `${supabaseUrl}/storage/v1/object/public/visitor-thread-images/${safePath}`;
  }

  const threadMediaExtensions = {
    "image/jpeg": "jpg", "image/png": "png", "image/gif": "gif",
    "image/webp": "webp", "image/avif": "avif",
    "video/mp4": "mp4", "video/webm": "webm", "video/quicktime": "mov"
  };

  function isVideoType(mimeType) {
    return mimeType && mimeType.startsWith("video/");
  }

  function threadMediaType(mimeType) {
    return isVideoType(mimeType) ? "video" : "image";
  }

  async function uploadThreadMedia(file, token) {
    if (!threadMediaExtensions[file.type]) {
      throw new Error("Choose a JPEG, PNG, GIF, WebP, AVIF image or MP4/WebM/MOV video.");
    }
    const maxSize = isVideoType(file.type) ? 100 * 1024 * 1024 : 5 * 1024 * 1024;
    if (file.size > maxSize) {
      throw new Error(isVideoType(file.type) ? "Videos must be 100 MB or smaller." : "Photos must be 5 MB or smaller.");
    }
    const ext = threadMediaExtensions[file.type];
    const path = `${token}/${window.crypto.randomUUID()}.${ext}`;
    const safePath = path.split("/").map(encodeURIComponent).join("/");
    const response = await fetch(`${supabaseUrl}/storage/v1/object/visitor-thread-images/${safePath}`, {
      method: "POST",
      headers: {
        apikey: publishableKey,
        Authorization: `Bearer ${publishableKey}`,
        "Content-Type": file.type,
        "x-upsert": "false"
      },
      body: file
    });
    if (!response.ok) {
      const result = await response.json().catch(() => ({}));
      throw new Error(result.message || result.error || `Upload failed (${response.status}).`);
    }
    return { path, mediaType: threadMediaType(file.type) };
  }

  function createMediaElement(mediaPath, mediaType, legacyImagePath) {
    const path = mediaPath || legacyImagePath;
    if (!path) return null;
    const url = threadImageUrl(path);
    const type = mediaPath ? mediaType : "image";
    if (type === "video") {
      const video = document.createElement("video");
      video.src = url;
      video.controls = true;
      video.playsInline = true;
      video.preload = "metadata";
      video.className = "visitor-thread-image";
      video.style.maxHeight = "360px";
      return video;
    }
    const img = document.createElement("img");
    img.src = url;
    img.alt = "Attached media";
    img.loading = "lazy";
    img.className = "visitor-thread-image";
    return img;
  }
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "";
    return new Intl.DateTimeFormat("en-PH", {
      timeZone: zone, month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit"
    }).format(date);
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

    // Identify this visitor's own posts so only they see Edit/Delete
    const myToken = threadState.token || localStorage.getItem(threadTokenKey) || "";

    threadState.posts.forEach((post) => {
      const isOwn = post.visitor_token && String(post.visitor_token) === myToken;

      const card = document.createElement("article");
      card.className = "visitor-thread-card";

      const header = document.createElement("div");
      header.className = "visitor-thread-head";
      const author = document.createElement("div");
      const name = document.createElement("p");
      name.className = "visitor-thread-author";
      name.textContent = post.display_name || "Visitor";
      const date = document.createElement("p");
      date.className = "visitor-thread-date";
      date.textContent = threadDateLabel(post.created_at);
      author.append(name, date);
      header.append(author);

      // Only the original poster sees Edit / Delete
      if (isOwn) {
        const actions = document.createElement("div");
        actions.className = "visitor-thread-actions";
        const edit = document.createElement("button");
        edit.type = "button";
        edit.dataset.action = "edit";
        edit.dataset.threadId = String(post.id);
        edit.textContent = "Edit";
        const remove = document.createElement("button");
        remove.type = "button";
        remove.dataset.action = "delete";
        remove.dataset.threadId = String(post.id);
        remove.textContent = "Delete";
        actions.append(edit, remove);
        header.append(actions);
      }
      card.append(header);

      if (post.content) {
        const content = document.createElement("p");
        content.className = "visitor-thread-content";
        content.textContent = post.content;
        card.append(content);
      }
      // Show media (new media_path/media_type, fallback to legacy image_path)
      const threadMedia = createMediaElement(post.media_path, post.media_type, post.image_path);
      if (threadMedia) card.append(threadMedia);

      // Comments section - visible to all
      const comments = document.createElement("div");
      comments.className = "visitor-thread-comments";
      (threadState.comments[String(post.id)] || []).forEach((comment) => {
        const item = document.createElement("article");
        item.className = "visitor-thread-comment" + (comment.sender === "owner" ? " owner" : "");
        const commentHeader = document.createElement("div");
        commentHeader.className = "visitor-thread-comment-head";
        const commentAuthor = document.createElement("strong");
        commentAuthor.textContent = comment.sender_label || (comment.sender === "owner" ? "Owner" : "Visitor");
        const commentDate = document.createElement("time");
        commentDate.textContent = threadDateLabel(comment.created_at);
        commentHeader.append(commentAuthor, commentDate);

        const isOwnComment = comment.sender === "visitor"
          && comment.visitor_token && String(comment.visitor_token) === myToken;
        if (isOwnComment) {
          const editBtn = document.createElement("button");
          editBtn.type = "button";
          editBtn.dataset.action = "edit-comment";
          editBtn.dataset.commentId = String(comment.id);
          editBtn.dataset.commentContent = comment.content;
          editBtn.textContent = "Edit";
          editBtn.style.cssText = "margin-left:auto;padding:2px 6px;border:1px solid #e7dfe4;border-radius:6px;background:transparent;color:#a64e68;cursor:pointer;font-size:.7rem;font-weight:700;";
          const delBtn = document.createElement("button");
          delBtn.type = "button";
          delBtn.dataset.action = "delete-comment";
          delBtn.dataset.commentId = String(comment.id);
          delBtn.textContent = "Delete";
          delBtn.style.cssText = "padding:2px 6px;border:0;background:transparent;color:#a64e68;cursor:pointer;font-size:.7rem;font-weight:700;";
          commentHeader.append(editBtn, delBtn);
        }

        const body = document.createElement("p");
        body.textContent = comment.content;
        item.append(commentHeader, body);

        const commentMedia = createMediaElement(comment.media_path, comment.media_type, null);
        if (commentMedia) item.append(commentMedia);

        comments.append(item);
      });

      // Comment form - available to all visitors
      const commentForm = document.createElement("form");
      commentForm.className = "visitor-thread-comment-form";
      commentForm.dataset.threadId = String(post.id);

      const commentInput = document.createElement("input");
      commentInput.type = "text";
      commentInput.maxLength = 1000;
      commentInput.placeholder = "Write a comment...";
      commentInput.setAttribute("aria-label", "Comment on " + (post.display_name || "this") + " thread");

      const commentFileLabel = document.createElement("label");
      commentFileLabel.style.cssText = "display:flex;align-items:center;gap:6px;margin-top:6px;font-size:.76rem;color:#827d85;cursor:pointer;";
      const commentFileInput = document.createElement("input");
      commentFileInput.type = "file";
      commentFileInput.className = "comment-media-input";
      commentFileInput.accept = "image/jpeg,image/png,image/gif,image/webp,image/avif,video/mp4,video/webm,video/quicktime";
      commentFileInput.style.cssText = "max-width:180px;font-size:.74rem;";
      commentFileLabel.append("\uD83D\uDCCE Attach photo/video", commentFileInput);

      const commentButton = document.createElement("button");
      commentButton.type = "submit";
      commentButton.textContent = "Comment";

      commentForm.append(commentInput, commentFileLabel, commentButton);
      comments.append(commentForm);
      card.append(comments);
      feed.append(card);
    });
  }

  async function loadThreads() {
    if (!supabaseUrl || !publishableKey) {
      throw new Error("Threads are unavailable because the content service is not configured.");
    }
    setStatus(getElement("visitor-thread-status"), "Loading threads…", false);

    // Load ALL threads — every visitor sees everyone's posts
    const posts = await callVisitorRpc("get_all_visitor_threads", {});
    if (!Array.isArray(posts)) throw new Error("Threads returned an unexpected response.");
    threadState.posts = posts;

    // Load all comments for every thread
    const commentResults = await Promise.all(posts.map(async (post) => {
      const comments = await callVisitorRpc("get_all_thread_comments", { p_thread_id: post.id });
      if (!Array.isArray(comments)) throw new Error("Thread comments returned an unexpected response.");
      return [String(post.id), comments];
    }));
    threadState.comments = Object.fromEntries(commentResults);
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

  // uploadThreadImage now wraps uploadThreadMedia for backward compat
  async function uploadThreadImage(file, token) {
    const result = await uploadThreadMedia(file, token);
    return result.path;
  }

    async function saveThread(event) {
    event.preventDefault();
    if (threadState.saving) return;
    const content = getElement("visitor-thread-content").value.trim();
    const name = getElement("visitor-thread-name").value.trim() || "Visitor";
    const file = getElement("visitor-thread-image").files[0] || null;
    const removeImage = getElement("visitor-thread-remove-image").checked;
    const wasEditing = Boolean(threadState.editingId);
    if (!content && !file && !(threadState.imagePath && !removeImage)) {
      setStatus(getElement("visitor-thread-status"), "Write something or add a photo before posting.", true);
      return;
    }
    threadState.saving = true;
    const saveButton = getElement("save-visitor-thread");
    saveButton.disabled = true;
    setStatus(getElement("visitor-thread-status"), threadState.editingId ? "Saving your changes…" : "Posting your thread…", false);
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

  async function deleteComment(commentId) {
    if (!window.confirm("Delete this comment? This cannot be undone.")) return;
    setStatus(getElement("visitor-thread-status"), "Deleting comment…", false);
    try {
      await callVisitorRpc("delete_visitor_thread_comment", {
        p_visitor_token: visitorToken(),
        p_comment_id: Number(commentId)
      });
      await loadThreads();
      setStatus(getElement("visitor-thread-status"), "Comment deleted.", false);
    } catch (error) {
      console.error("Could not delete the visitor thread comment.", error);
      setStatus(getElement("visitor-thread-status"), error.message || "The comment could not be deleted.", true);
    }
  }

  async function deleteThread(id) {
    const post = threadState.posts.find((item) => String(item.id) === id);
    if (!post || !window.confirm("Delete this thread and its comments? This cannot be undone.")) return;
    setStatus(getElement("visitor-thread-status"), "Deleting thread…", false);
    try {
      await callVisitorRpc("delete_visitor_thread", { p_visitor_token: visitorToken(), p_thread_id: post.id });
      await loadThreads();
      setStatus(getElement("visitor-thread-status"), "Thread deleted.", false);
    } catch (error) {
      console.error("Could not delete the visitor thread.", error);
      setStatus(getElement("visitor-thread-status"), error.message || "The thread could not be deleted.", true);
    }
  }

  async function sendThreadComment(event) {
    event.preventDefault();
    const form = event.target;
    if (!(form instanceof HTMLFormElement) || !form.matches(".visitor-thread-comment-form")) return;
    const input = form.querySelector("input[type='text']");
    const fileInput = form.querySelector(".comment-media-input");
    const button = form.querySelector("button[type='submit']");
    const content = input ? input.value.trim() : "";
    const file = fileInput ? (fileInput.files[0] || null) : null;
    if (!content && !file) return;
    const savedValue = input ? input.value : "";
    button.disabled = true;
    try {
      const token = visitorToken();
      let commentMediaPath = null;
      let commentMediaType = null;
      if (file) {
        const uploaded = await uploadThreadMedia(file, token);
        commentMediaPath = uploaded.path;
        commentMediaType = uploaded.mediaType;
      }
      await callVisitorRpc("add_comment_to_thread", {
        p_visitor_token: token,
        p_thread_id: Number(form.dataset.threadId),
        p_display_name: getElement("visitor-thread-name").value.trim() || localStorage.getItem(threadNameKey) || "Visitor",
        p_content: content,
        p_media_path: commentMediaPath,
        p_media_type: commentMediaType
      });
      if (input) input.value = "";
      if (fileInput) fileInput.value = "";
      await loadThreads();
      setStatus(getElement("visitor-thread-status"), "Comment added.", false);
    } catch (error) {
      console.error("Could not add the visitor thread comment.", error);
      if (input) input.value = savedValue;
      setStatus(getElement("visitor-thread-status"), error.message || "Your comment could not be added.", true);
    } finally {
      button.disabled = false;
    }
  }

  async function editComment(commentId, currentContent) {
    const newContent = window.prompt("Edit your comment:", currentContent);
    if (newContent === null) return; // cancelled
    const trimmed = newContent.trim();
    if (!trimmed) { alert("Comment cannot be empty."); return; }
    setStatus(getElement("visitor-thread-status"), "Saving edit...", false);
    try {
      await callVisitorRpc("edit_visitor_thread_comment", {
        p_visitor_token: visitorToken(),
        p_comment_id: Number(commentId),
        p_content: trimmed
      });
      await loadThreads();
      setStatus(getElement("visitor-thread-status"), "Comment updated.", false);
    } catch (error) {
      console.error("Could not edit the visitor thread comment.", error);
      setStatus(getElement("visitor-thread-status"), error.message || "The comment could not be edited.", true);
    }
  }
  function refreshThreads() {
    // Save any comment text the visitor is currently typing
    const drafts = {};
    document.querySelectorAll(".visitor-thread-comment-form").forEach((form) => {
      const input = form.querySelector("input");
      if (input && input.value.trim()) drafts[form.dataset.threadId] = input.value;
    });

    loadThreads().then(() => {
      // Restore saved drafts after re-render
      if (Object.keys(drafts).length) {
        document.querySelectorAll(".visitor-thread-comment-form").forEach((form) => {
          const saved = drafts[form.dataset.threadId];
          if (saved) {
            const input = form.querySelector("input");
            if (input) input.value = saved;
          }
        });
      }
    }).catch((error) => {
      console.error("Could not load visitor threads.", error);
      setStatus(getElement("visitor-thread-status"), error.message || "Threads could not be loaded.", true);
    });
  }

  function startThreadPolling() {
    if (threadState.timer) window.clearInterval(threadState.timer);
    threadState.timer = window.setInterval(() => {
      if (getElement("page-threads").hidden || document.hidden) return;
      // Don't refresh if the visitor is actively typing in a comment box
      const focused = document.activeElement;
      if (focused && focused.closest(".visitor-thread-comment-form")) return;
      refreshThreads();
    }, 15000);
  }

  function initThreads() {
    try {
      const token = localStorage.getItem(threadTokenKey);
      if (token) threadState.token = token;
      getElement("visitor-thread-name").value = localStorage.getItem(threadNameKey) || "";
      getElement("visitor-thread-form").addEventListener("submit", saveThread);
      getElement("cancel-visitor-thread-edit").addEventListener("click", resetThreadForm);
      getElement("visitor-thread-feed").addEventListener("click", (event) => {
        const button = event.target.closest("button[data-action]");
        if (!button) return;
        if (button.dataset.action === "edit") editThread(button.dataset.threadId);
        if (button.dataset.action === "delete") deleteThread(button.dataset.threadId);
        if (button.dataset.action === "delete-comment") deleteComment(button.dataset.commentId);
        if (button.dataset.action === "edit-comment") editComment(button.dataset.commentId, button.dataset.commentContent);
      });
      getElement("visitor-thread-feed").addEventListener("submit", sendThreadComment);
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
