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
local World, tabs, status, theme, editor, focus, mode
----------------------------------------------------------------

------------------------------------------------
-- Worlds
------------------------------------------------

World = {}

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
					--sleep(100)
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
	},
	tabs = {
		["selected"] = { fg = "0", bg = "f" },
		["normal"]   = { fg = "f", bg = "7" },
	}
}

------------------------------------------------
-- Tab Bar
------------------------------------------------

tabs = {
	cameraX = 0
}

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

function tabs.getTabText(index)
	local world = worlds[index]
	return " "
		..(world.filepath and fs.getName(world.filepath) or "untitled")
		..(world.modified and "\007" or "")
		.." "
end

function tabs.switch(index)
	currentWorldIndex = math.min(#worlds, math.max(index, 1))
	currentWorld = worlds[currentWorldIndex]
	tabs.draw()
	editor.draw()
end

------------------------------------------------
-- Status Bar
------------------------------------------------

status = {
	messages = {}
}

function status.draw()
	local term  = status.window
	local width = term.getSize()

	term.setCursorPos(1, 1)
	term.clearLine()

	if #status.messages > 0 then
		local message, text = status.messages[1]
		if message.error then
			text = "\215 "..message.text
		else
			text = message.text
		end
		if text:len() > width then
			text = text:sub(1, width - 1).."\187"
		end
		term.write(text)
	else

	end
end

------------------------------------------------
-- Editor
------------------------------------------------

editor = {}

function editor.draw()
	local world = currentWorld
	local term = editor.window
	local width, height = term.getSize()
	local camX, camY = world.cameraX, world.cameraY
	local buffer = {}

	for y = 1, math.min(height-1, #world.lines-camY) do
		local line, tx, fg, bg = world.lines[y+camY], {}, {}, {}
		for x = 1, math.min(width, #line.text-camX) do
			local s = line.scopes[x+camX]
			tx[x] = line.text[x+camX]
			fg[x] = (theme.editor[s] or {}).fg or theme.editor.default.fg
			bg[x] = (theme.editor[s] or {}).bg or theme.editor.default.bg
		end
		buffer[y] = { tx = tx, fg = fg, bg = bg }
	end

	term.clear()
	for y = 1, #buffer do
		term.setCursorPos(1, y)
		term.blit(table.concat(buffer[y].tx)
		         ,table.concat(buffer[y].fg)
		         ,table.concat(buffer[y].bg))
	end

	if focus == "editor" and mode == "edit" then
		term.setCursorPos(world.cursorX-camX, world.cursorY-camY)
	end
end

function editor.rescanLibs()
	local inUse = {}

	local function addLibs(world)
		if world.needsUpdate then
			world:updateAll()
		end
		for filepath, _ in pairs(world.libs) do
			if not inUse[filepath] then
				inUse[filepath] = true
				if not worlds[filepath] then
					local lib, msg = World.open(filepath)
					if lib then
						editor.addWorld(lib)
					else
						-- Error, see msg for details
						return
					end
				end
				addLibs(worlds[filepath])
			end
		end
	end

	addLibs(worlds[1])

	-- Remove all of the unused worlds
	local i = 2
	while i <= #worlds do
		local world = worlds[i]
		if not inUse[world.filepath] and not world.modified then
			-- TODO: Replace with editor.closeWorld?
			editor.removeWorldByIndex(i)
		else
			i = i + 1
		end
	end
end

function editor.addWorld(world)
	table.insert(worlds, world)
	if world.filepath then
		worlds[world.filepath] = world
	end
end

function editor.getWorldByFilepath(filepath)
	return worlds[filepath]
end

function editor.getWorldByIndex(index)
	return worlds[index]
end

function editor.removeWorldByFilepath(filepath) 
	for i = 1, #worlds do
		if worlds[i] == worlds[filepath] then
			table.remove(worlds, i)
		end
	end
	worlds[filepath] = nil
end

function editor.removeWorldByIndex(index)
	if worlds[index].filepath then
		worlds[worlds[index].filepath] = nil
	end
	table.remove(worlds, index)
end

function editor.closeWorld(index)

end

function editor.handleEvent(e, p1, p2, p3)

end

function editor.takeFocus()
	focus = "editor"
	editor.window.restoreCursor()
	editor.window.setCursorBlink(mode == "edit")
end

------------------------------------------------
-- Argument Parsing / Main Logic
------------------------------------------------

local args = {...}
