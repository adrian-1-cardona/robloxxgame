--!nocheck
-- Compiles every Luau source file in the project.
--
--   lune run tests/Syntax.spec.luau
--
-- Roblox scripts cannot be executed outside Studio, but they can be COMPILED anywhere, so
-- this catches syntax errors, unbalanced blocks and typos in edits to the big service files
-- without waiting for a Studio sync.

local fs = require("@lune/fs")
local process = require("@lune/process")

local ROOTS = { "src", "tests" }

local function collect(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			collect(path, out)
		elseif string.match(name, "%.luau$") then
			table.insert(out, path)
		end
	end
	return out
end

print("\nSurvive at Sea · Luau syntax check\n")

local files: { string } = {}
for _, root in ROOTS do
	if fs.isDir(root) then
		collect(root, files)
	elseif fs.isDir(`../{root}`) then
		collect(`../{root}`, files)
	end
end
table.sort(files)

local failed = 0
for _, path in files do
	local chunk, err = loadstring(fs.readFile(path), "@" .. path)
	if chunk then
		print(`  OK    {path}`)
	else
		failed += 1
		print(`  FAIL  {path}\n        {err}`)
	end
end

print(`\n{#files - failed}/{#files} files compile\n`)
if failed > 0 then
	process.exit(1)
end
