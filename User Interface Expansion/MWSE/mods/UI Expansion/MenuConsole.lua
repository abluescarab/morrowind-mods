local GUI_ID_MenuConsole = tes3ui.registerID("MenuConsole")
local GUI_ID_MenuConsole_text_input = tes3ui.registerID("MenuConsole_text_input")
local GUI_ID_MenuConsole_scroll_pane = tes3ui.registerID("MenuConsole_scroll_pane")

local GUI_ID_UIEXP_ConsoleInputBox = tes3ui.registerID("UIEXP:ConsoleInputBox")

local common = require("UI Expansion.common")
local config = common.config

local luaMode = false
local currentHistoryIndex = 1
local previousConsoleEntries = config.previousConsoleEntries
if (previousConsoleEntries == nil) then
	previousConsoleEntries = { { text = "", lua = false } }
end

local sandbox = {}

local function updateScriptButton(button)
	if (luaMode) then
		button.text = "lua"
	else
		button.text = "mwscript"
	end
end

local function sandboxInit()
	setmetatable(sandbox, { __index = _G })
	sandbox.print = tes3ui.logToConsole
	event.trigger("UIEXP:sandboxConsole", { sandbox = sandbox })
end

local function sandboxScript(f)
	sandbox.currentRef = tes3ui.findMenu(GUI_ID_MenuConsole):getPropertyObject("MenuConsole_current_ref")
	setfenv(f, sandbox)
	return pcall(f)
end

local function onSubmitCommand()
	local menuConsole = tes3ui.findMenu(GUI_ID_MenuConsole)
	local inputBox = menuConsole:findChild(GUI_ID_UIEXP_ConsoleInputBox)
	local text = inputBox.text
	inputBox.text = ""

	if (luaMode) then
		tes3ui.logToConsole(text, true)
	end

	local context = (luaMode and "lua" or "mwscript")
	local e = event.trigger("UIEXP:consoleCommand", { command = text, context = context }, { filter = context })
	if (e) then
		text = e.command
	end

	if (not e or not e.block) then
		if (luaMode) then
			-- Try compiling command as an expression first.
			local f, message = loadstring("return " .. text)
			if (not f) then
				f, message = loadstring(text)
			end

			-- Run command and show output in console.
			if (f) then
				local results = { sandboxScript(f) }
				local status = results[1]
				if (status) then
					if (#results > 1) then
						-- Get all of our return values to print, but we have to conver them to strings first.
						local values = {}
						for i = 2, #results do
							values[i - 1] = tostring(results[i])
						end
						tes3ui.logToConsole(string.format("> %s", table.concat(values, ", ")))
					end
				else
					tes3ui.logToConsole(results[2])
				end
			else
				tes3ui.logToConsole(message)
			end
		else
			-- Any of the togglestats reporting outputs will destroy the text input,
			-- which is recreated on the next key input, so send one.
			menuConsole:triggerEvent("keyEnter")

			local vanillaInputText = menuConsole:findChild(GUI_ID_MenuConsole_text_input)
			vanillaInputText.text = text
			menuConsole:triggerEvent("keyEnter")
		end
	end

	local vanillaInputText = menuConsole:findChild(GUI_ID_MenuConsole_text_input)
	if (vanillaInputText) then
		vanillaInputText.visible = false
	end

	-- updateLayout twice, first to layout text, second to update scroll pane
	menuConsole:updateLayout()
	menuConsole:updateLayout()
	tes3ui.acquireTextInput(inputBox)

	-- Save last used console commands to the command history.
	if (text ~= "") then
		local lastEntry = previousConsoleEntries[#previousConsoleEntries]
		if (not lastEntry or lastEntry.text ~= text or lastEntry.lua ~= luaMode) then
			table.insert(previousConsoleEntries, { text = text, lua = luaMode })
			currentHistoryIndex = 1

			-- Save a selection of the history.
			local savedEntries = {}
			local previousConsoleEntriesCount = #previousConsoleEntries
			for i = math.max(1, previousConsoleEntriesCount - config.consoleHistoryLimit), previousConsoleEntriesCount do
				table.insert(savedEntries, previousConsoleEntries[i])
			end
			savedEntries[1] = { text = "", lua = false }
			config.previousConsoleEntries = savedEntries
			mwse.saveConfig("UI Expansion", config)
		end
	end
end

local function onMenuConsoleActivated(e)
	if (not e.newlyCreated) then
		tes3ui.acquireTextInput(e.element:findChild(GUI_ID_UIEXP_ConsoleInputBox))
		return
	end

	local menuConsole = e.element
	local mainPane = menuConsole:findChild(GUI_ID_MenuConsole_scroll_pane).parent
	mainPane.borderBottom = 0

	-- Disable normal input method.
	local vanillaInputText = menuConsole:findChild(GUI_ID_MenuConsole_text_input)
	vanillaInputText.visible = false

	-- Create a new input block for our new controls..
	local inputBlock = mainPane:createBlock{}
	inputBlock.flowDirection = "left_to_right"
	inputBlock.widthProportional = 1.0
	inputBlock.autoHeight = true
	inputBlock.borderTop = 4
	inputBlock.childAlignY = 0.5

	-- Create an input frame.
	local border = inputBlock:createThinBorder{}
	border.autoWidth = true
	border.autoHeight = true
	border.widthProportional = 1.0

	-- Create the command input.
	local input = border:createTextInput{ id = "UIEXP:ConsoleInputBox" }
	input.borderLeft = 5
	input.borderRight = 5
	input.borderTop = 2
	input.borderBottom = 4
	input.font = 1
	input.widget.lengthLimit = nil
	input.widget.eraseOnFirstKey = true
	input:register("keyEnter", onSubmitCommand)

	-- Create toggle button.
	local scriptToggleButton = inputBlock:createButton{ text = "mwscript" }
	scriptToggleButton.borderAllSides = 0
	scriptToggleButton.borderLeft = 4
	scriptToggleButton.minWidth = 90
	scriptToggleButton.width = 90
	scriptToggleButton:register("mouseClick", function()
		luaMode = not luaMode
		updateScriptButton(scriptToggleButton)
		menuConsole:updateLayout()
	end)
	local toggleText = scriptToggleButton.children[1]
	toggleText.wrapText = true
	toggleText.justifyText = "center"

	input:register("keyPress", function(e)
		local key = e.data0

		if (key == 9) then
			-- Prevent alt-tabbing from creating spacing.
			return
		elseif (key == -0x7FFFFFFD) then
			-- Pressing up goes to the previous entry in the history.
			currentHistoryIndex = currentHistoryIndex - 1
			if (currentHistoryIndex < 1) then
				currentHistoryIndex = #previousConsoleEntries
			end

			-- Add caret to allow immediate editing.
			input.text = previousConsoleEntries[currentHistoryIndex].text .. "|"
			luaMode = previousConsoleEntries[currentHistoryIndex].lua

			updateScriptButton(scriptToggleButton)
			menuConsole:updateLayout()
			return
		elseif (key == -0x7FFFFFFC) then
			-- Pressing down goes to the next entry in the history.
			currentHistoryIndex = currentHistoryIndex + 1
			if (currentHistoryIndex > #previousConsoleEntries) then
				currentHistoryIndex = 1
			end

			-- Add caret to allow immediate editing.
			input.text = previousConsoleEntries[currentHistoryIndex].text .. "|"
			luaMode = previousConsoleEntries[currentHistoryIndex].lua

			updateScriptButton(scriptToggleButton)
			menuConsole:updateLayout()
			return
		end

		input:forwardEvent(e)
	end)

	-- Make it so clicking on the border focuses the input box.
	input.consumeMouseEvents = false
	border:register("mouseClick", function()
		tes3ui.acquireTextInput(input)
	end)

	menuConsole:updateLayout()
	tes3ui.acquireTextInput(input)
end

sandboxInit()
event.register("uiActivated", onMenuConsoleActivated, { filter = "MenuConsole" })
