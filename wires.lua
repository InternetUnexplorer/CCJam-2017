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
local World, Dot, tabs, status, theme, editor, focus, mode, program, key
----------------------------------------------------------------

------------------------------------------------
-- Worlds
------------------------------------------------

World = {}

-- Opens a world
-- If a filepath is specified, the world will be loaded from that file, and
-- if the save is successful, the world's filepath will be updated
-- If the file exists but cannot be loaded, nil and and error message will be
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
		return false, "File is read-only"
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
	self.starts, self.warps, self.libs, self.libWarp = {}, {}, {}
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
					self.libs[filepath] = true
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
		["view_mode"] = { fg = "0", bg = "f" },
		["edit_mode"] = { fg = "0", bg = "f" },
		["prompt"]    = { fg = "f", bg = "0" },
		["info_msg"]  = { fg = "0", bg = "f" },
		["error_msg"] = { fg = "0", bg = "e" },
		["confirm"]   = { fg = "0", bg = "1" },
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

function Dot:new(world, x, y)
	return setmetatable({
		world = world,
		x = x,
		y = y,
		warpStack = {}
	}, {
		__index = Dot
	})
end

function Dot:step()
	-- Starting (no direction yet)
	if not self.dir then
		if self:charAt(0, -1) == "|" then
			self.dir = { x = 0, y = -1 }
		elseif self:charAt(0, 1) == "|" then
			self.dir = { x = 0, y = 1 }
		elseif self:charAt(-1, 0) == "-" then
			self.dir = { x = -1, y = 0 }
		elseif self:charAt(1, 0) == "-" then
			self.dir = { x = 1, y = 0 }
		else
			self:die("No start")
		end
	-- Waiting
	elseif self.waiting then

	-- Moving
	else
		local char, scope = self:charAt()
		-- Nothing
		if not char then
			self:die()
		-- Right Mirror
		elseif char == "/" then
			self:move()
			self.dir.x, self.dir.y = self.dir.y, self.dir.x
		-- Left Mirror
		elseif char == "\\" then
			self:move()
			self.dir.x, self.dir.y = -self.dir.y, -self.dir.x
		-- Junction
		elseif char == "+" then
			self:move()
		-- Warp
		elseif self.world.warps[char] then
			local warp = self.world.warps[char]
			-- Warp to library
			if warp.lib then
				local lib = warp.lib
				if lib.loaded and lib.libWarp then
					table.insert(self.warpStack, {
						world = self.world,
						warpX = self.x,
						warpY = self.y
					})
				else
					self:die()
				end
			-- Warp from library
			elseif warp.libWarp then
				if #self.warpStack == 0 then
					-- No world to go back to D;
					self:die()
				else
					local elem = table.remove(self.warpStack)
					self.world = elem.world
					self.x, self.y = elem.warpX, elem.warpY
				end
			-- Regular warp
			else
				if #warp == 3 then
					-- Go to the other location
					if warp[2].x ~= self.x and warp[2].y ~= self.y then
						self.x, self.y = warp[2].x, warp[2].y
					else
						self.x, self.y = warp[3].x, warp[3].y
					end
				else
					-- Either too many or too few locations
					self:die()
				end
			end
		-- Horizontal symbols
		elseif self.dir.x ~= 0 then
			if char == "-" then
				self:move()
			elseif char == "^" or char == "v" then
				self:move()
				self.dir = { x = 0, y = char == "^" and 1 or -1 }
			elseif char == "(" or char == ")" then
				self:move()
				self.dir = { x = char == "(" and 1 or -1, y = 0 }
			else
				self:die()
			end
		-- Vertical symbols
		else

		end
	end
end

function Dot:move()
	self.x = self.x + self.dir.x
	self.y = self.y + self.dir.y
end

function Dot:charAt(deltaX, deltaY, includeString)
	deltaX, deltaY = deltaX or self.dir.x, deltaY or self.dir.y
	if self.world.lines[self.y+deltaY] then
		local line = self.world.lines[self.y+deltaY]
		local scope = line.scopes[self.y+deltaY]
		if scope ~= "comment" and scope ~= "invalid"
		and scope ~= "declaration" and scope ~= "whitespace"
		and (includeString or scope ~= "string") then
			return line.text[self.x+deltaX], scope
		end
	end
end

function Dot:die(msg)
	error("x: "..self.x..", y: "..self.y..", msg: "..(msg or "<nil>"))
	for i = 1, #self.world.dots do
		if self.world.dots[i] == self then
			table.remove(self.world.dots, i)
			break
		end
	end
end

------------------------------------------------
-- Program
------------------------------------------------

program = {}

function program.start()
	editor.rescanLibs()
	for i = 1, #worlds do
		local world = worlds[i]
		world.dots = {}
		for j = 1, #world.starts do
			local start = world.starts[j]
			table.insert(world.dots, Dot:new(world, start.x, start.y))
		end
	end
	program.isRunning = true
end

function program.step()
	for i = 1, #worlds[1].dots do
		worlds[1].dots[i]:step()
	end
end

function program.stop()
	program.isRunning = false
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
		local text = tabs.getTabText(i)
		local fgColor, bgColor
		if i == currentWorldIndex then
			if #tx - camX + text:len() > width then
				camX = width - text:len()
			end
			if #tx < camX-1 then
				camX = #tx-1
			end
			fgColor = theme.tabs.selected.fg
			bgColor = theme.tabs.selected.bg
		else
			fgColor = theme.tabs.normal.fg
			bgColor = theme.tabs.normal.bg
		end
		for j = 1, text:len() do
			table.insert(tx, text:sub(j, j))
			table.insert(fg, fgColor)
			table.insert(bg, bgColor)
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

-- Returns the text for the tab at index index
function tabs.getTabText(index)
	local world = worlds[index]
	return " "
		..(world.filepath and fs.getName(world.filepath) or "untitled")
		..(world.modified and "\007" or "")
		.." "
end

-- Switches to the tab at index index
function tabs.switch(index)
	currentWorldIndex = math.min(#worlds, math.max(index, 1))
	currentWorld = worlds[currentWorldIndex]
	tabs.needsDraw = true
	editor.needsDraw = true
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
		-- Set color and add glyphs
		if msg.isError then
			color = theme.status.error_msg
			text  = "\215 "..msg.text
		else
			color = theme.status.info_msg
			text  = msg.text
		end
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
			local pText, pBuf = prompt.text, prompt.buffer
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
	elseif status.mode == "confirm" then
		text  = status.confirm.text.." (y/n)"
		color = theme.status.confirm
	elseif status.mode == "normal" then
		local rText, lText
		-- Get the mode text
		if mode == "view" then
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
	-- Draw the text
	term.setCursorPos(1, 1)
	term.setTextColor(theme.toDecimal(color.fg))
	term.setBackgroundColor(theme.toDecimal(color.bg))
	term.clearLine()
	term.write(text)
end

-- Handles events when the status bar is focused
function status.handleEvent(event, p1, p2, p3, shiftDown, ctrlDown, altDown)
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
	if submit and prompt.onSubmit then
		prompt.onSubmit(not prompt.isConfirm and table.concat(prompt.buffer))
	elseif not submit and prompt.onCancel then
		prompt.onCancel()
	end
	-- If the onSubmit or onCancel functions opened another prompt then pass
	-- it our returnFocus instead of returning the focus
	-- If we don't do this then the focus may be returned while in a prompt!
	if status.prompt then
		status.prompt.returnFocus = prompt.returnFocus
	else
		focus = prompt.returnFocus
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
		status.needsDraw = true
	end
end

-- Cycles to the next message, or sets the mode back to normal if there are
-- no more messages in the queue
function status.nextMessage()
	table.remove(status.messages)
	if #status.messages == 0 then
		status.mode = "normal"
	end
	status.needsDraw = true
end

-- Clears all of the messages in the queue and sets the mode back to normal
function status.clearMessages()
	status.messages = {}
	status.mode = "normal"
	status.needsDraw = true
end

-- Grabs the cursor, as it may have been moved while drawing other areas of
-- the screen
function status.grabCursor()
	if status.mode == "prompt" and not status.prompt.isConfirm then
		status.window.restoreCursor()
		status.window.setCursorBlink(true)
		local p = status.prompt
		status.window.setCursorPos(p.cursorX - p.cameraX + p.text:len(), 1)
	else
		status.window.setCursorBlink(false)
	end
end

------------------------------------------------
-- Editor
------------------------------------------------

editor = {}

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

-- Loads worlds which are required but not yet loaded, and removes worlds
-- which are no longer required and have not been modified
function editor.rescanLibs()
	local inUse = {}

	local function addLibs(world)
		-- Update the world first
		if world.needsUpdate then
			world:updateAll()
		end
		-- Iterate through each of the libs this world uses
		for filepath, _ in pairs(world.libs) do
			if not inUse[filepath] then
				inUse[filepath] = true
				if not worlds[filepath] then
					-- World not loaded yet, load it here
					local lib, msg = World.open(filepath)
					if lib then
						editor.addWorld(lib)
					else
						-- Loading failed
						return
					end
				end
				-- Check libs for this world
				addLibs(worlds[filepath])
			end
		end
	end

	-- Add the libraries used by the first world
	addLibs(worlds[1])

	-- Remove all of the unused worlds
	local i = 2
	while i <= #worlds do
		local world = worlds[i]
		if world.filepath and not inUse[world.filepath] then
			if not world.modified then
				editor.closeWorld(i)
			end
		else
			i = i + 1
		end
	end
end

-- Adds a world to the worlds table
function editor.addWorld(world)
	table.insert(worlds, world)
	if world.filepath then
		worlds[world.filepath] = world
	end
end

-- Returns the world with filepath filepath in the worlds table
function editor.getWorldByFilepath(filepath)
	return worlds[filepath]
end

-- Returns the world at index index in the worlds table
function editor.getWorldByIndex(index)
	return worlds[index]
end

-- Removes a world from the worlds table by its filepath
function editor.removeWorldByFilepath(filepath) 
	for i = 1, #worlds do
		if worlds[i] == worlds[filepath] then
			table.remove(worlds, i)
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

-- Closes the world at index index, prompting the user if the world has
-- unsaved changes
function editor.closeWorld(index)

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
	status.showPrompt("Save as: ", false,
		function(filepath) -- onSubmit
			if fs.exists(filepath) then
				status.showPrompt("File exists, overwrite?", true, function()
					editor.save(filepath)
				end)
			else
				editor.save(filepath)
			end
		end
	)
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
	(mode == "edit" and editor.moveCursor or editor.moveCamera)(x, y)
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

-- Handles events when the editor is focused
function editor.handleEvent(event, p1, p2, p3, shiftDown, ctrlDown, altDown)
	local world = currentWorld
	local curX, curY = world.cursorX, world.cursorY
	local line  = world.lines[curY]
	local text  = line.text

	if event == "key" then
		if ctrlDown then
			if p1 == keys.s then
				if shiftDown then editor.saveAs() else editor.save() end
			end
		else
			if     p1 == keys.tab   then -- NYI, Mode switch
			elseif p1 == keys.up    then editor.move(0, -1)
			elseif p1 == keys.down  then editor.move(0,  1)
			elseif p1 == keys.left  then editor.move(-1, 0)
			elseif p1 == keys.right then editor.move(1,  0)

			elseif mode == "edit" then
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
		if mode == "edit" then editor.insert(p1) end
	end
end

-- Grabs the cursor, as it may have been moved while drawing other areas of
-- the screen
function editor.grabCursor()
	if mode == "edit" then
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

-- Testing :)

worlds = {
	World.open("world.dots")
}

currentWorldIndex = 1
currentWorld = worlds[currentWorldIndex]

local width, height = term.getSize()
tabs.window = window.create(term.current(), 1, 1, width, 1)
editor.window = window.create(term.current(), 1, 2, width, height-2)
status.window = window.create(term.current(), 1, height, width, 1)

focus, mode = "editor", "edit"

tabs.needsDraw = true
editor.needsDraw = true
status.needsDraw = true

local lShift, rShift, lCtrl, rCtrl, lAlt, rAlt

-- Main event loop
while true do
	if currentWorld.needsUpdate then currentWorld:updateAll() end

	if tabs.needsDraw   then tabs.draw()   end
	if editor.needsDraw then editor.draw() end
	if status.needsDraw then status.draw() end

	(focus == "editor" and editor or status).grabCursor()

	local event, p1, p2, p3, skip = os.pullEvent()
	if event == "key" then
		if     p1 == keys.leftShift  then lShift = true
		elseif p1 == keys.rightShift then rShift = true
		elseif p1 == keys.leftCtrl   then lCtrl  = true
		elseif p1 == keys.rightCtrl  then rCtrl  = true
		elseif p1 == keys.leftAlt    then lAlt   = true
		elseif p1 == keys.rightAlt   then rAlt   = true
		end
	elseif event == "key_up" then
		if     p1 == keys.leftShift  then lShift = false
		elseif p1 == keys.rightShift then rShift = false
		elseif p1 == keys.leftCtrl   then lCtrl  = false
		elseif p1 == keys.rightCtrl  then rCtrl  = false
		elseif p1 == keys.leftAlt    then lAlt   = false
		elseif p1 == keys.rightAlt   then rAlt   = false
		end
	elseif event == "term_resize" then
		local width, height = term.getSize()
		tabs.window.reposition(1, 1, width, 1)
		editor.window.reposition(1, 2, width, height-2)
		status.window.reposition(1, height, width, 1)
		tabs.needsDraw = true
		editor.needsDraw = true
		status.needsDraw = true
		skip = true
	end
	if not skip then
		(focus == "editor" and editor or status)
		.handleEvent(event, p1, p2, p3,
			lShift or rShift, lCtrl or rCtrl, lAlt or rAlt)
	end
end
