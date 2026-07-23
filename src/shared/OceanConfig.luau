-- Shared ocean look + streaming knobs for Survive at Sea.
-- Terrain water carries the real waves; client FX add foam / underwater feel.

local OceanConfig = {
	-- Sea surface height (studs). Deck bottoms sit just above this.
	SurfaceY = 0.4,

	-- How deep the water voxels go below the surface.
	DepthStuds = 56,

	-- Streaming chunk grid around rafts / lobby (infinite sail).
	ChunkStuds = 256,
	-- Keep this many chunks in each direction from every focus point.
	KeepRadiusChunks = 3,
	-- How often the server refreshes which chunks stay filled.
	StreamHz = 2,

	-- Engine Terrain water material (the realistic wave field). Calm rolling
	-- swells (lower speed) read as a prettier open sea than the old fast chop.
	WaterColor = Color3.fromRGB(14, 92, 116),
	WaterReflectance = 0.85,
	WaterTransparency = 0.3,
	WaterWaveSize = 0.28,
	WaterWaveSpeed = 10,

	-- Soft abyss tint under the voxels (non-colliding visual only).
	AbyssColor = Color3.fromRGB(3, 28, 48),
	AbyssTransparency = 0.12,

	-- Client underwater look when the camera dips below the surface.
	Underwater = {
		Tint = Color3.fromRGB(28, 92, 118),
		Contrast = 0.08,
		Saturation = -0.12,
		Brightness = -0.04,
		FogColor = Color3.fromRGB(18, 70, 92),
		FogStart = 8,
		FogEnd = 90,
	},
}

return OceanConfig
