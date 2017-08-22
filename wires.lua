----------------------------------------------------------------
-- WIRES: An AsciiDots IDE for ComputerCraft
--
-- Copyright (C) 2017 InternetUnexplorer
-- All rights reserved.
--
-- This software may be modified and distributed under the terms
-- of the MIT license.  See the LICENSE file for details.
----------------------------------------------------------------

local world

------------------------------------------------
-- Worlds
------------------------------------------------

local World = {}

function World.open(filename, parent)
	local world = {
		lines  = {},
		warps  = {},
		starts = {},

		filename = filename,
		parent   = parent,

		cursorX = 1, cursorY = 1,
		cameraX = 1, cameraY = 1,

		modified = false
	}

	if filename and fs.exists(filename) then
		world.isReadOnly = fs.isReadOnly(filename)
		
		local f = fs.open(filename, "r")

		if not f then
			return nil, "Cannot open file: "..filename
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
	local line = self.lines[line]
	local t = line.text
	local s = {}
	line.starts, line.warps, line.declaration = {}, {}

	local i = 1

	-- Declaration
	if t[1] == "%" then
		s[1] = "declaration"
		s[2] = "declaration"

		i = i + 3
		-- Warp declaration
		if t[2] == "$" then
			line.declaration = {
				type = "warp",
				warpNames = {}
			}
			-- Add the warp names
			while t[i] and t[i]:find "[A-Zb-z]" do
				table.insert(declaration.warpNames, t[i])
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
				i = i + 1
				s[i] = "declaration"
				line.declaration = {
					type = "lib",
					name = table.concat(name),
					warpName = t[i]
				}
			else
				s[i] = "invalid"
			end
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
		-- Other (invalid) declaration
		else
			s[1] = "invalid"
			s[2] = "invalid"
		end
	end

	while i < #t do
		local c = t[i]
		-- Whitespace
		if c == " " then
			s[i] = "whitespace"
		-- Comment
		elseif c == "`" and t[i] == "`" then
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
				line.scopes[warpXPos] = scope
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
						mark(warpXPos, "warp")
					end
				end
			elseif declaration.type == "lib" then
				local name = declaration.name
				local warpName = declaration.warpName
				local warpXPos = 2 + name:len() + 1 -- %!, name, and a space

				if self.warps[warpName] then
					mark(warpXPos, "invalid")
				else
					self.libs[name] = self.libs[name] or name
					self.warps[warpName] = {
						lib = libName,
						{
							x = warpXPos,
							y = i
						}
					}
					mark(warpXPos, "warp")
				end
			elseif declaration.type == "lib_warp" then
				local warpName = declaration.warpName
				local warpXPos = j + 2 -- %^

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
					mark(warpXPos, "warp")
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
				if not warp.libWarp or #warp < 2 then
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

	return changedLines
end

------------------------------------------------

-- local world, scopes

-- local theme = {
-- 	["default"]        = { fg = "0", bg = "f" },
-- 	["declaration"]    = { fg = "9" },
-- 	["comment"]        = { fg = "d" },
-- 	["string"]         = { fg = "d" },
-- 	["control"]        = { fg = "2" },
-- 	["operator_bound"] = { fg = "8" },
-- 	["operator"]       = { fg = "2" },
-- 	["start"]          = { fg = "3" },
-- 	["end"]            = { fg = "3" },
-- 	["digit"]          = { fg = "4" },
-- 	["data"]           = { fg = "3" },
-- 	["io"]             = { fg = "3" },
-- 	["warp"]           = { fg = "3" },
-- 	["invalid"]        = { fg = "0", bg = "e" },

-- 	["cursor"]         = { fg = "f", bg = "0" },
-- }

-- local cameraX, cameraY = 0, 0
-- local cursorX, cursorY = 1, 1
-- local cursorVisible = true

-- local function updateLine( lineNumber )
-- 	local l, s = world[lineNumber], {}

-- 	local oldWarpDecl, newWarpDecl
-- 	for k, v in pairs(world.warps) do
-- 		if v.decl == lineNumber then
-- 			oldWarpDecl = k
-- 		end
-- 		local i = 1
-- 		while i < #v do
-- 			if v[i].y == lineNumber then
-- 				table.remove(v, i)
-- 			else
-- 				i = i + 1
-- 			end
-- 		end
-- 	end

-- 	local i = 1
-- 	while i < #world.starts do
-- 		if world.starts[i].y == lineNumber then
-- 			table.remove(world.starts, i)
-- 		else
-- 			i = i + 1
-- 		end
-- 	end

-- 	i = 1
-- 	-- Declaration
-- 	if l[1] == "%" then
-- 		-- Warp declaration
-- 		if l[2] == "$" then
-- 			-- Check if warp name is valid
-- 			if (l[3] or ""):find("[A-Z]") then
-- 				-- Valid name, mark warp name as valid
-- 				newWarpDecl = l[3]
-- 				s[3] = "declaration"
-- 				-- Check if we have seen this warp before
-- 				local w = world.warps[l[3]]
-- 				if w then
-- 					-- We have seen this warp before, check where
-- 					if w.decl > lineNumber then
-- 						-- Declared on a line below this one
-- 						-- We want only the first declaration in the file to
-- 						-- be marked as valid, so change the declaration to
-- 						-- this line, and mark the line where it was
-- 						-- previously declared as needing an update
-- 						world[w.decl].needsUpdate = true
-- 						w.decl = lineNumber
-- 					elseif w.decl < lineNumber then
-- 						-- Declared on a line above this one
-- 						-- We want only the first declaration in the file to
-- 						-- be marked as valid, so mark this declaration as
-- 						-- invalid
-- 						s[3] = "invalid"
-- 					end
-- 				else
-- 					-- We haven't seen this warp before, add it to the table
-- 					world.warps[l[3]] = { decl = lineNumber }
-- 					-- We now have a new warp to look for when parsing, and so
-- 					-- every line needs to be updated
-- 					for j = 1, #world do
-- 						world[j].needsUpdate = true
-- 					end
-- 				end
-- 			else
-- 				-- Not a valid name, mark warp name as invalid
-- 				s[3] = "invalid"
-- 			end
-- 			s[1] = "declaration"
-- 			s[2] = "declaration"
-- 			i = i + 3
-- 		else
-- 			-- Other (unsupported) declaration, mark as invalid
-- 			s[1] = "invalid"
-- 			s[2] = "invalid"
-- 			i = i + 2
-- 		end
-- 	end
-- 	if oldWarpDecl and not newWarpDecl then
-- 		world.warps[oldWarpDecl] = nil
-- 		for j = 1, #world do
-- 			world[j].needsUpdate = true
-- 		end
-- 	end
-- 	while i <= #l do
-- 		local c = l[i]
-- 		-- Whitespace
-- 		if c == " " then
-- 			s[i] = "whitespace"
-- 		-- Comment
-- 		elseif c == "`" and l[i+1] == "`" then
-- 			-- Mark rest of line
-- 			repeat
-- 				s[i] = "comment"
-- 				i = i + 1
-- 			until i > #l
-- 		-- String
-- 		elseif c == "'" or c == '"' then
-- 			-- Mark rest of string
-- 			repeat
-- 				s[i] = "string"
-- 				i = i + 1
-- 			until l[i] == c or i > #l
-- 			-- Check whether we found a closing quote or hit EOL
-- 			if l[i] == c then
-- 				s[i] = "string"
-- 			else
-- 				s[i] = "invalid"
-- 			end
-- 		-- Path
-- 		elseif c:find "[|%-/\\%+><%^v%(%)]" then
-- 			s[i] = "path"
-- 		-- Control
-- 		elseif c == "~" or c == "!" or c == "*" then
-- 			s[i] = "control"
-- 		-- Operation
-- 		elseif c == "[" or c == "{" then
-- 			s[i] = "operator_bound"
-- 			-- Check if the next character is an operator
-- 			if (l[i+1] or ""):find "[%*%+%-%%%^/&!ox<>=\247\187\171\019]" then
-- 				s[i+1] = "operator"
-- 			else
-- 				s[i+1] = "invalid"
-- 			end
-- 			-- Check for a closing bound
-- 			if c == "[" and l[i+2] == "]"
-- 			or c == "{" and l[i+2] == "}" then
-- 				s[i+2] = "operator_bound"
-- 			else
-- 				s[i+2] = "invalid"
-- 			end
-- 			i = i + 2
-- 		-- Start
-- 		elseif c == "." or c == "\7" then
-- 			s[i] = "start"
-- 			table.insert(world.starts, { y = lineNumber, x = i })
-- 		-- End
-- 		elseif c == "&" then
-- 			s[i] = "end"
-- 		-- Digit
-- 		elseif c:find "%d" then
-- 			s[i] = "digit"
-- 		-- Address & value
-- 		elseif c == "@" or c == "#" then
-- 			s[i] = "data"
-- 		-- IO
-- 		elseif c:find "[%?%$_a]" then
-- 			s[i] = "io"
-- 		-- Warp
-- 		elseif world.warps[c] then
-- 			s[i] = "warp"
-- 			table.insert(world.warps[c], { y = lineNumber, x = i })
-- 		-- Other (invalid)
-- 		else
-- 			s[i] = "invalid"
-- 		end
-- 		i = i + 1
-- 	end
-- 	scopes[lineNumber] = s
-- 	-- This line has been updated, mark it as no longer needing an update
-- 	world[lineNumber].needsUpdate = false
-- end

-- local function updateScopes()
-- 	for i = 1, #world do
-- 		if world[i].needsUpdate then
-- 			updateLine(i)
-- 		end
-- 	end
-- end

-- local function render()
-- 	local buffer = {}
-- 	local width, height = term.getSize()
-- 	-- Draw world
-- 	for y = 1, height do
-- 		buffer[y] = { tx = {}, fg = {}, bg = {} }
-- 		for x = 1, width do
-- 			local c = (world[y+cameraY] or {})[x+cameraX]
-- 			local s = (scopes[y+cameraY] or {})[x+cameraX]
-- 			buffer[y].tx[x] = c or " "
-- 			buffer[y].fg[x] = (theme[s] or {}).fg or theme.default.fg
-- 			buffer[y].bg[x] = (theme[s] or {}).bg or theme.default.bg
-- 		end
-- 	end
-- 	-- Draw cursor
-- 	if cursorVisible then
-- 		local x, y = cursorX-cameraX, cursorY-cameraY
-- 		if x > 0 and x <= width and y > 0 and y <= height then
-- 			buffer[y].fg[x] = (theme["cursor"] or {}).fg or theme.default.fg
-- 			buffer[y].bg[x] = (theme["cursor"] or {}).bg or theme.default.bg
-- 		end
-- 	end
-- 	term.clear()
-- 	for y = 1, height do
-- 		term.setCursorPos(1, y)
-- 		term.blit(table.concat(buffer[y].tx)
-- 		         ,table.concat(buffer[y].fg)
--  		         ,table.concat(buffer[y].bg))
-- 	end
-- end

-- local function loadWorld(file)
-- 	world = { warps = {}, starts = {} }
-- 	scopes = {}
-- 	local f = fs.open(file, "r")
-- 	local l = f.readLine()
-- 	while l do
-- 		local line = { needsUpdate = true }
-- 		for i = 1, l:len() do
-- 			line[i] = l:sub(i, i)
-- 		end
-- 		table.insert(world, line)
-- 		l = f.readLine()
-- 	end
-- 	f.close()
-- end

-- loadWorld "world.dots"

-- local changed = true
-- local width, height = term.getSize()

-- local function moveCameraToCursor()
-- 	if cursorY-cameraY < 1 then
-- 		cameraY = cursorY - 1
-- 	elseif cursorY-cameraY > height then
-- 		cameraY = cursorY - height + 1
-- 	end
-- 	if cursorX-cameraX < 1 then
-- 		cameraX = cursorX - 1
-- 	elseif cursorX-cameraX > width then
-- 		cameraX = cursorX - width + 1
-- 	end
-- end

-- while true do
-- 	if changed then
-- 		updateScopes()
-- 	end
-- 	render()

-- 	local event, p1 = os.pullEvent()
-- 	if event == "key" then
-- 		if p1 == keys.up then
-- 			if cursorY > 1 then
-- 				cursorY = cursorY - 1
-- 				moveCameraToCursor()
-- 			end
-- 		elseif p1 == keys.down then
-- 			if cursorY < #world then
-- 				cursorY = cursorY + 1
-- 				moveCameraToCursor()
-- 			end
-- 		elseif p1 == keys.left then
-- 			if cursorX > 1 then
-- 				cursorX = cursorX - 1
-- 				moveCameraToCursor()
-- 			end
-- 		elseif p1 == keys.right then
-- 			if cursorX <= #world[cursorY] then
-- 				cursorX = cursorX + 1
-- 				moveCameraToCursor()
-- 			end
-- 		elseif p1 == keys.backspace then
-- 			if cursorX > 1 then
-- 				table.remove(world[cursorY], cursorX-1)
-- 				cursorX = cursorX - 1
-- 				world[cursorY].needsUpdate = true
-- 				changed = true
-- 				moveCameraToCursor()
-- 			else
-- 				if cursorY > 1 then
-- 					local l = #world[cursorY-1]
-- 					for i = 1, #world[cursorY] do
-- 						world[cursorY-1][i+l] = world[cursorY][i]
-- 					end
-- 					world[cursorY-1].needsUpdate = true
-- 					changed = true
-- 					table.remove(world, cursorY)
-- 					table.remove(scopes, cursorY)
-- 					cursorY = cursorY - 1
-- 					cursorX = l+1
-- 					moveCameraToCursor()
-- 				end
-- 			end
-- 		elseif p1 == keys.enter then
-- 			table.insert(world, cursorY+1, {})
-- 			table.insert(scopes, cursorY+1, {})
-- 			world[cursorY].needsUpdate = true
-- 			world[cursorY+1].needsUpdate = true
-- 			changed = true
-- 			while cursorX <= #world[cursorY] do
-- 				table.insert(world[cursorY+1],
-- 				             table.remove(world[cursorY], cursorX))
-- 			end
-- 			cursorY = cursorY + 1
-- 			cursorX = 1
-- 			moveCameraToCursor()
-- 		end
-- 	elseif event == "char" then
-- 		table.insert(world[cursorY], cursorX, p1)
-- 		world[cursorY].needsUpdate = true
-- 		changed = true
-- 		cursorX = cursorX + 1
-- 		moveCameraToCursor()
-- 	end
-- end
		-- 
		-- if context then
		-- 	if context == "`" then
		-- 		scope = "comment"
		-- 	elseif context == "'" or context == '"' then
		-- 		scope = "string"
		-- 		if char == context then
		-- 			-- End of the string, clear the scope
		-- 			context = nil
		-- 		end
		-- 	elseif context == "%" then

		-- 	elseif context == "[" or context == "{" then
		-- 		-- Check if this is a valid operator
		-- 		if char:find "[%*%+%-%%%^/&!ox<>=\247\187\171\019]" then
		-- 			scope = "operator"
		-- 		else
		-- 			scope = "invalid"
		-- 		end
		-- 		if context == "[" then
		-- 			context = "]"
		-- 		else
		-- 			context = "}"
		-- 		end
		-- 	elseif context == "]" or context == "}" then
		-- 		if char == context then
		-- 			scope = "operator_bound"
		-- 		else
		-- 			scope = "invalid"
		-- 		end
		-- 		context = nil
		-- 	end
		-- else

		-- 	elseif char:find "[|%-\\//%+><%^v%(%)]" then
		-- 		context = "path"
			-- or context == "string.double" and char == '"' then
			-- 	-- End of the string, clear the context
			-- 	context = nil
			-- elseif context == "operation.operator.vertical"
			--     or context == "operation.operator.horizontal" then
		 --    	-- If not a valid operator, mark this char as invalid
			-- 	if not char:find "[%*%+%-%%%^/&!ox<>=\247\187\171\019]" then
			-- 		scope = "invalid."..context
			-- 	end
			-- 	-- Next is the closing bound, set the context
			-- 	context = "operation.bound."..context:match "%a+$"\
			-- elseif context == "operation.bound.vertical" then
			-- 	-- If not a closing vertical bound, mark this char as invalid
			-- 	if char ~= "]" then
			-- 		scope = "invalid."..context
			-- 	end
			-- 	context = nil
			-- elseif context == "operation.bound.horizontal" then
			-- 	-- If not a closing horizontal bound, mark this char as invalid
			-- 	if char ~= "}" then
			-- 		scope = "invalid."..context
			-- 	end
			-- 	context = nil
			-- end
-- 		else
-- 			if char:find "[|%-/\]" then
-- 				scope = "path.regular"
-- 			end
-- 	end
-- end

-- local file = {}
-- local scopes = {}

-- local warps = {}
-- local startingPoints = {}

-- local cameraX, cameraY = 0, 0
-- local cursorX, cursorY = 1, 1

-- local theme

-- local scope = {
-- 	NONE     = "transparent",
-- 	COMMENT  = "comment",
-- 	STRING   = "string",
-- 	DECL     = "declaration",
-- 	PATH     = "path",
-- 	DATA     = "data",
-- 	IO       = "io",
-- 	CONTROL  = "control",
-- 	START    = "start",
-- 	END      = "end",
-- 	OPERATOR = "operator",
-- 	OP_BOUND = "operator_bound",
-- 	NUMBER   = "number",
-- 	WARP     = "warp",
-- 	INVALID  = "invalid",
-- }

-- local function genLookupTab(chars)
-- 	local t = {}
-- 	for i = 1, chars:len() do
-- 		t[chars:sub(i, i)] = true
-- 	end
-- 	return t
-- end

-- local pathCharacters     = genLookupTab "|-/\\+><^v()"
-- local operatorCharacters = genLookupTab "*/+-%^&!ox><=\187\171\019"

-- local function parseAll()
-- 	-- Clear tables for scopes, startingPoints, and warps
-- 	scopes, startingPoints, warps = {}, {}, {}
-- 	-- Loop through the lines in the file
-- 	for y = 1, #file do
-- 		-- Create an index in the scopes table for this line
-- 		scopes[y] = {}
-- 		-- Loop through the characters on this line
-- 		local x = 1
-- 		while x <= #file[y] do
-- 			local char = file[y][x]
-- 			-- Whitespace
-- 			if char == " " then
-- 				scopes[y][x] = Scope.NONE
-- 			-- Comment
-- 			elseif char == "`" and file[y][x+1] == "`" then
-- 				-- Mark rest of line as a comment
-- 				while x <= #file[y] do
-- 					scopes[y][x] = Scope.COMMENT
-- 					x = x + 1
-- 				end
-- 			-- String
-- 			elseif char == "'" or char == '"' then
-- 				-- Mark rest of string as a string
-- 				repeat
-- 					scopes[y][x] = Scope.STRING
-- 					x = x + 1
-- 				until file[y][x] == char or x > #file[y]
-- 				-- Check whether we found a closing quote or we ran off the
-- 				-- end of the line
-- 				if file[y][x] == char then
-- 					-- Mark closing quote as valid
-- 					scopes[y][x] = Scope.STRING
-- 				else
-- 					-- Mark previous character (last character on line) as
-- 					-- invalid
-- 					scopes[y][x-1] = Scope.INVALID
-- 				end
-- 			-- Path
-- 			elseif pathCharacters[char] then
-- 				scopes[y][x] = Scope.PATH
-- 			-- If and clone
-- 			elseif char == "~" or char == "*" then
-- 				scopes[y][x] = Scope.CONTROL
-- 			-- If not
-- 			elseif char == "!" and file[y-1][x] == "~"
-- 			and scopes[y-1][x] == Scope.CONTROL then
-- 				scopes[y][x] = Scope.CONTROL
-- 			-- Operator
-- 			elseif char == "[" or char == "{" then
-- 				-- Check if the character to the right (the operator) is valid
-- 				if operatorCharacters[file[y][x+1]] then
-- 					-- Check if the character on the right of the operator is
-- 					-- a closing bound
-- 					if (char == "[" and file[y][x+2] == "]")
-- 					or (char == "{" and file[y][x+2] == "}") then
-- 						-- Mark everything as valid
-- 						scopes[y][x]   = Scope.OP_BOUND
-- 						scopes[y][x+1] = Scope.OPERATOR
-- 						scopes[y][x+2] = Scope.OP_BOUND
-- 						-- Consume both bounds and the operator
-- 						x = x + 2
-- 					else
-- 						-- Mark the opening bound and the operator as invalid
-- 						scopes[y][x]   = Scope.INVALID
-- 						scopes[y][x+1] = Scope.INVALID
-- 						-- Consume the opening bound and the operator
-- 						x = x + 1
-- 					end
-- 				else
-- 					-- Not connected to a valid operator, mark the bound as
-- 					-- invalid
-- 					scopes[y][x] = Scope.INVALID
-- 				end
-- 			-- Program start
-- 			elseif char == "." or char == "\7" then
-- 				scopes[y][x] = Scope.START
-- 				-- Add this point to our startingPoints table
-- 				table.insert(startingPoints, { x = x, y = y })
-- 			-- Program end
-- 			elseif char == "&" then
-- 				scopes[y][x] = Scope.END
-- 			-- Digit
-- 			elseif char:find "%d" then
-- 				scopes[y][x] = Scope.NUMBER
-- 			-- Address and value
-- 			elseif char == "#" or char == "@" then
-- 				scopes[y][x] = Scope.DATA
-- 			-- IO
-- 			elseif char == "?" or char == "$"
-- 			or char == "_" or char == "a" then
-- 				scopes[y][x] = Scope.IO
-- 			-- Warp
-- 			elseif warps[char] and #warps[char] < 2 then
-- 				scopes[y][x] = Scope.WARP
-- 				-- Add this warp to our warps table
-- 				table.insert(warps[char], { x = x, y = y })
-- 			-- Declaration
-- 			elseif x == 1 and char == "%" then
-- 				-- Warp declaration
-- 				if file[y][x+1] == "$" and
-- 				string.find(file[y][x+2], "[A-Z]") then
-- 					-- Mark this as a valid warp declaration
-- 					scopes[y][x]   = Scope.DECL
-- 					scopes[y][x+1] = Scope.DECL
-- 					scopes[y][x+2] = Scope.WARP
-- 					-- Add this warp to the warps table
-- 					warps[file[y][x+2]] = {}
-- 					-- Consume the declaration
-- 					x = x + 2
-- 				-- Other (unsupported) declaration
-- 				else
-- 					scopes[y][x]   = Scope.INVALID
-- 					scopes[y][x+1] = Scope.INVALID
-- 					-- Consume invalid characters
-- 					x = x + 1
-- 				end
-- 			-- Other (invalid)
-- 			else
-- 				scopes[y][x] = Scope.INVALID
-- 			end
-- 			x = x + 1
-- 		end
-- 	end
-- end

-- local function draw()
-- 	-- We will draw to a buffer and then use term.blit to draw everything
-- 	local buffer = {}
-- 	-- Get the terminal dimensions
-- 	local width, height = term.getSize()
-- 	-- Loop through lines
-- 	for y = 1, math.min(height, #file-cameraY) do
-- 		-- Create the tables to store the colors for this line
-- 		buffer[y] = { tx = {}, fg = {}, bg = {} }
-- 		-- Loop through the characters on this line
-- 		for x = 1, math.min(width, #file[y]-cameraX) do
-- 			-- Set the text to the current character
-- 			buffer[y].tx[x] = file[y-cameraY][x-cameraX]
-- 			-- Store the scope in a local variable
-- 			local s = scopes[y-cameraY][x-cameraX]
-- 			-- Set the foreground and background colors to the ones for this
-- 			-- scope in the theme
-- 			buffer[y].fg[x] = (theme[s] or {}).fg or theme.default.fg
-- 			buffer[y].bg[x] = (theme[s] or {}).bg or theme.default.bg
-- 		end
-- 	end
-- 	--Clear the terminal before we draw anything
-- 	term.clear()
-- 	-- Draw the buffer
-- 	for y = 1, math.min(height, #file-cameraY) do
-- 		term.setCursorPos(1, y)
-- 		term.blit(table.concat(buffer[y].tx)
-- 		         ,table.concat(buffer[y].fg)
-- 		         ,table.concat(buffer[y].bg))
-- 	end
-- end

-- theme = {
-- 	default = { fg = "0", bg = "f" },
-- 	comment = { fg = "d" },
-- 	string  = { fg = "d" },
-- 	declaration = { fg = "9" },
-- 	data    = { fg = "a" },
-- 	io      = { fg = "5" },
-- 	control = { fg = "3" },
-- 	start   = { fg = "3" },
-- 	["end"] = { fg = "e" },
-- 	operator= { fg = "a" },
-- 	operator_bound = { fg = "8" },
-- 	number  = { fg = "1" },
-- 	warp    = { fg = "b" },
-- 	invalid = { fg = "0", bg = "e" },
-- }

-- file = {
-- 	{"%","$","A"," ","`","`","W","a","r","p"},
-- 	{".","-","{","^","}","-","&"}
-- }

-- parseAll()
-- draw()

-- local function updateScope()
-- 	scope = {}
-- 	-- Loop through the lines in the file
-- 	for y = 1, #world do
-- 		-- Create the color tables for this line
-- 		fg[y], bg[y] = {}, {}

-- 		-- Loop through each character on this line
-- 		for x = 1, #world[y] do
-- 			-- We'll store the color in this variable and add it to
-- 			-- the table(s) later
-- 			local color
-- 			-- Store the current character, as well as the characters
-- 			-- on all sides of it in local variables for easy access
-- 			local c, u, d, l, r
-- 			c = world[y][x]
-- 			u = world[y-1][x]
-- 			d = world[y+1][x]
-- 			l = world[y][x-1]
-- 			r = world[y][x+1]

-- 			-- Whitespace
-- 			if c == " " then
-- 				color = theme.TRANSPARENT
-- 			-- Program start and end
-- 			elseif c == "." or c == "&" then
-- 				color = theme.ENDPOINT
-- end

-- local function parse()
-- 	local world = {}
-- 	local startSymbols = {}

-- 	-- Iterate through the lines of the file
-- 	for y = 1, #file do
-- 		-- Iterate through the characters on a line
-- 		for x = 1, #file[y] do
-- 			-- Skip the character if it is a space
-- 			if file[y][x] ~= " " then
-- 				-- We will fill in this table with information
-- 				-- about the current symbol
-- 				local symbol = { x = x, y = y, t = nil }

-- 				-- Assign the current character to a local variable
-- 				-- for easier access
-- 				local char = file[y][x]

-- 				-- Some symbols are 'simple' (their type does not change
-- 				-- based on surrounding symbols), so we can use a table
-- 				-- to look them up. We will attempt to match the current
-- 				-- character against the table:
-- 				symbol.t = SymbolLookup[char]

-- 				if not symbol.t then
-- 					-- We couldn't find the symbol in the lookup table, so
-- 					-- we will attempt to match it here

-- 					-- Comment
-- 					if char == "`" and file[y][x+1] == "`" then
-- 						symbol.t = Symbol.COMMENT
-- 						-- Get the comment text
-- 						symbol.d = table.concat(file[y], nil, x+2)
-- 					-- Numeric constant
-- 					elseif char:find "%d" then
-- 						symbol.t = Symbol.DIGIT
-- 						symbol.d = 


-- 				local symbol = { x = x, y = y, t = Symbols.UNKNOWN }

-- 				-- Assign CENTER, UP, DOWN, LEFT, RIGHT characters
-- 				-- to local variables for easy access
-- 				local c = file[y][x]
-- 				local u = file[y-1][x]
-- 				local d = file[y+1][x]
-- 				local l = file[y][x-1]
-- 				local r = file[y][x+1]

-- 				-- Program start and end
-- 				if c == "." then
-- 					symbol.t
-- 				-- Comment
-- 				elseif 
					
-- 				-- Vertical Path
-- 				elseif c == "|" then
-- 					symbol.t = Symbol.VPATH
					



-- local Symbols = {
-- 	START     = "Program start",
-- 	END       = "Program end",
-- 	COMMENT   = "Comment",
-- 	VPATH     = "Vertical path",
-- 	HPATH     = "Horizontal path",
-- 	RMIRROR   = "Right mirror",
-- 	LMIRROR   = "Left mirror",
-- 	JUNCTION  = "Junction",
-- 	RFUNNEL   = "Right funnel",
-- 	LFUNNEL   = "Left funnel",
-- 	UFUNNEL   = "Upwards funnel",
-- 	DFUNNEL   = "Downwards funnel",
-- 	RDIODE    = "Right diode",
-- 	LDIODE    = "Left diode",
-- 	CLONE     = "Clone",
-- 	ADDR      = "Dot's address",
-- 	VALUE     = "Dot's value",
-- 	DIGIT     = "Digit",
-- 	OUTPUT    = "Output",
-- 	OUT_NEWL  = "Output: disable newline",
-- 	OUT_ASCII = "Output: to ascii",
-- 	INPUT     = "Input",
-- 	CONDITION = "Conditional",
-- 	INV_COND  = "Invert conditional",
-- 	OPERATION = "Operation",
-- 	WARP_DECL = "Warp declaration",
-- 	WARP_IN   = "Warp entry point",
-- 	WARP_OUT  = "Warp exit point",
-- 	UNKNOWN   = "Unknown symbol"
-- }

-- local SymbolLookup = {
-- 	["."] = Symbols.START,
-- 	["&"] = Symbols.END,
-- 	["|"] = Symbols.VPATH,
-- 	["-"] = Symbols.HPATH,
-- 	["/"] = Symbols.RMIRROR,
-- 	["\\"] = Symbols.LMIRROR,
-- 	["+"] = Symbols.JUNCTION,
-- 	[">"] = Symbols.RFUNNEL,
-- 	["<"] = Symbols.LFUNNEL,
-- 	["^"] = Symbols.UFUNNEL,
-- 	["v"] = Symbols.DFUNNEL,
-- 	["("] = Symbols.RDIODE,
-- 	[")"] = Symbols.LDIODE,
-- 	["*"] = Symbols.CLONE,
-- 	["@"] = Symbols.ADDR,
-- 	["#"] = Symbols.VALUE,
-- 	["$"] = Symbols.OUTPUT,
-- 	["?"] = Symbols.INPUT,
-- 	["~"] = Symbols.CONDITIONAL,
-- 	["!"] = Symbols.INV_COND
-- }

-- local Errors = {
-- 	OVER_CONNECTED = "Too many connections",
-- 	NOT_CONNECTED = "Not connected"
-- }

























-- local cursorVisible = false

-- local theme = {
-- 	default    = { fg = "0", bg = "f" },
-- 	comment    = { fg = "b" },
-- 	string     = { fg = "d" },
-- 	operator   = { fg = "3" },
-- 	brackets   = { fg = "8" },
-- 	path       = { fg = "0" },
-- 	digit      = { fg = "1" },
-- 	control    = { fg = "2" },
-- 	startpoint = { fg = "4" },
-- 	endpoint   = { fg = "4" },
-- 	io         = { fg = "5" },
-- 	warp       = { fg = "d" },
-- 	invalid    = { fg = "0", bg = "e" },
-- 	cursor     = { fg = "f", bg = "0" },
-- }

-- local symbolTypes = {}

-- local function render()
-- 	local width, height = term.getSize()
-- 	local buffer = {}

-- 	for y = 1, height do
-- 		buffer[y] = { tx = {}, fg = {}, bg = {} }
-- 		local scope

-- 		for x = 1, width+cameraX do
-- 			local char, color = world[y+cameraY][x] or " "

-- 			if char == " " then
-- 				color = theme.transparent
-- 			elseif scope then
-- 				if scope == "`" then
-- 					color = theme.comment
-- 				elseif scope == "'" or scope == '"' then
-- 					color = theme.string
-- 					if char == scope then
-- 						scope = nil
-- 					end
-- 				elseif scope == "[" or scope == "{" then
-- 					if char:find "[%*/%+%-%%%^&!ox>\187<\171=\19]" then
-- 						color = theme.operator
-- 						if scope == "[" then
-- 							scope = "]"
-- 						else
-- 							scope = "}"
-- 						end
-- 					else
-- 						color = theme.invalid
-- 						scope = nil
-- 					end
-- 				elseif scope == "]" or scope == "}" then
-- 					if char == scope then
-- 						color = theme.brackets
-- 					else
-- 						color = theme.invalid
-- 					end
-- 					scope = nil
-- 				end
-- 			else
-- 				if char:find "[|%-/\\%+><^v%(%)]" then
-- 					color = theme.path
-- 				elseif char == "`" and world[y+cameraY][x+1] == "`" then
-- 					scope = "`"
-- 					color = theme.comment
-- 				elseif char:find "%d" then
-- 					color = theme.digit
-- 				elseif char == "[" or char == "{" then
-- 					scope = char
-- 					color = theme.brackets
-- 				elseif char == "~" or char == "*" then
-- 					color = theme.control
-- 				elseif char == "!" and world[y+cameraY-1][x] == "~" then
-- 					color = theme.control
-- 				elseif char:find "[%?@#%$_a]" then
-- 					color = theme.io
-- 				elseif char == "." then
-- 					color = theme.startpoint
-- 				elseif char == "&" then
-- 					color = theme.endpoint
-- 				elseif char:find "[A-Z]" then
-- 					color = theme.warp
-- 				else
-- 					color = theme.invalid
-- 				end
-- 			end

-- 			if x >= cameraX then
-- 				buffer[y].tx[x-cameraX] = char
-- 				buffer[y].fg[x-cameraX] = (color or {}).fg or theme.default.fg
-- 				buffer[y].bg[x-cameraX] = (color or {}).bg or theme.default.bg
-- 			end
-- 		end
-- 	end

-- 	if cursorVisible then
-- 		buffer[cursorY-cameraY].fg[cursorX-cameraX] = (theme.cursor or {}).fg or theme.default.fg
-- 		buffer[cursorY-cameraY].bg[cursorX-cameraX] = (theme.cursor or {}).bg or theme.default.bg
-- 	end

-- 	for y = 1, height do
-- 		term.setCursorPos(1, y)
-- 		term.blit(table.concat(buffer[y].tx), table.concat(buffer[y].fg), table.concat(buffer[y].bg))
-- 	end
-- end

-- world = {
-- 	{" ", "[", "4", "]", "5"},
-- 	{"`", "`", " ", "h", "i"},
-- }

-- setmetatable(world, {
-- 	__index = function(t, k)
-- 		t[k] = {}
-- 		return t[k]
-- 	end
-- })

-- cursorVisible = true
-- render()

-- local w, h = term.getSize()
-- while true do
-- 	local event, p1, p2, p3 = os.pullEvent()
-- 	if event == "key" then
-- 		if p1 == 203 then
-- 			cursorX = cursorX - 1
-- 			if cursorX < 1 then
-- 				cursorX = 1
-- 			end
-- 		elseif p1 == 205 then
-- 			cursorX = cursorX + 1
-- 			if cursorX-cameraX > w then
-- 				cameraX = cameraX + 1
-- 			end
-- 		elseif p1 == 200 then
-- 			cursorY = cursorY + 1
-- 			if cursorY-cameraY > h then
-- 				cameraY = cameraY + 1
-- 			end
-- 		elseif p1 == 208 then
-- 			cursorY = cursorY - 1
-- 			if cursorX < 1 then cursorY = 1 end
-- 		end
-- 		render()
-- 	end
-- end