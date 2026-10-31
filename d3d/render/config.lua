-- d3d render configuration.
--
-- Values are read from game.project under the [d3d] section so a project can
-- tune the pipeline without touching Lua. Defaults keep the example working
-- even when the section is absent.

local config = {}

config.camera = sys.get_config_string("d3d.camera", "main:/camera#camera")
config.hdr = sys.get_config_number("d3d.hdr", 1) > 0
config.shadows = sys.get_config_number("d3d.shadows", 1) > 0
config.cascade_count = math.floor(sys.get_config_number("d3d.cascades", 3))
config.shadow_resolution = math.floor(sys.get_config_number("d3d.shadow_resolution", 1024))
config.shadow_lambda = sys.get_config_number("d3d.shadow_lambda", 0.75)
config.shadow_bias = sys.get_config_number("d3d.shadow_bias", 0.0008)
config.shadow_slope_bias = sys.get_config_number("d3d.shadow_slope_bias", 0.003)
config.exposure = sys.get_config_number("d3d.exposure", 1.0)
config.fog_density = sys.get_config_number("d3d.fog_density", 0.012)
config.fog_color_red = sys.get_config_number("d3d.fog_red", 0.55)
config.fog_color_green = sys.get_config_number("d3d.fog_green", 0.65)
config.fog_color_blue = sys.get_config_number("d3d.fog_blue", 0.8)
config.clear_red = sys.get_config_number("d3d.clear_red", 0.05)
config.clear_green = sys.get_config_number("d3d.clear_green", 0.06)
config.clear_blue = sys.get_config_number("d3d.clear_blue", 0.08)

config.cascade_count = math.max(1, math.min(3, config.cascade_count))
config.shadow_resolution = math.max(256, config.shadow_resolution)

return config
