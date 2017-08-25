----------------------------------------------------------------
-- WIRES: An AsciiDots IDE for ComputerCraft
--
-- Copyright (C) 2017 InternetUnexplorer
-- All rights reserved.
--
-- This software may be modified and distributed under the terms
-- of the MIT license.  See the LICENSE file for details.
----------------------------------------------------------------

local worlds, currentWorld, currentWorldIndex

----------------------------------------------------------------
local World, Dot, tabs, status, theme, editor, focus, program
----------------------------------------------------------------

------------------------------------------------
-- Worlds
------------------------------------------------

World = {}

-- Opens a world
-- If a filepath is specified, the world will be loaded from that file, and
-- if the save is successful, the world's filepath will be updated
-- If the file exists but cannot be loaded, nil and the error message will be
-- returned
-- If no filepath is specified, or if the file does not exist, a
-- blank world will be returned
function World.open(filepath)
	local world = {
		lines  = {},
		warps  = {},
		starts = {},
		libs   = {},

		parent   = parent,
		filepath = filepath,

		cursorX = 1, cursorY = 1,
		cameraX = 0, cameraY = 0,

		loaded       = true,
		needsUpdate  = true,
		modified     = false,
	}

	if filepath and fs.exists(filepath) then
		world.isReadOnly = fs.isReadOnly(filepath)
		
		if fs.isDir(filepath) then
			return false, "File is a directory"
		end

		local f = fs.open(filepath, "r")

		if not f then
			return nil, "Cannot open file: "..filepath
		end

		for l in f.readLine do
			local line = {}

			for i = 1, l:len() do
				line[i] = l:sub(i, i)
			end

			table.insert(world.lines, {
				text = line,
				needsUpdate = true
			})
		end

		f.close()
	else
		world.isNewFile = true
		-- Worlds need to have at least one line, so add a blank one
		world.lines[1] = {
			text = {},
			needsUpdate = true
		}
	end

	return setmetatable(world, {__index = World})
end

-- Writes a world to a file
-- If filepath is not specified, the world's filepath will be used
-- Returns true, msg on success, false, msg on error
function World:write(filepath)
	filepath = filepath or self.filepath

	-- Trims trailing spaces
	local function trimEnd(string)
		return string:gsub("(.-)%s*$", "%1")
	end

	if fs.isReadOnly(filepath) then
		return false, "Permission denied"
	end

	if fs.isDir(filepath) then
		return false, "File is a directory"
	end

	local f = fs.open(filepath, "w")
	if not f then
		return false, "Cannot open file for writing"
	end

	for i = 1, #self.lines do
		f.writeLine(trimEnd(table.concat(self.lines[i].text)))
	end

	f.close()

	self.modified = false
	self.filepath = filepath

	return true, 'Saved to "'..fs.getName(filepath)..'"'
end

-- Updates the scopes and indexes for a single line in a world
function World:updateLine(lineNum)
	local line = self.lines[lineNum]
	local t = line.text
	local s = {}
	line.starts, line.warps, line.declaration = {}, {}

	local i = 1

	-- Declaration
	if t[1] == "%" then
		s[1] = "declaration"
		s[2] = "declaration"

		i = i + 2
		-- Warp declaration
		if t[2] == "$" then
			line.declaration = {
				type = "warp",
				warpNames = {}
			}
			-- Add the warp names
			while t[i] and t[i]:find "[A-Zb-z]" do
				table.insert(line.declaration.warpNames, t[i])
				s[i] = "declaration"
				i = i + 1
			end
		-- Library declaration
		elseif t[2] == "!" then
			local name = {}
			-- First get the name
			while t[i] and t[i] ~= " " do
				name[i-2] = t[i]
				s[i] = "declaration"
				i = i + 1
			end
			-- Next get the warp name
			if t[i] == " " and t[i+1] and t[i+1]:find "[A-Zb-z]" then
				s[i] = "whitespace"
				s[i+1] = "declaration"
				line.declaration = {
					type = "lib",
					name = table.concat(name),
					warpName = t[i+1]
				}
			else
				s[i+1] = "invalid"
			end
			i = i + 2
		-- Library warp declaration
		elseif t[2] == "^" then
			if t[i] and t[i]:find "[A-Zb-z]" then
				s[i] = "declaration"
				line.declaration = {
					type = "lib_warp",
					warpName = t[i]
				}
			else
				s[i] = "invalid"
			end
			i = i + 1
		-- Other (invalid) declaration
		else
			s[1] = "invalid"
			s[2] = "invalid"
		end
	end

	while i <= #t do
		local c = t[i]
		-- Whitespace
		if c == " " then
			s[i] = "whitespace"
		-- Comment
		elseif c == "`" and t[i+1] == "`" then
			-- Mark rest of line
			repeat
				s[i] = "comment"
				i = i + 1
			until i > #t
		-- String
		elseif c == "'" or c == '"' then
			-- Mark rest of string
			repeat
				s[i] = "string"
				i = i + 1
			until t[i] == c or i > #t
			-- Check whether we found a closing quote or hit EOL
			s[i] = t[i] == c and "string" or "invalid"
		-- Path
		elseif c:find "[|%-/\\%+><%^v%(%)]" then
			s[i] = "path"
		-- Control
		elseif c == "~" or c == "!" or c == "*" then
			s[i] = "control"
		-- Operation
		elseif c == "[" and t[i+2] == "]"
			or c == "{" and t[i+2] == "}" then
			s[i]   = "operator_bound"
			s[i+2] = "operator_bound"
			-- Check if middle character is an operator
			if (t[i+1] or ""):find "[%*%+%-%%%^/&!ox<>=\247\187\171\019]" then
				s[i+1] = "operator"
			else
				s[i+1] = "invalid"
			end
			i = i + 2
		-- Start
		elseif c == "." or c == "\7" then
			s[i] = "start"
			table.insert(line.starts, i)
		-- End
		elseif c == "&" then
			s[i] = "end"
		-- Digit
		elseif c:find "%d" then
			s[i] = "digit"
		-- Address & value
		elseif c == "@" or c == "#" then
			s[i] = "data"
		-- IO
		elseif c:find "[%?%$_a]" then
			s[i] = "io"
		-- Warp
		elseif c:find "[A-Zb-z]" then
			s[i] = "warp"
			table.insert(line.warps, i)
		-- Other (invalid) character
		else
			s[i] = "invalid"
		end
		i = i + 1
	end

	line.scopes = s
	line.needsUpdate = false
end

-- Updates the scopes and indexes for all of the lines in a world
-- Returns a list of line numbers for the lines which were changed
function World:updateAll()
	self.starts, self.warps, self.libWarp = {}, {}
	local changedLines = {}

	for i = 1, #self.lines do
		local line = self.lines[i]
		local changed = false

		if line.needsUpdate then
			self:updateLine(i)
			changed = true
		end

		local function mark(xPos, scope)
			if line.scopes[xPos] ~= scope then
				line.scopes[xPos] = scope
				changed = true
			end
		end

		for j = 1, #line.starts do
			table.insert(self.starts, {
				x = line.starts[j],
				y = i
			})
		end

		if line.declaration then
			local declaration = line.declaration

			if declaration.type == "warp" then
				for j = 1, #declaration.warpNames do
					local warpName = declaration.warpNames[j]
					local warpXPos = j + 2 -- %$

					if self.warps[warpName] then
						-- Warp already declared
						mark(warpXPos, "invalid")
					else
						-- Create a table for this warp and add the
						-- declaration as the first element
						self.warps[warpName] = {{
							x = warpXPos,
							y = i
						}}
						mark(warpXPos, "declaration")
					end
				end
			elseif declaration.type == "lib" then
				local filepath = shell.resolve(declaration.name)
				local warpName = declaration.warpName
				local warpXPos = filepath:len() + 4 -- %!, name, and a space

				if self.warps[warpName] then
					mark(warpXPos, "invalid")
				else
					self.warps[warpName] = {
						lib = filepath,
						{
							x = warpXPos,
							y = i
						}
					}
					mark(warpXPos, "declaration")
				end
			elseif declaration.type == "lib_warp" then
				local warpName = declaration.warpName
				local warpXPos = 3 -- %^

				if self.libWarp or self.warps[warpName] then
					mark(warpXPos, "invalid")
				else
					self.libWarp = {
						libWarp = true,
						{
							x = warpXPos,
							y = i
						}
					}
					self.warps[warpName] = self.libWarp
					mark(warpXPos, "declaration")
				end
			end
		end

		for j = 1, #line.warps do
			local warpXPos = line.warps[j]
			local warpName = line.text[warpXPos]

			if self.warps[warpName] then
				local warp = self.warps[warpName]

				-- If it is a lib warp, it cannot have been seen
				-- anywhere (other than its declaration) already
				if not warp.libWarp or #warp == 1 then
					table.insert(warp, {
						x = warpXPos,
						y = i
					})
					mark(warpXPos, "warp")
				else
					mark(warpXPos, "invalid")
				end
			else
				-- Warp doesn't exist
				mark(warpXPos, "invalid")
			end
		end

		if changed then
			table.insert(changedLines, i)
		end
	end

	self.needsUpdate = false

	return changedLines
end

------------------------------------------------
-- Theme
------------------------------------------------

theme = {
	editor = {
		["default"]        = { fg = "0",
		                       bg = "f" },
		["declaration"]    = { fg = "9" },
		["comment"]        = { fg = "d" },
		["string"]         = { fg = "d" },
		["control"]        = { fg = "2" },
		["operator_bound"] = { fg = "8" },
		["operator"]       = { fg = "2" },
		["start"]          = { fg = "3" },
		["end"]            = { fg = "3" },
		["digit"]          = { fg = "4" },
		["data"]           = { fg = "3" },
		["io"]             = { fg = "3" },
		["warp"]           = { fg = "3" },
		["invalid"]        = { fg = "e" },
		["dot"]            = { fg = "e",
		                       bg = "f" },
	},
	tabs = {
		["selected"] = { fg = "0", bg = "f" },
		["normal"]   = { fg = "f", bg = "7" },
	},
	status = {
		["default"]   = { fg = "0", bg = "f" },
		["view_mode"] = {},
		["edit_mode"] = {},
		["prompt"]    = {},
		["info_msg"]  = { fg = "5" },
		["error_msg"] = { fg = "e" },
		["confirm"]   = { fg = "4" },
	}
}

-- Converts a color from hex to its decimal representation
function theme.toDecimal(hexColor)
	return math.pow(2, tonumber(hexColor, 16))
end

------------------------------------------------
-- Dots
------------------------------------------------

Dot = {}

-- Creates a new dot
function Dot:new(world, x, y)
	return setmetatable({
		world = world,
		x = x,
		y = y,
	}, {
		__index = Dot
	})
end

------------------------------------------------
-- Program
------------------------------------------------

program = {}

-- Starts the program
function program.run()

end

-- Halts the program
function program.halt()

end

------------------------------------------------
-- Tab Bar
------------------------------------------------

tabs = {
	cameraX = 0
}

-- Draws the tab bar to the screen
function tabs.draw()
	local term  = tabs.window
	local width = term.getSize()

	local camX = tabs.cameraX

	local tx, fg, bg = {}, {}, {}

	for i = 1, #worlds do
		local text, color = tabs.getTabText(i)
		if i == currentWorldIndex then
			if #tx - camX + text:len() > width then
				camX = #tx - text:len()
			end
			if #tx < camX-1 then
				camX = #tx-1
			end
			color = theme.tabs.selected
		else
			color = theme.tabs.normal
		end
		for j = 1, text:len() do
			table.insert(tx, text:sub(j, j))
			table.insert(fg, color.fg)
			table.insert(bg, color.bg)
		end
	end

	if #tx - camX < width then
		camX = #tx - width
	end
	if camX < 0 then
		camX = 0
	end

	for i = #tx, width-camX do
		table.insert(tx, " ")
		table.insert(fg, theme.tabs.normal.fg)
		table.insert(bg, theme.tabs.normal.bg)
	end

	term.setCursorPos(1, 1)
	term.blit(table.concat(tx, "", camX+1, width+camX)
	         ,table.concat(fg, "", camX+1, width+camX)
	         ,table.concat(bg, "", camX+1, width+camX))
end

-- Returns the text for the tab at index
function tabs.getTabText(index)
	local world = worlds[index]
	return " "
		..(world.filepath and fs.getName(world.filepath) or "untitled")
		..(world.modified and "\007" or "")
		.." "
end

-- Cycles to the next tab
function tabs.nextTab()
	tabs.switch(currentWorldIndex < #worlds and currentWorldIndex + 1 or 1)
end

-- Switches to the tab at index
function tabs.switch(index)
	currentWorldIndex = math.min(#worlds, math.max(index, 1))
	currentWorld = worlds[currentWorldIndex]
	tabs.needsDraw = true
	editor.needsDraw = true
	status.clearMessages()
end

------------------------------------------------
-- Status Bar
------------------------------------------------

status = {
	messages = {},
	mode = "normal",
}

-- Draws the status bar to the screen
function status.draw()
	local term  = status.window
	local width = term.getSize()

	local text, color

	if status.mode == "message" then
		local msg = status.messages[1]
		if msg.isError then
			color = theme.status.error_msg
		else
			color = theme.status.info_msg
		end
		text = msg.text
		-- Truncate message if it is too long
		if text:len() > width then
			text = text:sub(1, width-3).."..."
		end
	elseif status.mode == "prompt" then
		local prompt = status.prompt
		if prompt.isConfirm then
			color = theme.status.confirm
			text = prompt.text.." (y/n)"
		else
			color = theme.status.prompt
			local camX, curX = prompt.cameraX, prompt.cursorX
			local pText, pBuf = prompt.text..": ", prompt.buffer
			-- Bound the cursor
			if curX < 1 then
				curX = 1
			elseif curX > #pBuf+1 then
				curX = #pBuf+1
			end
			-- Bound the camera
			if camX >= curX then
				camX = curX - 1
			elseif curX > camX + width - pText:len() then
				camX = curX - width + pText:len()
			end
			-- Save the bounded values
			prompt.cameraX, prompt.cursorX = camX, curX

			local x1, x2 = camX+1, math.min(width+camX-pText:len(), #pBuf)
			text = pText..table.concat(pBuf, "", x1, x2)
		end
	elseif status.mode == "normal" then
		local rText, lText
		-- Get the mode text
		if editor.mode == "view" then
			rText = (program.isRunning and " RUNNING" or " READY")
			color = theme.status.view_mode
		else
			rText = (editor.isReplace and " REPLACE" or " INSERT")
			color = theme.status.edit_mode
		end
		-- Get the file text
		if currentWorld.filepath then
			local filename, filemods = fs.getName(currentWorld.filepath)
			if currentWorld.isNewFile then
				filemods = " [New File]"
			elseif currentWorld.isReadOnly then
				filemods = " [Read-Only]"
			end
			-- Truncate the filename if it is too long
			local maxFLen = width - rText:len() - 2 - (filemods or ""):len()
			if filename:len() > maxFLen then
				filename = filename:sub(1, maxFLen-3).."..."
			end
			lText = '"'..filename..'"'..(filemods or "")
		else
			lText = "[New File]"
		end
		-- Pad out rText with spaces
		if lText:len() + rText:len() < width then
			lText = lText..string.rep(" ", width-lText:len()-rText:len())
		end
		text = lText..rText
	end
	local fgColor = (color or {}).fg or theme.status.default.fg
	local bgColor = (color or {}).bg or theme.status.default.bg
	-- Draw the text
	term.setCursorPos(1, 1)
	term.setTextColor(theme.toDecimal(fgColor))
	term.setBackgroundColor(theme.toDecimal(bgColor))
	term.clearLine()
	term.write(text)
end

-- Handles events when the status bar is focused
function status.handleEvent(event, p1, p2, p3, shiftDown, ctrlDown)
	if status.mode == "prompt" then
		local p = status.prompt
		if p.isConfirm then
			if event == "char" then
				status.closePrompt(p1 == "y" or p1 == "Y")
			end
		else
			if event == "key" then
				if     p1 == keys.right  then p.cursorX = p.cursorX + 1
				elseif p1 == keys.left   then p.cursorX = p.cursorX - 1
				elseif p1 == keys.home   then p.cursorX = 1
				elseif p1 == keys["end"] then p.cursorX = #p.buffer + 1

				elseif p1 == keys.backspace then status.pBackspace()
				elseif p1 == keys.delete    then status.pDelete()
				elseif p1 == keys.enter     then status.closePrompt(true)
				elseif p1 == keys.escape    then status.closePrompt(false)
				end
				status.needsDraw = true
			elseif event == "char" then
				table.insert(p.buffer, p.cursorX, p1)
				p.cursorX   = p.cursorX + 1
				status.needsDraw = true
			end
		end
	end
end

-- Shows a prompt with text promptText
-- If isConfirm is true, then the prompt will be a yes/no confirmation prompt
-- Otherwise, the user will be prompted to enter text
-- If the prompt is submitted (enter or y for a confirmation prompt), the
-- onSubmit function is called
-- If not a confirmation prompt, the text the user typed is passed to this
-- onSubmit function as the first argument
-- If the prompt is cancelled (by pressing ESC or pressing backspace while
-- there is no text in the buffer, or by pressing a character other than y
-- for a confirmation prompt) then the onCancel function is called
function status.showPrompt(promptText, isConfirm, onSubmit, onCancel)
	status.mode = "prompt"
	status.prompt = {
		text = promptText,
		isConfirm = isConfirm,
		buffer = {},
		cameraX = 1,
		cursorX = 1,
		onCancel = onCancel,
		onSubmit = onSubmit,
		returnFocus = focus
	}
	focus = "status"
	status.needsDraw = true
end

-- Closes the prompt that is currently being shown
-- If submit is true, the prompt will be submitted
-- Otherwise, it will be cancelled
function status.closePrompt(submit)
	local prompt = status.prompt
	status.prompt = nil
	status.clearMessages()
	focus = prompt.returnFocus
	if submit and prompt.onSubmit then
		prompt.onSubmit(not prompt.isConfirm and table.concat(prompt.buffer))
	elseif not submit and prompt.onCancel then
		prompt.onCancel()
	end
end

-- Deletes the character behind the prompt's cursor, or cancels the prompt if
-- there are no characters left in the buffer
function status.pBackspace()
	local prompt = status.prompt
	if #prompt.buffer > 0 then
		if prompt.buffer[prompt.cursorX-1] then
			table.remove(prompt.buffer, prompt.cursorX-1)
			prompt.cursorX = prompt.cursorX - 1
		end
	else
		status.closePrompt(false)
	end
end

-- Deletes the character in front of the prompt's cursor
function status.pDelete()
	local prompt = status.prompt
	if prompt.buffer[prompt.cursorX] then
		table.remove(prompt.buffer, prompt.cursorX)
	end
end

-- Queues an error message
function status.error(text)
	status.msg(text, true)
end

-- Queues a regular (info) message
function status.info(text)
	status.msg(text, false)
end

-- Queues a message
function status.msg(text, isError)
	table.insert(status.messages, {
		text = text,
		isError = isError
	})
	if status.mode == "normal" then
		status.mode = "message"
		status.resetMessageTimer()
		status.needsDraw = true
	end
end

-- Cycles to the next message, or sets the mode back to normal if there are
-- no more messages in the queue
function status.nextMessage()
	table.remove(status.messages)
	if #status.messages == 0 then
		status.mode = "normal"
	else
		status.resetMessageTimer()
	end
	status.needsDraw = true
end

-- Clears all of the messages in the queue and sets the mode back to normal
function status.clearMessages()
	status.messages = {}
	status.messageTimer = nil
	status.mode = "normal"
	status.needsDraw = true
end

-- Starts a new timer for the current message
function status.resetMessageTimer()
	status.messageTimer = os.startTimer(2)
end

-- Grabs the cursor, as it may have been moved while drawing other areas of
-- the screen
function status.grabCursor()
	if status.mode == "prompt" and not status.prompt.isConfirm then
		status.window.restoreCursor()
		status.window.setCursorBlink(true)
		local p = status.prompt
		status.window.setCursorPos(p.cursorX-p.cameraX+p.text:len()+2, 1)
	else
		status.window.setCursorBlink(false)
	end
end

------------------------------------------------
-- Editor
------------------------------------------------

editor = {
	mode = "view"
}

-- Draws the current world to the window
function editor.draw()
	local world = currentWorld
	local term  = editor.window
	local width, height = term.getSize()
	local camX, camY = world.cameraX, world.cameraY

	-- Bound the camera
	if camY > #world.lines-height then
		camY = #world.lines-height
	end
	if camY < 0 then
		camY = 0
	end
	if camX > #world.lines[world.cursorY].text-width+1 then
		camX = #world.lines[world.cursorY].text-width+1
	end
	if camX < 0 then
		camX = 0
	end
	world.cameraX, world.cameraY = camX, camY

	-- Use a buffer to avoid repeatedly concatenating strings
	local buffer = {}

	for y = 1, math.min(height, #world.lines-camY) do
		local line, tx, fg, bg = world.lines[y+camY], {}, {}, {}
		for x = 1, math.min(width, #line.text-camX) do
			local s = line.scopes[x+camX]
			tx[x] = line.text[x+camX]
			fg[x] = (theme.editor[s] or {}).fg or theme.editor.default.fg
			bg[x] = (theme.editor[s] or {}).bg or theme.editor.default.bg
		end
		buffer[y] = { tx = tx, fg = fg, bg = bg }
	end

	-- Draw the buffer to the window
	term.clear()
	for y = 1, #buffer do
		term.setCursorPos(1, y)
		term.blit(table.concat(buffer[y].tx)
		         ,table.concat(buffer[y].fg)
		         ,table.concat(buffer[y].bg))
	end
end

-- Adds a world to the worlds table
-- If the current world is not modified and a new file, it will be replaced
-- Otherwise, the world will be added as a new tab
function editor.addWorld(world)
	if currentWorld.isNewFile and not currentWorld.modified then
		worlds[currentWorldIndex] = world
		tabs.switch(currentWorldIndex)
	else
		table.insert(worlds, world)
		if world.filepath then
			worlds[world.filepath] = world
		end
		tabs.switch(#worlds)
	end
end

-- Returns the world with filepath in the worlds table
function editor.getWorldByFilepath(filepath)
	return worlds[filepath]
end

-- Returns the world at index in the worlds table
function editor.getWorldByIndex(index)
	return worlds[index]
end

-- Removes a world from the worlds table by its filepath
-- Note that this does not update the tabs, editor, or status
function editor.removeWorldByFilepath(filepath) 
	for i = 1, #worlds do
		if worlds[i] == worlds[filepath] then
			table.remove(worlds, i)
			break
		end
	end
	worlds[filepath] = nil
end

-- Removes a world from the worlds table by its index
function editor.removeWorldByIndex(index)
	if worlds[index].filepath then
		worlds[worlds[index].filepath] = nil
	end
	table.remove(worlds, index)
end


-- Opens a new world
function editor.new()
	editor.addWorld(World.open())
end

-- Opens the world with filename, or prompts for a filename if none is
-- provided
function editor.open(filename)
	local function load(filename)
		local filepath   = shell.resolve(filename)
		local world, msg = World.open(filepath)
		if world then
			editor.addWorld(world)
		else
			status.error(msg)
		end
	end
	if filename then
		load(filename)
	else
		status.showPrompt("Open", false, load)
	end
end

-- Closes the current world, prompting the user if there are unsaved changes
-- If quitAfter is true, the program will quit after the world is closed
function editor.close(quitAfter)
	if currentWorld.modified then
		status.showPrompt("Discard changes?", true, function()
			currentWorld.modified = false
			editor.close(quitAfter)
		end)
	else
		editor.removeWorldByIndex(currentWorldIndex)
		if #worlds == 0 or quitAfter then
			editor.quit()
		else
			tabs.switch(currentWorldIndex - 1)
		end
	end
end

-- Closes open worlds and then quits the program
function editor.quit()
	-- Check if any worlds have unsaved changes
	for i = 1, #worlds do
		if worlds[i].modified then
			tabs.switch(i)
			editor.close(true)
			return
		end
	end
	focus = "quit"
end

-- Saves the current world
-- If filepath is not specified and the world does not already have a
-- filepath, editor.saveAs() is called
function editor.save(filepath)
	if currentWorld.modified or filepath then
		if not (filepath or currentWorld.filepath) then
			editor.saveAs()
		else
			local success, msg = currentWorld:write(filepath)
			status.msg(msg, not success)
			tabs.needsDraw = true
		end
	end
end

-- Prompts the user for a filepath, and saves the current world there
function editor.saveAs()
	local function onSubmit(filename)
		local filepath = shell.resolve(filename)
		if fs.exists(filepath) and not fs.isDir(filepath) then
			status.showPrompt("File exists, overwrite?", true, function()
				editor.save(filepath)
			end)
		else
			editor.save(filepath)
		end
	end

	status.showPrompt("Save as", false, onSubmit)
end
	
-- Sets the cursor position to the relative coordinates x, y
function editor.moveCursor(x, y)
	editor.setCursor(currentWorld.cursorX+x, currentWorld.cursorY+y)
end

-- Sets the cursor position to the absolute coordinates x, y
function editor.setCursor(x, y)
	-- Bound cursor
	if y > #currentWorld.lines then
		y = #currentWorld.lines
	elseif y < 1 then
		y = 1
	end
	if x > #currentWorld.lines[y].text+1 then
		x = #currentWorld.lines[y].text+1
	elseif x < 1 then
		x = 1
	end
	-- Set cursor
	currentWorld.cursorX, currentWorld.cursorY = x, y
	-- Move camera to cursor
	local width, height = editor.window.getSize()
	local camX, camY
	if currentWorld.cameraX >= x then
		camX = x-1
	elseif x-width > currentWorld.cameraX then
		camX = x-width
	end
	if currentWorld.cameraY >= y then
		camY = y-1
	elseif y-height > currentWorld.cameraY then
		camY = y-height
	end
	if camX or camY then
		-- Camera was moved, apply movement
		editor.setCamera(camX or currentWorld.cameraX
			            ,camY or currentWorld.cameraY)
	else
		-- No camera movement needed, just set cursor position
		editor.window.setCursorPos(currentWorld.cursorX-currentWorld.cameraX
		                          ,currentWorld.cursorY-currentWorld.cameraY)
	end
end

-- Sets the camera position to the relative coordinates x, y
function editor.moveCamera(x, y)
	editor.setCamera(currentWorld.cameraX+x, currentWorld.cameraY+y)
end

-- Sets the camera position to the absolute coordinates x, y
function editor.setCamera(x, y)
	currentWorld.cameraX, currentWorld.cameraY = x, y
	editor.needsDraw = true
end

-- Moves the camera or the cursor to the relative coordinates x, y
-- The type of movement is dependent on the current editor mode
function editor.move(x, y)
	(editor.mode == "edit" and editor.moveCursor or editor.moveCamera)(x, y)
	status.clearMessages()
end

-- Inserts a newline at the current cursor position
function editor.enter()
	local curX, curY = currentWorld.cursorX, currentWorld.cursorY
	local text = currentWorld.lines[curY].text
	
	-- Split the text at the cursor position into text1, text2
	local text1, text2 = {}, {}
	for i = 1, curX-1 do
		text1[i] = text[i]
	end
	for i = 1, #text-curX+1 do
		text2[i] = text[curX+i-1]
	end

	-- Set the current line's text to text1
	currentWorld.lines[curY].text = text1
	editor.lineChanged()
	-- Add text2 as a new line
	table.insert(currentWorld.lines, curY+1, { text = text2 })
	editor.setCursor(1, curY+1)
	editor.lineChanged()
end

-- Deletes the character behind the cursor
function editor.backspace()
	local curX, curY = currentWorld.cursorX, currentWorld.cursorY
	local text = currentWorld.lines[curY].text

	if curX > 1 then
		table.remove(text, curX-1)
		editor.moveCursor(-1, 0)
		editor.lineChanged()
	elseif curY > 1 then
		editor.joinLines(curY-1, curY)
	end
end

-- Deletes the character in front of the cursor
function editor.delete()
	local curX, curY = currentWorld.cursorX, currentWorld.cursorY
	local text = currentWorld.lines[curY].text

	if curX <= #text then
		table.remove(text, curX)
		editor.lineChanged()
	elseif curY < #currentWorld.lines then
		editor.joinLines(curY, curY+1)
	end
end

-- Moves the line at lineNum2 to the end of the line at lineNum1
function editor.joinLines(lineNum1, lineNum2)
	local curX  = currentWorld.cursorX
	local text1 = currentWorld.lines[lineNum1].text
	local text2 = currentWorld.lines[lineNum2].text

	editor.setCursor(#text1+1, lineNum1)
	for i = 1, #text2 do
		text1[#text1+1] = text2[i]
	end
	editor.lineChanged()

	table.remove(currentWorld.lines, lineNum2)
end

-- Inserts or replaces a character depending on the editor mode
function editor.insert(char)
	local text = currentWorld.lines[currentWorld.cursorY].text
	local curX = currentWorld.cursorX
	if editor.isReplace then
		text[curX] = char
	else
		table.insert(text, curX, char)
	end
	editor.moveCursor(1, 0)
	editor.lineChanged()
end

-- Toggles editor mode between insert and replace
function editor.toggleInsertMode()
	editor.isReplace = not editor.isReplace
	status.clearMessages()
end

-- Marks a line as changed
-- If lineNum is not specified, the line the cursor is on will be used
function editor.lineChanged(lineNum)
	lineNum = lineNum or currentWorld.cursorY
	currentWorld.lines[lineNum].needsUpdate = true
	currentWorld.needsUpdate = true
	currentWorld.modified = true
	editor.needsDraw = true
	status.clearMessages()
end

-- Toggles the editor mode between view and edit
function editor.switchMode()
	program.halt()
	editor.mode = editor.mode == "edit" and "view" or "edit"
	editor.needsDraw = true
	status.needsDraw = true
end

-- Handles events when the editor is focused
function editor.handleEvent(event, p1, p2, p3, shiftDown, ctrlDown)
	local world = currentWorld
	local curX, curY = world.cursorX, world.cursorY
	local line  = world.lines[curY]
	local text  = line.text

	if event == "key" then
		if ctrlDown and not shiftDown then
			if     p1 == keys.tab then tabs.nextTab()
			elseif p1 == keys.n   then editor.new()
			elseif p1 == keys.o   then editor.open()
			elseif p1 == keys.s   then editor.save()
			elseif p1 == keys.q   then editor.quit()
			elseif p1 == keys.w   then editor.close()
			end
		elseif ctrlDown and shiftDown then
			if p1 == keys.s then editor.saveAs()
			end
		else
			if     p1 == keys.tab   then editor.switchMode()
			elseif p1 == keys.up    then editor.move(0, -1)
			elseif p1 == keys.down  then editor.move(0,  1)
			elseif p1 == keys.left  then editor.move(-1, 0)
			elseif p1 == keys.right then editor.move(1,  0)

			elseif editor.mode == "edit" then
				if     p1 == keys.home   then editor.setCursor(1, curY)
				elseif p1 == keys["end"] then editor.setCursor(#text+1, curY)

				elseif p1 == keys.backspace then editor.backspace()
				elseif p1 == keys.delete    then editor.delete()
				elseif p1 == keys.enter     then editor.enter()
				
				elseif p1 == keys.insert then editor.toggleInsertMode()
				end
			end
		end
	elseif event == "char" then
		if editor.mode == "edit" then editor.insert(p1) end
	elseif event == "timer" then
		if p1 == status.messageTimer then status.nextMessage() end
	end
end

-- Resizes the tabs, editor, and status windows
function editor.resizeWindows()
	local width, height = term.getSize()
	tabs.window.reposition(1, 1, width, 1)
	editor.window.reposition(1, 2, width, height-2)
	status.window.reposition(1, height, width, 1)
	tabs.needsDraw = true
	editor.needsDraw = true
	status.needsDraw = true
end

-- Grabs the cursor, as it may have been moved while drawing other areas of
-- the screen
function editor.grabCursor()
	if editor.mode == "edit" then
		editor.window.restoreCursor()
		editor.window.setCursorBlink(true)
		editor.window.setCursorPos(currentWorld.cursorX-currentWorld.cameraX
		                          ,currentWorld.cursorY-currentWorld.cameraY)
	else
		editor.window.setCursorBlink(false)
	end
end

------------------------------------------------
-- Argument Parsing / Main Logic
------------------------------------------------

local args = {...}
local filenames = {}

for i = 1, #args do
	local arg = args[i]
	if arg:find "^%-%-[%a-]+$" then

	else
		table.insert(filenames, arg)
	end
end

worlds = {}

for i = 1, #filenames do
	editor.open(filenames[i])
end

if #worlds == 0 then
	worlds[1] = World.open()
	tabs.switch(1)
end

local windowArgs = { term.current(), 1, 1, 1, 1 }
tabs.window   = window.create(unpack(windowArgs))
editor.window = window.create(unpack(windowArgs))
status.window = window.create(unpack(windowArgs))
editor.resizeWindows()

focus = "editor"

-- Main Event Loop
local lShift, rShift, lCtrl, rCtrl
while focus ~= "quit" do
	if currentWorld.needsUpdate then currentWorld:updateAll() end

	if tabs.needsDraw   then tabs.draw()   end
	if editor.needsDraw then editor.draw() end
	if status.needsDraw then status.draw() end

	(focus == "editor" and editor or status).grabCursor()

	local event, p1, p2, p3 = os.pullEvent()
	if event == "key" then
		if     p1 == keys.leftShift  then lShift = true
		elseif p1 == keys.rightShift then rShift = true
		elseif p1 == keys.leftCtrl   then lCtrl  = true
		elseif p1 == keys.rightCtrl  then rCtrl  = true
		end
	elseif event == "key_up" then
		if     p1 == keys.leftShift  then lShift = false
		elseif p1 == keys.rightShift then rShift = false
		elseif p1 == keys.leftCtrl   then lCtrl  = false
		elseif p1 == keys.rightCtrl  then rCtrl  = false
		end
	elseif event == "term_resize" then
		editor.resizeWindows()
	end
	(focus == "editor" and editor or status).handleEvent(
		event, p1, p2, p3, lShift or rShift, lCtrl or rCtrl)
end

-- Clear the terminal after the program exits
term.setCursorPos(1, 1)
term.clear()
