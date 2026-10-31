-- Cascaded shadow map fitting for a single directional light.
--
-- The math follows the standard "fit an orthographic light frustum around each
-- camera frustum slice" approach:
--
--   1. split the camera frustum into N slices using a practical split scheme;
--   2. compute the 8 world-space corners of each slice;
--   3. fit an orthographic light frustum around those corners;
--   4. snap the frustum centre to the shadow texel grid to reduce shimmering;
--   5. return a world -> shadow-texture matrix for the receiver shader.
--
-- Everything here is pure Lua/vmath so it can be unit tested outside the
-- render script.

local M = {}

local function compute_splits(near, far, count, lambda)
    local splits = {}
    for i = 1, count do
        local p = i / count
        local logarithmic = near * (far / near) ^ p
        local linear = near + (far - near) * p
        splits[i] = lambda * logarithmic + (1.0 - lambda) * linear
    end
    splits[count] = far
    return splits
end

local function slice_corners(inv_view, fov, aspect, near_distance, far_distance)
    local tan_half = math.tan(fov * 0.5)
    local corners = {}

    for _, distance in ipairs({ near_distance, far_distance }) do
        local half_height = tan_half * distance
        local half_width = half_height * aspect

        for _, sx in ipairs({ -1, 1 }) do
            for _, sy in ipairs({ -1, 1 }) do
                local p = inv_view * vmath.vector4(sx * half_width, sy * half_height, -distance, 1)
                corners[#corners + 1] = vmath.vector3(p.x, p.y, p.z)
            end
        end
    end

    return corners
end

local function fit_corners(corners, sun_direction, resolution, depth_padding)
    local center = vmath.vector3()
    for _, corner in ipairs(corners) do
        center = center + corner
    end
    center = center / #corners

    local radius = 0
    for _, corner in ipairs(corners) do
        radius = math.max(radius, vmath.length(corner - center))
    end

    local up = vmath.vector3(0, 1, 0)
    if math.abs(sun_direction.y) > 0.99 then
        up = vmath.vector3(0, 0, 1)
    end

    -- Put the light far enough behind the slice that every corner is in front
    -- of the near plane, with padding on both sides of the depth range.
    local eye = center - sun_direction * (radius + depth_padding)
    local view = vmath.matrix4_look_at(eye, center, up)

    local min_x, max_x = math.huge, -math.huge
    local min_y, max_y = math.huge, -math.huge
    local min_z, max_z = math.huge, -math.huge

    for _, corner in ipairs(corners) do
        local p = view * vmath.vector4(corner.x, corner.y, corner.z, 1)
        min_x = math.min(min_x, p.x)
        max_x = math.max(max_x, p.x)
        min_y = math.min(min_y, p.y)
        max_y = math.max(max_y, p.y)
        min_z = math.min(min_z, p.z)
        max_z = math.max(max_z, p.z)
    end

    local near_z = math.max(0.01, -max_z - depth_padding)
    local far_z = math.max(near_z + 1.0, -min_z + depth_padding)

    -- A square projection keeps the PCF texel footprint isotropic. Snapping
    -- the centre (not the bounds) to whole texels keeps the extents stable as
    -- the camera moves.
    local center_x = (min_x + max_x) * 0.5
    local center_y = (min_y + max_y) * 0.5
    local extent = math.max(max_x - min_x, max_y - min_y) * 0.5
    extent = math.max(extent, 0.01)

    local texel = (extent * 2.0) / resolution
    center_x = math.floor(center_x / texel + 0.5) * texel
    center_y = math.floor(center_y / texel + 0.5) * texel

    local projection = vmath.matrix4_orthographic(
        center_x - extent,
        center_x + extent,
        center_y - extent,
        center_y + extent,
        near_z,
        far_z
    )

    return view, projection
end

local function create_bias_matrix()
    local m = vmath.matrix4()
    m.c0 = vmath.vector4(0.5, 0.0, 0.0, 0.0)
    m.c1 = vmath.vector4(0.0, 0.5, 0.0, 0.0)
    m.c2 = vmath.vector4(0.0, 0.0, 0.5, 0.0)
    m.c3 = vmath.vector4(0.5, 0.5, 0.5, 1.0)
    return m
end

--- Builds the cascades for one frame.
-- @param camera_view matrix4 Camera view matrix (world -> view).
-- @param fov number Vertical field of view in radians.
-- @param aspect number Viewport aspect ratio.
-- @param near number Camera near plane.
-- @param far number Camera far plane.
-- @param sun_direction vector3 Normalized direction the sunlight travels.
-- @param options table { count, resolution, lambda, depth_padding }.
-- @return array of cascades with view, projection, frustum, matrix and split.
function M.compute(camera_view, fov, aspect, near, far, sun_direction, options)
    options = options or {}
    local count = options.count or 3
    local resolution = options.resolution or 1024
    local lambda = options.lambda or 0.75
    local depth_padding = options.depth_padding or 2.0

    local direction = vmath.normalize(sun_direction)
    local inv_view = vmath.inv(camera_view)
    local splits = compute_splits(near, far, count, lambda)
    local bias = create_bias_matrix()

    local cascades = {}
    local previous = near

    for i = 1, count do
        local split = splits[i]
        local corners = slice_corners(inv_view, fov, aspect, previous, split)
        local view, projection = fit_corners(corners, direction, resolution, depth_padding)

        cascades[i] = {
            view = view,
            projection = projection,
            frustum = projection * view,
            matrix = bias * projection * view,
            split = split,
            texel = 1.0 / resolution,
        }

        previous = split
    end

    return cascades, splits
end

return M
