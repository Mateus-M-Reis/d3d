-- Render-target helpers for the d3d pipeline.
--
-- The scene target keeps lighting in a floating point colour buffer so the
-- tone mapper sees values above 1.0. The depth attachment is created as a
-- texture for future depth-based effects (SSAO, depth of field, fog).

local M = {}

local function depth_params(width, height)
    return {
        format = graphics.TEXTURE_FORMAT_DEPTH,
        width = width,
        height = height,
        min_filter = graphics.TEXTURE_FILTER_NEAREST,
        mag_filter = graphics.TEXTURE_FILTER_NEAREST,
        u_wrap = graphics.TEXTURE_WRAP_CLAMP_TO_EDGE,
        v_wrap = graphics.TEXTURE_WRAP_CLAMP_TO_EDGE,
        flags = render.TEXTURE_BIT,
    }
end

--- Creates the HDR scene target.
function M.create_scene(width, height, hdr)
    local color_format = graphics.TEXTURE_FORMAT_RGBA
    if hdr and graphics.TEXTURE_FORMAT_RGBA16F then
        color_format = graphics.TEXTURE_FORMAT_RGBA16F
    end

    local color = {
        format = color_format,
        width = width,
        height = height,
        min_filter = graphics.TEXTURE_FILTER_LINEAR,
        mag_filter = graphics.TEXTURE_FILTER_LINEAR,
        u_wrap = graphics.TEXTURE_WRAP_CLAMP_TO_EDGE,
        v_wrap = graphics.TEXTURE_WRAP_CLAMP_TO_EDGE,
    }

    return render.render_target({
        [graphics.BUFFER_TYPE_COLOR0_BIT] = color,
        [graphics.BUFFER_TYPE_DEPTH_BIT] = depth_params(width, height),
    })
end

--- Creates a square depth-only target used by one shadow cascade.
function M.create_shadow(resolution)
    return render.render_target({
        [graphics.BUFFER_TYPE_DEPTH_BIT] = depth_params(resolution, resolution),
    })
end

function M.delete(target)
    if target then
        render.delete_render_target(target)
    end
end

return M
