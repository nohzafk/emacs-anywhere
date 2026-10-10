--- === EmacsAnywhere ===
---
--- Edit text from any application in Emacs
---

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "EmacsAnywhere"
obj.version = "0.1.0"
obj.author = "randall"
obj.license = "MIT"

-- Configuration
obj.tmpdir = "/tmp/emacs-anywhere"
obj.emacsclient = "/opt/homebrew/bin/emacsclient"
obj.yabai = "/opt/homebrew/bin/yabai"

-- Extra arguments passed to every emacsclient call, before the Spoon's own.
-- Use them to reach a server that emacsclient does not find by default, e.g.
-- { "-f", "~/.emacs.d/server/server" } for a TCP server or { "-s", "work" }
-- for a named socket. A leading ~ is expanded to the home directory.
obj.emacsclientArgs = {}

-- Optional: function(callback) that makes sure an Emacs server is reachable,
-- then calls callback(). Set it to start Emacs on demand. When nil, the Spoon
-- checks for a running server and shows an alert if there is none.
obj.ensureEmacs = nil

-- Optional: function(args, callback) that runs emacsclient with args and calls
-- callback(exitCode, stdOut, stdErr). Set it to supply environment variables.
-- args already include obj.emacsclientArgs. When nil, the Spoon runs
-- obj.emacsclient directly.
obj.runEmacsclient = nil

-- State
obj.hotkey = nil
-- Note: previousApp and currentTmpFile are no longer stored globally
-- They are passed as parameters to support concurrent sessions

-- Seed random generator
math.randomseed(os.time())

--- EmacsAnywhere:checkIPC()
--- Method
--- Check if hs.ipc is loaded (required for Emacs callback)
function obj:checkIPC()
  -- Check if ipc module was explicitly loaded
  -- (can't just check hs.ipc as it lazy-loads)
  if not package.loaded["hs.ipc"] then
    return false
  end
  return true
end

--- EmacsAnywhere:isYabaiRunning()
--- Method
--- Check if yabai window manager is running
function obj:isYabaiRunning()
  -- Check if yabai binary exists and is running
  local handle = io.popen(self.yabai .. " -m query --spaces 2>/dev/null")
  local output = handle:read("*a")
  handle:close()
  return output and output ~= "" and output:match("%[")
end

--- EmacsAnywhere:focusEmacsAnywhereWindow()
--- Method
--- Use yabai to focus the emacs-anywhere window
function obj:focusEmacsAnywhereWindow()
  -- Query yabai for all windows
  local cmd = self.yabai .. " -m query --windows"
  local handle = io.popen(cmd)
  local output = handle:read("*a")
  handle:close()

  if not output or output == "" then
    return false
  end

  -- Parse JSON using Hammerspoon's json module
  local windows = hs.json.decode(output)
  if not windows then
    return false
  end

  -- Find the emacs-anywhere window
  for _, win in ipairs(windows) do
    if win.title == "emacs-anywhere" then
      os.execute(self.yabai .. " -m window --focus " .. win.id)
      return true
    end
  end

  return false
end

--- EmacsAnywhere:checkServer()
--- Method
--- Check if Emacs server is running
function obj:checkServer()
  local function quote(arg)
    return "'" .. arg:gsub("'", "'\\''") .. "'"
  end
  local words = { "TERM=xterm-256color", quote(self.emacsclient) }
  for _, arg in ipairs(self:_emacsclientArgs({ "-e", "(+ 1 1)" })) do
    table.insert(words, quote(arg))
  end
  local cmd = table.concat(words, " ") .. " 2>&1"
  local handle = io.popen(cmd)
  local output = handle:read("*a")
  handle:close()

  if output then
    output = output:gsub("%s+$", "") -- trim whitespace
  end

  -- If server is running, output should be "2"
  return output == "2"
end

-- obj.emacsclientArgs, with a leading ~ expanded, followed by args.
function obj:_emacsclientArgs(args)
  local home = os.getenv("HOME")
  local result = {}
  for _, arg in ipairs(self.emacsclientArgs or {}) do
    if home then
      arg = arg:gsub("^~/", home .. "/")
      if arg == "~" then arg = home end
    end
    table.insert(result, arg)
  end
  for _, arg in ipairs(args) do
    table.insert(result, arg)
  end
  return result
end

-- Call callback once an Emacs server is reachable.
function obj:_ensureEmacs(callback)
  if self.ensureEmacs then
    return self.ensureEmacs(callback)
  end
  if not self:checkServer() then
    hs.alert.show("Emacs server not running!\nStart with M-x server-start", 3)
    print("[EmacsAnywhere] Error: Emacs server not running")
    return
  end
  callback()
end

-- Run emacsclient with args; callback(exitCode, stdOut, stdErr).
function obj:_runEmacsclient(args, callback)
  args = self:_emacsclientArgs(args)
  if self.runEmacsclient then
    return self.runEmacsclient(args, callback)
  end
  local task = hs.task.new(self.emacsclient, callback, args)
  task:start()
  return task
end

--- EmacsAnywhere:start()
--- Method
--- Capture text and open in Emacs
function obj:start()
  -- Check if hs.ipc is loaded (required for Emacs callback)
  if not self:checkIPC() then
    hs.alert.show('hs.ipc not loaded!\nAdd require("hs.ipc") to init.lua', 4)
    print("[EmacsAnywhere] Error: hs.ipc not loaded")
    return
  end

  -- Capture caller context now, before any wait for Emacs, so the frontmost
  -- app and the selection are the ones at the moment the hotkey was pressed.
  local currentApp = hs.application.frontmostApplication()
  local appName = currentApp:name()
  local appBundleID = currentApp:bundleID() or appName  -- Fallback to name if no bundle ID

  -- Try to get selected text via Accessibility API (no clipboard, no beep)
  local text = ""
  local ax = hs.axuielement
  local systemElement = ax.systemWideElement()
  local focusedElement = systemElement:attributeValue("AXFocusedUIElement")

  if focusedElement then
    local selectedText = focusedElement:attributeValue("AXSelectedText")
    if selectedText and selectedText ~= "" then
      text = selectedText
    end
  end

  hs.timer.doAfter(0.05, function()
    -- Ensure temp directory exists
    os.execute("mkdir -p " .. self.tmpdir)

    -- Generate unique temp file name
    local safeName = appName:gsub("[^%w]", "-"):lower()
    local timestamp = os.time()
    local random = math.random(10000, 99999)
    self.currentTmpFile = string.format("%s/%s-%d-%d.txt", self.tmpdir, safeName, timestamp, random)

    -- Write to temp file
    local f = io.open(self.currentTmpFile, "w")
    if f then
      f:write(text)
      f:close()
    end

    -- Get mouse position for frame placement
    local mousePos = hs.mouse.absolutePosition()
    local mouseX = math.floor(mousePos.x)
    local mouseY = math.floor(mousePos.y)

    -- Open in Emacs (requires daemon or server-mode to be running)
    -- Dynamically load elisp from Spoon directory
    local elispFile = hs.spoons.resourcePath("emacs-anywhere.el")

    -- Build the elisp command that creates the emacs-anywhere frame
    -- Pass both app name (for display) and bundle ID (for reliable lookup)
    local elispTemplate =
      '(progn (load "%s") (emacs-anywhere-open "%s" "%s" "%s" %d %d %s))'

    -- Activating a hidden Emacs (Cmd-H) unhides it, which shows every one of
    -- its frames, so the elisp is told to park the other frames first. Read
    -- after ensureEmacs, which may just have launched Emacs.
    local function emacsHidden()
      local emacs = hs.application.get("org.gnu.Emacs")
      return emacs ~= nil and emacs:isHidden()
    end

    self:_ensureEmacs(function()
      local elispCmd = string.format(
        elispTemplate,
        elispFile,
        self.currentTmpFile,
        appName,
        appBundleID,
        mouseX,
        mouseY,
        emacsHidden() and "t" or "nil"
      )

      -- emacsclient options:
      --   -n (--no-wait): Return immediately, don't wait for frame to close
      --                   This enables multiple concurrent emacs-anywhere sessions
      --   -e (--eval): Evaluate the following elisp expression
      -- No -c: emacs-anywhere-open creates the frame itself, so it can record
      -- the other frames' visibility before the new frame activates Emacs.
      self:_runEmacsclient({ "-n", "-e", elispCmd }, function(exitCode, stdOut, stdErr)
        if exitCode ~= 0 then
          local output = stdErr ~= "" and stdErr or stdOut
          print("[EmacsAnywhere] Error: " .. output:gsub("%s+$", ""))
          hs.alert.show("Failed to open Emacs!\n" .. output:gsub("%s+$", ""), 3)
        end
      end)

      -- Use yabai to focus the emacs-anywhere window (fixes focus issue with yabai)
      if self:isYabaiRunning() then
        hs.timer.doAfter(0.1, function()
          self:focusEmacsAnywhereWindow()
        end)
      end
    end)
  end)
end

--- EmacsAnywhere:abort(appBundleID)
--- Method
--- Called by Emacs when editing is aborted. Just refocuses the original app.
--- Parameters:
---  * appBundleID - Bundle ID of the app to refocus
function obj:abort(appBundleID)
  -- Small delay to ensure Emacs frame is closed
  hs.timer.doAfter(0.1, function()
    -- Find and refocus the original app by bundle ID
    local targetApp = hs.application.get(appBundleID)
    if targetApp then
      targetApp:activate()
    end
  end)
end

--- EmacsAnywhere:finish(tmpFile, appBundleID)
--- Method
--- Called by Emacs when editing is done. Pastes content back and refocuses.
--- Parameters:
---  * tmpFile - Path to the temporary file containing the edited content
---  * appBundleID - Bundle ID of the app to paste into (e.g., "com.google.Chrome")
function obj:finish(tmpFile, appBundleID)
  -- Read the edited content from the specified file
  local f = io.open(tmpFile, "r")
  if not f then
    print("[EmacsAnywhere] Error: Could not read temp file: " .. tmpFile)
    return
  end
  local content = f:read("*all")
  f:close()

  -- Clean up temp file
  os.remove(tmpFile)

  -- Find the app by bundle ID (most reliable method)
  local targetApp = hs.application.get(appBundleID)
  if not targetApp then
    print("[EmacsAnywhere] Warning: Could not find app with bundle ID: " .. appBundleID)
    return
  end

  -- Save original clipboard contents
  local originalClipboard = hs.pasteboard.getContents()

  -- Put content in clipboard
  hs.pasteboard.setContents(content)

  -- Small delay to ensure Emacs frame is closed
  hs.timer.doAfter(0.1, function()
    -- Refocus the target app
    targetApp:activate()

    -- Wait for app to focus, then paste
    hs.timer.doAfter(0.1, function()
      hs.eventtap.keyStroke({ "cmd" }, "v")

      -- Restore original clipboard after paste
      hs.timer.doAfter(0.1, function()
        if originalClipboard then
          hs.pasteboard.setContents(originalClipboard)
        end
      end)
    end)
  end)
end

--- EmacsAnywhere:bindHotkeys(mapping)
--- Method
--- Bind hotkeys for EmacsAnywhere
---
--- Parameters:
---  * mapping - A table with keys "toggle" mapped to hotkey specs
---
--- Example:
---  spoon.EmacsAnywhere:bindHotkeys({toggle = {{"ctrl"}, "f8"}})
function obj:bindHotkeys(mapping)
  if mapping.toggle then
    if self.hotkey then
      self.hotkey:delete()
    end
    self.hotkey = hs.hotkey.bind(mapping.toggle[1], mapping.toggle[2], function()
      self:start()
    end)
  end
  return self
end

return obj
