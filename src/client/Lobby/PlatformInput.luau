-- Cross-platform helpers for phone, tablet, computer, console, and VR.

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local VRService = game:GetService("VRService")

local PlatformInput = {}

function PlatformInput.getDeviceKind(): "Phone" | "Tablet" | "Computer" | "Console" | "VR"
	if VRService.VREnabled then
		return "VR"
	end
	if GuiService:IsTenFootInterface() then
		return "Console"
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		local camera = workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(800, 600)
		local minSide = math.min(viewport.X, viewport.Y)
		if minSide >= 700 then
			return "Tablet"
		end
		return "Phone"
	end
	return "Computer"
end

function PlatformInput.isGamepadPreferred(): boolean
	return GuiService:IsTenFootInterface()
		or UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled and not UserInputService.TouchEnabled
end

function PlatformInput.applySafeArea(guiObject: GuiObject)
	local insets = GuiService:GetGuiInset()
	-- Top inset already applied by ScreenGui IgnoreGuiInset=false; add side padding for notches / TV overscan.
	local padding = Instance.new("UIPadding")
	padding.Name = "SafeAreaPadding"
	padding.PaddingTop = UDim.new(0, math.max(8, insets.Y))
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = guiObject
end

function PlatformInput.scaleForDevice(): number
	local kind = PlatformInput.getDeviceKind()
	if kind == "Phone" then
		return 1.05
	elseif kind == "Tablet" then
		return 1.0
	elseif kind == "Console" or kind == "VR" then
		return 1.15
	end
	return 1.0
end

return PlatformInput
