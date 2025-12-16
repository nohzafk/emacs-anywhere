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

-- State
obj.previousApp = nil
obj.hotkey = nil
obj.currentTmpFile = nil

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

--- EmacsAnywhere:checkServer()
--- Method
--- Check if Emacs server is running
function obj:checkServer()
  local cmd = self.emacsclient .. " -e '(+ 1 1)' 2>&1"
  local handle = io.popen(cmd)
  local output = handle:read("*a")
  handle:close()

  if output then
    output = output:gsub("%s+$", "") -- trim whitespace
  end

  -- If server is running, output should be "2"
  return output == "2"
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

  -- Check if Emacs server is running
  if not self:checkServer() then
    hs.alert.show("Emacs server not running!\nStart with M-x server-start", 3)
    print("[EmacsAnywhere] Error: Emacs server not running")
    return
  end

  -- Save the current application
  self.previousApp = hs.application.frontmostApplication()
  local appName = self.previousApp:name()
  local appBundleID = self.previousApp:bundleID()

  print("[EmacsAnywhere] Triggered from: " .. appName)

  -- Try to get selected text via Accessibility API (no clipboard, no beep)
  local text = ""
  local ax = hs.axuielement
  local systemElement = ax.systemWideElement()
  local focusedElement = systemElement:attributeValue("AXFocusedUIElement")

  if focusedElement then
    local selectedText = focusedElement:attributeValue("AXSelectedText")
    if selectedText and selectedText ~= "" then
      text = selectedText
      print("[EmacsAnywhere] Got selected text via AX: " .. #text .. " chars")
    else
      print("[EmacsAnywhere] No text selected (starting empty)")
    end
  else
    print("[EmacsAnywhere] No focused element found (starting empty)")
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

    -- Open in Emacs (no -c flag, elisp creates its own frame)
    local cmd = string.format(
      '%s -e \'(emacs-anywhere-open "%s" "%s" %d %d)\'',
      self.emacsclient,
      self.currentTmpFile,
      appName,
      mouseX,
      mouseY
    )
    print("[EmacsAnywhere] Running: " .. cmd)

    local handle = io.popen(cmd .. " 2>&1")
    local output = handle:read("*a")
    handle:close()

    -- Check for actual errors (not just nil return value)
    if output and output:match("ERROR") then
      hs.alert.show("Failed to open Emacs!\n" .. output, 3)
    end
  end)
end

--- EmacsAnywhere:finish()
--- Method
--- Called by Emacs when editing is done. Pastes content back and refocuses.
function obj:finish()
  print("[EmacsAnywhere] Finishing...")

  -- Read the edited content
  local f = io.open(self.currentTmpFile, "r")
  if not f then
    print("[EmacsAnywhere] Error: Could not read temp file: " .. tostring(self.currentTmpFile))
    return
  end
  local content = f:read("*all")
  f:close()

  -- Clean up temp file
  os.remove(self.currentTmpFile)

  -- Save original clipboard contents
  local originalClipboard = hs.pasteboard.getContents()

  -- Put content in clipboard
  hs.pasteboard.setContents(content)

  -- Small delay to ensure Emacs frame is closed
  hs.timer.doAfter(0.1, function()
    -- Refocus the original app
    if self.previousApp then
      self.previousApp:activate()

      -- Wait for app to focus, then paste
      hs.timer.doAfter(0.1, function()
        hs.eventtap.keyStroke({ "cmd" }, "v")

        -- Restore original clipboard after paste
        hs.timer.doAfter(0.1, function()
          if originalClipboard then
            hs.pasteboard.setContents(originalClipboard)
          end
          print("[EmacsAnywhere] Done!")
        end)
      end)
    end
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
