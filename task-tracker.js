(function () {
  "use strict";

  const config = window.ACTIVITY_LOG_CONFIG || {};
  const supabaseUrl = typeof config.supabaseUrl === "string" ? config.supabaseUrl.replace(/\/+$/, "") : "";
  const publishableKey = typeof config.publishableKey === "string" ? config.publishableKey.trim() : "";
  const ownerSessionKey = "sachel-owner-auth-session";
  const trackerSessionKey = "sachel-task-tracker-auth-session";
  const loginPanel = document.getElementById("login-panel");
  const tracker = document.getElementById("tracker");
  const loginForm = document.getElementById("login-form");
  const loginStatus = document.getElementById("login-status");
  const signInButton = document.getElementById("sign-in");
  const signOutButton = document.getElementById("sign-out");
  const adminTools = document.getElementById("admin-tools");
  const userPicker = document.getElementById("user-picker");
  const userCount = document.getElementById("user-count");
  const boardStatus = document.getElementById("board-status");
  const boardCaption = document.getElementById("board-caption");
  const boardActivity = document.getElementById("board-activity");
  const taskDialog = document.getElementById("task-dialog");
  const taskForm = document.getElementById("task-form");
  const taskFormStatus = document.getElementById("task-form-status");
  const saveTaskButton = document.getElementById("save-task");
  const taskTitleInput = document.getElementById("task-title");
  const taskContentsInput = document.getElementById("task-contents");
  const taskPriorityInput = document.getElementById("task-priority");
  const taskDeadlineDateInput = document.getElementById("task-deadline-date");
  const taskDeadlineTimeInput = document.getElementById("task-deadline-time");
  const taskStatusInput = document.getElementById("task-status");
  const subtaskDialog = document.getElementById("subtask-dialog");
  const subtaskForm = document.getElementById("subtask-form");
  const subtaskTitleInput = document.getElementById("subtask-title");
  const subtaskFormStatus = document.getElementById("subtask-form-status");
  const saveSubtaskButton = document.getElementById("save-subtask");
  const moveDialog = document.getElementById("move-dialog");
  const moveForm = document.getElementById("move-form");
  const moveStatusInput = document.getElementById("move-status");
  const moveFormStatus = document.getElementById("move-form-status");
  const saveMoveButton = document.getElementById("save-move");
  const client = window.supabase && typeof window.supabase.createClient === "function"
    ? window.supabase.createClient(supabaseUrl, publishableKey, {
      auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false }
    })
    : null;

  let activeStorageKey = "";
  let session = null;
  let accessToken = "";
  let refreshPromise = null;
  let currentUser = null;
  let isAdmin = false;
  let boardUser = null;
  let users = [];
  let tasks = [];
  let subtasks = [];
  let comments = [];
  let activity = [];
  let activeChannel = null;
  let editingTaskId = null;
  let addingSubtaskTaskId = null;
  let movingTaskId = null;

  function setStatus(element, message, isError) {
    element.textContent = message;
    if (isError) element.dataset.error = "true";
    else delete element.dataset.error;
  }

  async function readResponse(response) {
    const text = await response.text();
    let data = {};
    if (text) {
      try {
        data = JSON.parse(text);
      } catch (error) {
        data = {};
      }
    }
    if (!response.ok) {
      throw new Error(data.message || data.msg || data.error_description || data.details || `Request failed (${response.status}).`);
    }
    return data;
  }

  function saveSession(nextSession, storageKey) {
    if (!nextSession || !nextSession.access_token || !nextSession.refresh_token) {
      throw new Error("Supabase did not return a refreshable sign-in session.");
    }
    const expiresAt = Number(nextSession.expires_at)
      ? Number(nextSession.expires_at) * 1000
      : Date.now() + Math.max(Number(nextSession.expires_in) || 3600, 60) * 1000;
    session = {
      accessToken: nextSession.access_token,
      refreshToken: nextSession.refresh_token,
      expiresAt
    };
    activeStorageKey = storageKey;
    accessToken = session.accessToken;
    localStorage.setItem(storageKey, JSON.stringify(session));
  }

  function clearStoredSession(storageKey) {
    localStorage.removeItem(storageKey);
    if (activeStorageKey === storageKey) {
      activeStorageKey = "";
      session = null;
      accessToken = "";
    }
  }

  function loadSession(storageKey) {
    const stored = localStorage.getItem(storageKey);
    if (!stored) return false;
    try {
      const saved = JSON.parse(stored);
      if (!saved || typeof saved.accessToken !== "string" || typeof saved.refreshToken !== "string") {
        clearStoredSession(storageKey);
        return false;
      }
      session = saved;
      activeStorageKey = storageKey;
      accessToken = saved.accessToken;
      return true;
    } catch (error) {
      clearStoredSession(storageKey);
      return false;
    }
  }

  async function ensureFreshSession() {
    if (!session || !activeStorageKey) throw new Error("Sign in to continue.");
    if (session.expiresAt > Date.now() + 30000) return;
    if (refreshPromise) {
      await refreshPromise;
      return;
    }
    refreshPromise = (async function () {
      const storageKey = activeStorageKey;
      const response = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=refresh_token`, {
        method: "POST",
        headers: { apikey: publishableKey, "Content-Type": "application/json" },
        body: JSON.stringify({ refresh_token: session.refreshToken })
      });
      if (!response.ok) {
        clearStoredSession(storageKey);
        throw await readResponse(response);
      }
      saveSession(await readResponse(response), storageKey);
      if (client) client.realtime.setAuth(accessToken);
    }());
    try {
      await refreshPromise;
    } finally {
      refreshPromise = null;
    }
  }

  async function request(path, options) {
    await ensureFreshSession();
    const response = await fetch(`${supabaseUrl}${path}`, {
      ...options,
      headers: {
        apikey: publishableKey,
        Authorization: `Bearer ${accessToken}`,
        ...(options && options.headers ? options.headers : {})
      }
    });
    return readResponse(response);
  }

  async function checkAdmin(token) {
    const response = await fetch(`${supabaseUrl}/rest/v1/rpc/is_log_admin`, {
      method: "POST",
      headers: {
        apikey: publishableKey,
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json"
      },
      body: "{}"
    });
    return readResponse(response) === true;
  }

  async function authenticateSession(token) {
    const response = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: { apikey: publishableKey, Authorization: `Bearer ${token}` }
    });
    return readResponse(response);
  }

  function showTracker() {
    loginPanel.hidden = true;
    tracker.hidden = false;
    signOutButton.hidden = false;
    adminTools.hidden = !isAdmin;
    boardUser = currentUser;
    boardCaption.textContent = isAdmin
      ? `Signed in as ${currentUser.email || "admin"}. Select a user to open their board.`
      : "Your private board, with progress and conversation kept together.";
  }

  async function restoreSession() {
    if (!supabaseUrl || !publishableKey || supabaseUrl.includes("YOUR-PROJECT-REF")) {
      setStatus(loginStatus, "Supabase is not configured for this site.", true);
      return;
    }

    for (const storageKey of [ownerSessionKey, trackerSessionKey]) {
      if (!loadSession(storageKey)) continue;
      try {
        await ensureFreshSession();
        currentUser = await authenticateSession(accessToken);
        isAdmin = await checkAdmin(accessToken);
        const correctKey = isAdmin ? ownerSessionKey : trackerSessionKey;
        if (correctKey !== activeStorageKey) {
          saveSession({
            access_token: session.accessToken,
            refresh_token: session.refreshToken,
            expires_at: session.expiresAt / 1000
          }, correctKey);
          clearStoredSession(storageKey);
        }
        showTracker();
        await initializeBoard();
        return;
      } catch (error) {
        console.error("Could not restore the Task Tracker session.", error);
        clearStoredSession(storageKey);
        setStatus(loginStatus, `Saved sign-in expired or could not be restored. ${error.message}`, true);
      }
    }
  }

  async function signIn(event) {
    event.preventDefault();
    setStatus(loginStatus, "");
    signInButton.disabled = true;
    try {
      if (!supabaseUrl || !publishableKey || supabaseUrl.includes("YOUR-PROJECT-REF")) {
        throw new Error("Supabase is not configured for this site.");
      }
      const response = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, {
        method: "POST",
        headers: { apikey: publishableKey, "Content-Type": "application/json" },
        body: JSON.stringify({
          email: document.getElementById("email").value.trim(),
          password: document.getElementById("password").value
        })
      });
      const nextSession = await readResponse(response);
      const admin = await checkAdmin(nextSession.access_token);
      const storageKey = admin ? ownerSessionKey : trackerSessionKey;
      saveSession(nextSession, storageKey);
      currentUser = nextSession.user || await authenticateSession(accessToken);
      isAdmin = admin;
      document.getElementById("password").value = "";
      setStatus(loginStatus, "");
      showTracker();
      await initializeBoard();
    } catch (error) {
      console.error("Task Tracker sign-in failed.", error);
      setStatus(loginStatus, error.message || "Sign-in failed. Check your account and database setup.", true);
    } finally {
      signInButton.disabled = false;
    }
  }

  async function signOut() {
    const keyToClear = activeStorageKey;
    let logoutError = null;
    try {
      await request("/auth/v1/logout", { method: "POST" });
    } catch (error) {
      logoutError = error;
      console.error("Supabase sign-out request failed.", error);
    }
    if (activeChannel && client) {
      await client.removeChannel(activeChannel);
      activeChannel = null;
    }
    if (keyToClear) clearStoredSession(keyToClear);
    currentUser = null;
    boardUser = null;
    isAdmin = false;
    tracker.hidden = true;
    loginPanel.hidden = false;
    signOutButton.hidden = true;
    if (logoutError) {
      setStatus(loginStatus, `Signed out on this device, but Supabase could not revoke the session: ${logoutError.message}`, true);
    } else {
      setStatus(loginStatus, "Signed out.");
    }
  }

  async function initializeBoard() {
    if (isAdmin) {
      try {
        await loadUsers();
      } catch (error) {
        console.error("Could not load registered Task Tracker users.", error);
        userCount.textContent = `User list unavailable: ${error.message}`;
        setStatus(boardStatus, `Could not load the user list. ${error.message}`, true);
      }
    }
    await loadBoard();
    subscribeToBoard();
  }

  async function loadUsers() {
    const listedUsers = await request("/rest/v1/rpc/get_task_tracker_users", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: "{}"
    });
    users = Array.isArray(listedUsers) ? listedUsers : [];
    userPicker.replaceChildren();

    const ownOption = document.createElement("option");
    ownOption.value = currentUser.id;
    ownOption.textContent = `My board (${currentUser.email || "admin"})`;
    userPicker.append(ownOption);
    users.forEach((user) => {
      if (user.id === currentUser.id) return;
      const option = document.createElement("option");
      option.value = user.id;
      option.textContent = user.email || `User ${user.id.slice(0, 8)}`;
      userPicker.append(option);
    });
    userCount.textContent = `${users.length} registered account${users.length === 1 ? "" : "s"}`;
  }

  function setBoardUser(userId) {
    if (!isAdmin || userId === currentUser.id) {
      boardUser = currentUser;
    } else {
      boardUser = users.find((user) => user.id === userId) || currentUser;
    }
    if (userPicker.value !== boardUser.id) userPicker.value = boardUser.id;
    boardCaption.textContent = boardUser.id === currentUser.id
      ? `Viewing ${isAdmin ? "your" : "private"} board${currentUser.email ? ` · ${currentUser.email}` : ""}.`
      : `Viewing ${boardUser.email || "user"}'s task board.`;
  }

  async function loadBoard(quiet) {
    if (!boardUser) return;
    const ownerId = boardUser.id;
    if (!quiet) setStatus(boardStatus, "Loading board...");
    try {
      const ownerFilter = `owner_id=eq.${encodeURIComponent(ownerId)}`;
      const [nextTasks, nextSubtasks, nextComments, nextActivity] = await Promise.all([
        request(`/rest/v1/task_tracker_tasks?select=*&${ownerFilter}&order=created_at.asc`),
        request(`/rest/v1/task_tracker_subtasks?select=*&${ownerFilter}&order=position.asc,created_at.asc`),
        request(`/rest/v1/task_tracker_comments?select=*&${ownerFilter}&order=created_at.asc`),
        request(`/rest/v1/task_tracker_activity?select=*&${ownerFilter}&order=created_at.desc&limit=80`)
      ]);
      if (!boardUser || boardUser.id !== ownerId) return;
      tasks = nextTasks;
      subtasks = nextSubtasks;
      comments = nextComments;
      activity = nextActivity;
      renderBoard();
      if (!quiet) setStatus(boardStatus, client ? "Live updates connected." : "Board loaded; live updates could not start.", !client);
    } catch (error) {
      console.error("Could not load the Task Tracker board.", error);
      setStatus(boardStatus, `Could not load this board. ${error.message}`, true);
    }
  }

  function subscribeToBoard() {
    if (!client) {
      setStatus(boardStatus, "Saved changes work, but the live update client did not load. Check your connection and reload.", true);
      return;
    }
    if (activeChannel) {
      client.removeChannel(activeChannel);
      activeChannel = null;
    }
    client.realtime.setAuth(accessToken);
    const subscribedOwnerId = boardUser.id;
    const channel = client.channel(`task-tracker-${subscribedOwnerId}-${Date.now()}`);
    ["task_tracker_tasks", "task_tracker_subtasks", "task_tracker_comments", "task_tracker_activity"].forEach((table) => {
      channel.on("postgres_changes", { event: "*", schema: "public", table }, (payload) => {
        const changedRow = payload.new && Object.keys(payload.new).length ? payload.new : payload.old;
        if (changedRow && changedRow.owner_id === subscribedOwnerId && boardUser && boardUser.id === subscribedOwnerId) {
          loadBoard(true);
        }
      });
    });
    activeChannel = channel.subscribe((status) => {
      if (boardUser && boardUser.id !== subscribedOwnerId) return;
      if (status === "SUBSCRIBED") {
        setStatus(boardStatus, "Live updates connected.");
      } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT" || status === "CLOSED") {
        setStatus(boardStatus, `Live updates disconnected (${status}). Reload the page to reconnect.`, true);
      }
    });
  }

  function formatDate(value, includeTime, timeZone) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return "";
    const options = includeTime
      ? { dateStyle: "medium", timeStyle: "short" }
      : { dateStyle: "medium" };
    if (timeZone) options.timeZone = timeZone;
    return new Intl.DateTimeFormat(undefined, options).format(date);
  }

  function getPhilippineDeadlineParts(value) {
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) return { date: "", time: "" };
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone: "Asia/Manila",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23"
    }).formatToParts(date);
    const values = {};
    parts.forEach((part) => {
      if (part.type !== "literal") values[part.type] = part.value;
    });
    return {
      date: `${values.year}-${values.month}-${values.day}`,
      time: `${values.hour}:${values.minute}`
    };
  }

  function toPhilippineDeadline(date, time) {
    if (!date) {
      if (time) throw new Error("Choose a deadline date before entering a time.");
      return null;
    }
    return new Date(`${date}T${time || "23:59"}:00+08:00`).toISOString();
  }

  function makeElement(tag, className, text) {
    const element = document.createElement(tag);
    if (className) element.className = className;
    if (text !== undefined) element.textContent = text;
    return element;
  }

  function renderBoard() {
    ["todo", "in_progress", "completed"].forEach((status) => {
      const list = document.querySelector(`[data-list-status="${status}"]`);
      const columnTasks = tasks.filter((task) => task.status === status);
      document.querySelector(`[data-count="${status}"]`).textContent = String(columnTasks.length);
      list.replaceChildren();
      if (!columnTasks.length) {
        list.append(makeElement("p", "empty-column", "Drop a task here or add a new one."));
      } else {
        columnTasks.forEach((task) => list.append(renderTask(task)));
      }
    });
    renderActivity();
  }

  function renderTask(task) {
    const card = makeElement("article", "task-card");
    card.dataset.taskId = task.id;
    card.draggable = true;

    const head = makeElement("div", "task-head");
    head.append(makeElement("h3", "", task.title));
    const actions = makeElement("div", "task-actions");
    const editButton = makeElement("button", "", "Edit");
    editButton.type = "button";
    editButton.dataset.action = "edit-task";
    editButton.dataset.taskId = task.id;
    const deleteButton = makeElement("button", "", "Delete");
    deleteButton.type = "button";
    deleteButton.dataset.action = "delete-task";
    deleteButton.dataset.taskId = task.id;
    actions.append(editButton, deleteButton);
    head.append(actions);
    card.append(head);

    const meta = makeElement("div", "task-meta");
    meta.append(makeElement("span", `priority priority-${task.priority}`, `${task.priority} priority`));
    if (task.deadline) {
      const deadline = makeElement("time", "deadline", `Due ${formatDate(task.deadline, true, "Asia/Manila")} PHT`);
      deadline.dateTime = task.deadline;
      if (task.status !== "completed" && new Date(task.deadline).getTime() < Date.now()) deadline.classList.add("is-overdue");
      meta.append(deadline);
    }
    card.append(meta);

    if (task.contents) card.append(makeElement("p", "task-contents", task.contents));

    const taskSubtasks = subtasks.filter((subtask) => subtask.task_id === task.id);
    if (taskSubtasks.length) {
      const completedCount = taskSubtasks.filter((subtask) => subtask.is_completed).length;
      const progress = makeElement("div", "task-progress");
      const label = makeElement("div", "progress-label");
      label.append(makeElement("span", "", "Subtask progress"));
      label.append(makeElement("span", "", `${completedCount}/${taskSubtasks.length} completed`));
      const track = makeElement("div", "progress-track");
      track.setAttribute("role", "progressbar");
      track.setAttribute("aria-label", "Subtask progress");
      track.setAttribute("aria-valuemin", "0");
      track.setAttribute("aria-valuemax", String(taskSubtasks.length));
      track.setAttribute("aria-valuenow", String(completedCount));
      const value = makeElement("div", "progress-value");
      value.style.width = `${Math.round(completedCount / taskSubtasks.length * 100)}%`;
      track.append(value);
      progress.append(label, track);
      card.append(progress);
    }

    const subtaskList = makeElement("div", "subtask-list");
    taskSubtasks.forEach((subtask) => {
      const row = makeElement("label", `subtask-row${subtask.is_completed ? " is-completed" : ""}`);
      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.checked = subtask.is_completed;
      checkbox.dataset.action = "toggle-subtask";
      checkbox.dataset.subtaskId = subtask.id;
      checkbox.setAttribute("aria-label", `${subtask.is_completed ? "Reopen" : "Complete"} ${subtask.title}`);
      row.append(checkbox, makeElement("span", "", subtask.title));
      const subtaskActions = makeElement("span", "subtask-actions");
      const renameButton = makeElement("button", "", "Rename");
      renameButton.type = "button";
      renameButton.dataset.action = "rename-subtask";
      renameButton.dataset.subtaskId = subtask.id;
      renameButton.dataset.title = subtask.title;
      renameButton.setAttribute("aria-label", `Rename ${subtask.title}`);
      const removeButton = makeElement("button", "", "×");
      removeButton.type = "button";
      removeButton.dataset.action = "delete-subtask";
      removeButton.dataset.subtaskId = subtask.id;
      removeButton.setAttribute("aria-label", `Remove ${subtask.title}`);
      subtaskActions.append(renameButton, removeButton);
      row.append(subtaskActions);
      subtaskList.append(row);
    });
    card.append(subtaskList);

    const cardActions = makeElement("div", "card-footer-actions");
    const addSubtaskButton = makeElement("button", "small-action-button", "＋ Add a subtask");
    addSubtaskButton.type = "button";
    addSubtaskButton.dataset.action = "add-subtask";
    addSubtaskButton.dataset.taskId = task.id;
    const moveButton = makeElement("button", "small-action-button move-button", "Move to…");
    moveButton.type = "button";
    moveButton.dataset.action = "move-task";
    moveButton.dataset.taskId = task.id;
    cardActions.append(addSubtaskButton, moveButton);
    card.append(cardActions);

    const details = document.createElement("details");
    details.className = "task-details";
    const summary = makeElement("summary", "", `Comments (${comments.filter((comment) => comment.task_id === task.id).length})`);
    details.append(summary, renderComments(task));
    card.append(details);
    return card;
  }

  function renderComments(task) {
    const wrapper = document.createElement("div");
    const taskComments = comments.filter((comment) => comment.task_id === task.id);
    const list = makeElement("ul", "comment-list");
    if (!taskComments.length) list.append(makeElement("li", "no-comments", "No comments yet."));
    taskComments.forEach((comment) => {
      const item = makeElement("li", "comment");
      const meta = makeElement("div", "comment-meta");
      meta.append(makeElement("strong", "", comment.author_email), makeElement("time", "", formatDate(comment.created_at, true)));
      const body = makeElement("p", "", comment.body);
      item.append(meta, body);
      list.append(item);
    });
    wrapper.append(list);

    const form = document.createElement("form");
    form.className = "comment-form";
    form.dataset.taskId = task.id;
    const input = document.createElement("input");
    input.name = "body";
    input.maxLength = 2000;
    input.required = true;
    input.placeholder = "Write a comment";
    input.setAttribute("aria-label", `Comment on ${task.title}`);
    const button = makeElement("button", "", "Send");
    button.type = "submit";
    form.append(input, button);
    wrapper.append(form);
    return wrapper;
  }

  function renderActivity() {
    boardActivity.replaceChildren();
    if (!activity.length) {
      boardActivity.append(makeElement("li", "no-activity", "No task activity yet."));
      return;
    }
    activity.slice(0, 16).forEach((entry) => {
      const item = makeElement("li", "activity-item");
      const detail = makeElement("p");
      detail.append(makeElement("strong", "", entry.task_title), document.createTextNode(` · ${entry.summary} · ${entry.actor_email}`));
      const time = makeElement("time", "", formatDate(entry.created_at, true));
      time.dateTime = entry.created_at;
      item.append(detail, time);
      boardActivity.append(item);
    });
  }

  function openTaskDialog(task) {
    editingTaskId = task ? task.id : null;
    document.getElementById("task-dialog-title").textContent = task ? "Edit task" : "New task";
    taskTitleInput.value = task ? task.title : "";
    taskContentsInput.value = task ? task.contents : "";
    taskPriorityInput.value = task ? task.priority : "medium";
    const deadlineParts = task && task.deadline
      ? getPhilippineDeadlineParts(task.deadline)
      : { date: "", time: "" };
    taskDeadlineDateInput.value = deadlineParts.date;
    taskDeadlineTimeInput.value = deadlineParts.time;
    taskStatusInput.value = task ? task.status : "todo";
    saveTaskButton.textContent = task ? "Save changes" : "Create task";
    setStatus(taskFormStatus, "");
    taskDialog.showModal();
    taskTitleInput.focus();
  }

  async function saveTask(event) {
    event.preventDefault();
    saveTaskButton.disabled = true;
    setStatus(taskFormStatus, "Saving...");
    try {
      const body = {
        owner_id: boardUser.id,
        title: taskTitleInput.value.trim(),
        contents: taskContentsInput.value.trim(),
        priority: taskPriorityInput.value,
        deadline: toPhilippineDeadline(taskDeadlineDateInput.value, taskDeadlineTimeInput.value),
        status: taskStatusInput.value
      };
      if (editingTaskId) {
        await request(`/rest/v1/task_tracker_tasks?id=eq.${encodeURIComponent(editingTaskId)}`, {
          method: "PATCH",
          headers: { "Content-Type": "application/json", Prefer: "return=minimal" },
          body: JSON.stringify(body)
        });
      } else {
        await request("/rest/v1/task_tracker_tasks", {
          method: "POST",
          headers: { "Content-Type": "application/json", Prefer: "return=minimal" },
          body: JSON.stringify(body)
        });
      }
      taskDialog.close();
      await loadBoard(true);
    } catch (error) {
      console.error("Could not save the task.", error);
      setStatus(taskFormStatus, error.message, true);
    } finally {
      saveTaskButton.disabled = false;
    }
  }

  async function updateTaskStatus(taskId, status) {
    const task = tasks.find((item) => item.id === taskId);
    if (!task || task.status === status) return true;
    try {
      await request(`/rest/v1/task_tracker_tasks?id=eq.${encodeURIComponent(taskId)}`, {
        method: "PATCH",
        headers: { "Content-Type": "application/json", Prefer: "return=minimal" },
        body: JSON.stringify({ status })
      });
      await loadBoard(true);
      return true;
    } catch (error) {
      console.error("Could not move the task.", error);
      setStatus(boardStatus, `Could not move task. ${error.message}`, true);
      return false;
    }
  }

  function openSubtaskDialog(taskId) {
    const task = tasks.find((item) => item.id === taskId);
    if (!task) return;
    addingSubtaskTaskId = taskId;
    document.getElementById("subtask-task-caption").textContent = `For “${task.title}”`;
    subtaskTitleInput.value = "";
    setStatus(subtaskFormStatus, "");
    subtaskDialog.showModal();
    subtaskTitleInput.focus();
  }

  function openMoveDialog(taskId) {
    const task = tasks.find((item) => item.id === taskId);
    if (!task) return;
    movingTaskId = taskId;
    document.getElementById("move-task-caption").textContent = `Move “${task.title}” to a different column.`;
    moveStatusInput.value = task.status;
    setStatus(moveFormStatus, "");
    moveDialog.showModal();
  }

  async function handleAction(button) {
    const taskId = button.dataset.taskId;
    if (button.dataset.action === "add-subtask") {
      openSubtaskDialog(taskId);
    } else if (button.dataset.action === "move-task") {
      openMoveDialog(taskId);
    } else if (button.dataset.action === "edit-task") {
      openTaskDialog(tasks.find((task) => task.id === taskId));
    } else if (button.dataset.action === "delete-task") {
      const task = tasks.find((item) => item.id === taskId);
      if (!task || !window.confirm(`Delete "${task.title}" and its subtasks and comments?`)) return;
      try {
        await request(`/rest/v1/task_tracker_tasks?id=eq.${encodeURIComponent(taskId)}`, { method: "DELETE" });
        await loadBoard(true);
      } catch (error) {
        console.error("Could not delete the task.", error);
        setStatus(boardStatus, `Could not delete task. ${error.message}`, true);
      }
    } else if (button.dataset.action === "rename-subtask") {
      const subtask = subtasks.find((item) => item.id === button.dataset.subtaskId);
      if (!subtask) return;
      const title = window.prompt("Rename subtask", subtask.title);
      if (title === null || !title.trim()) return;
      try {
        await request(`/rest/v1/task_tracker_subtasks?id=eq.${encodeURIComponent(subtask.id)}`, {
          method: "PATCH",
          headers: { "Content-Type": "application/json", Prefer: "return=minimal" },
          body: JSON.stringify({ title: title.trim() })
        });
        await loadBoard(true);
      } catch (error) {
        console.error("Could not rename the subtask.", error);
        setStatus(boardStatus, `Could not rename subtask. ${error.message}`, true);
      }
    } else if (button.dataset.action === "delete-subtask") {
      const subtask = subtasks.find((item) => item.id === button.dataset.subtaskId);
      if (!subtask || !window.confirm(`Remove "${subtask.title}"?`)) return;
      try {
        await request(`/rest/v1/task_tracker_subtasks?id=eq.${encodeURIComponent(subtask.id)}`, { method: "DELETE" });
        await loadBoard(true);
      } catch (error) {
        console.error("Could not remove the subtask.", error);
        setStatus(boardStatus, `Could not remove subtask. ${error.message}`, true);
      }
    }
  }

  async function addSubtask(event) {
    event.preventDefault();
    const title = subtaskTitleInput.value.trim();
    if (!title) return;
    saveSubtaskButton.disabled = true;
    setStatus(subtaskFormStatus, "Saving...");
    try {
      await request("/rest/v1/task_tracker_subtasks", {
        method: "POST",
        headers: { "Content-Type": "application/json", Prefer: "return=minimal" },
        body: JSON.stringify({ task_id: addingSubtaskTaskId, title })
      });
      subtaskDialog.close();
      await loadBoard(true);
    } catch (error) {
      console.error("Could not add the subtask.", error);
      setStatus(subtaskFormStatus, error.message, true);
    } finally {
      saveSubtaskButton.disabled = false;
    }
  }

  async function saveMove(event) {
    event.preventDefault();
    saveMoveButton.disabled = true;
    setStatus(moveFormStatus, "Saving...");
    const saved = await updateTaskStatus(movingTaskId, moveStatusInput.value);
    saveMoveButton.disabled = false;
    if (saved) moveDialog.close();
    else setStatus(moveFormStatus, boardStatus.textContent, true);
  }

  async function addComment(form) {
    const input = form.elements.body;
    const body = input.value.trim();
    if (!body) return;
    const button = form.querySelector("button");
    button.disabled = true;
    try {
      await request("/rest/v1/task_tracker_comments", {
        method: "POST",
        headers: { "Content-Type": "application/json", Prefer: "return=minimal" },
        body: JSON.stringify({ task_id: form.dataset.taskId, body })
      });
      input.value = "";
      await loadBoard(true);
    } catch (error) {
      console.error("Could not add the comment.", error);
      setStatus(boardStatus, `Could not add comment. ${error.message}`, true);
    } finally {
      button.disabled = false;
    }
  }

  loginForm.addEventListener("submit", signIn);
  signOutButton.addEventListener("click", signOut);
  document.getElementById("new-task").addEventListener("click", () => openTaskDialog(null));
  document.getElementById("close-task-dialog").addEventListener("click", () => taskDialog.close());
  document.getElementById("cancel-task").addEventListener("click", () => taskDialog.close());
  taskForm.addEventListener("submit", saveTask);
  document.getElementById("close-subtask-dialog").addEventListener("click", () => subtaskDialog.close());
  document.getElementById("cancel-subtask").addEventListener("click", () => subtaskDialog.close());
  subtaskForm.addEventListener("submit", addSubtask);
  document.getElementById("close-move-dialog").addEventListener("click", () => moveDialog.close());
  document.getElementById("cancel-move").addEventListener("click", () => moveDialog.close());
  moveForm.addEventListener("submit", saveMove);
  userPicker.addEventListener("change", async () => {
    setBoardUser(userPicker.value);
    await loadBoard();
    subscribeToBoard();
  });

  document.getElementById("board").addEventListener("click", (event) => {
    const button = event.target.closest("button[data-action]");
    if (button) handleAction(button);
  });
  document.getElementById("board").addEventListener("change", async (event) => {
    const target = event.target;
    if (target.matches('input[data-action="toggle-subtask"]')) {
      try {
        await request(`/rest/v1/task_tracker_subtasks?id=eq.${encodeURIComponent(target.dataset.subtaskId)}`, {
          method: "PATCH",
          headers: { "Content-Type": "application/json", Prefer: "return=minimal" },
          body: JSON.stringify({ is_completed: target.checked })
        });
        await loadBoard(true);
      } catch (error) {
        console.error("Could not update subtask progress.", error);
        setStatus(boardStatus, `Could not update subtask. ${error.message}`, true);
      }
    }
  });
  document.getElementById("board").addEventListener("submit", (event) => {
    if (event.target.matches(".comment-form")) {
      event.preventDefault();
      addComment(event.target);
    }
  });
  document.getElementById("board").addEventListener("dragstart", (event) => {
    const card = event.target.closest(".task-card");
    if (!card || !event.dataTransfer) return;
    event.dataTransfer.setData("text/plain", card.dataset.taskId);
    event.dataTransfer.effectAllowed = "move";
    card.classList.add("is-dragging");
  });
  document.getElementById("board").addEventListener("dragend", (event) => {
    const card = event.target.closest(".task-card");
    if (card) card.classList.remove("is-dragging");
    document.querySelectorAll(".board-column.is-drop-target").forEach((column) => column.classList.remove("is-drop-target"));
  });
  document.querySelectorAll(".board-column").forEach((column) => {
    column.addEventListener("dragover", (event) => {
      event.preventDefault();
      column.classList.add("is-drop-target");
      if (event.dataTransfer) event.dataTransfer.dropEffect = "move";
    });
    column.addEventListener("dragleave", (event) => {
      if (!column.contains(event.relatedTarget)) column.classList.remove("is-drop-target");
    });
    column.addEventListener("drop", async (event) => {
      event.preventDefault();
      column.classList.remove("is-drop-target");
      const taskId = event.dataTransfer && event.dataTransfer.getData("text/plain");
      if (taskId) await updateTaskStatus(taskId, column.dataset.dropStatus);
    });
  });

  restoreSession();
}());
