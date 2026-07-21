-- Generates short, shareable party codes (Dead Rails-style).

local HttpService = game:GetService("HttpService")

local PartyCode = {}

local ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

local function randomChar(): string
	local index = math.random(1, #ALPHABET)
	return string.sub(ALPHABET, index, index)
end

function PartyCode.generate(existing: { [string]: any }?): string
	for _ = 1, 40 do
		local code = `{randomChar()}{randomChar()}{randomChar()}{randomChar()}`
		if not existing or existing[code] == nil then
			return code
		end
	end

	-- Extremely unlikely fallback
	return string.upper(string.sub(HttpService:GenerateGUID(false), 1, 4))
end

function PartyCode.normalize(raw: string): string
	local cleaned = string.upper(string.gsub(raw, "%s+", ""))
	cleaned = string.gsub(cleaned, "[^A-Z0-9]", "")
	return cleaned
end

return PartyCode
