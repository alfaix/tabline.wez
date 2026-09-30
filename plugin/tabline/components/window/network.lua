local wezterm = require('wezterm')

local last_update_time = 0
local last_result = ''
local last_rx, last_tx, last_uptime

local function read_file(path)
  local file = io.open(path, 'r')
  if not file then
    return nil
  end
  local content = file:read('*a')
  file:close()
  return content
end

-- Virtual interfaces (lo, bridges, docker, VPN tunnels) have no backing device;
-- skipping them avoids counting tunnelled traffic twice.
local function is_physical(interface)
  local file = io.open('/sys/class/net/' .. interface .. '/device/uevent', 'r')
  if not file then
    return false
  end
  file:close()
  return true
end

local function read_counters(interfaces)
  local dev = read_file('/proc/net/dev')
  if not dev then
    return nil
  end
  local rx, tx = 0, 0
  for name, stats in dev:gmatch('([^%s:|]+):([^\n]*)') do
    local selected
    if interfaces then
      selected = interfaces[name]
    else
      selected = is_physical(name)
    end
    if selected then
      local fields = {}
      for value in stats:gmatch('%d+') do
        fields[#fields + 1] = tonumber(value)
      end
      rx = rx + fields[1]
      tx = tx + fields[9]
    end
  end
  return rx, tx
end

local function format_rate(bytes_per_second)
  local units = { 'B/s', 'KB/s', 'MB/s', 'GB/s' }
  local i = 1
  while bytes_per_second >= 1000 and i < #units do
    bytes_per_second = bytes_per_second / 1024
    i = i + 1
  end
  return string.format('%.1f %s', bytes_per_second, units[i])
end

return {
  default_opts = {
    throttle = 3,
    icon = wezterm.nerdfonts.md_swap_vertical,
    interfaces = nil,
    down_icon = wezterm.nerdfonts.md_arrow_down,
    up_icon = wezterm.nerdfonts.md_arrow_up,
  },
  update = function(_, opts)
    if string.match(wezterm.target_triple, 'linux') == nil then
      return ''
    end
    local current_time = os.time()
    if current_time - last_update_time < opts.throttle then
      return last_result
    end

    local interfaces
    if opts.interfaces then
      interfaces = {}
      for _, name in ipairs(opts.interfaces) do
        interfaces[name] = true
      end
    end

    local rx, tx = read_counters(interfaces)
    local uptime = tonumber((read_file('/proc/uptime') or ''):match('^[%d.]+'))
    if not rx or not uptime then
      return ''
    end

    if last_uptime and uptime > last_uptime then
      local elapsed = uptime - last_uptime
      local down = math.max(0, rx - last_rx) / elapsed
      local up = math.max(0, tx - last_tx) / elapsed
      last_result = opts.down_icon .. ' ' .. format_rate(down) .. ' ' .. opts.up_icon .. ' ' .. format_rate(up)
    end

    last_rx, last_tx, last_uptime = rx, tx, uptime
    last_update_time = current_time

    return last_result
  end,
}
